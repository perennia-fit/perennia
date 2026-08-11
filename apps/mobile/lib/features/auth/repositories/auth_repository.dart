import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../api/perennia_api_client.dart';

const defaultAuthServerUrl = String.fromEnvironment(
  'PERENNIA_DEFAULT_SERVER_URL',
  defaultValue: 'https://open-workout-logger-server.onrender.com',
);
const _googleClientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
const _googleServerClientId = String.fromEnvironment(
  'GOOGLE_OAUTH_SERVER_CLIENT_ID',
  defaultValue: _googleClientId,
);
const _authSessionTokenKey = 'auth.session.token';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FileAuthRepository.openDefault();
});

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

abstract interface class AuthRepository {
  Future<AuthState> load();

  Future<AuthState> saveServerUrl(Uri serverUrl);

  Future<AuthSession> signInWithEmail({
    required Uri serverUrl,
    required String email,
    required String password,
  });

  Future<AuthSignUpOutcome> signUpWithEmail({
    required Uri serverUrl,
    required String name,
    required String email,
    required String password,
  });

  Future<void> resendVerificationEmail({
    required Uri serverUrl,
    required String email,
  });

  Future<AuthSession> signInWithSocial({
    required Uri serverUrl,
    required AuthSocialProvider provider,
  });

  Future<AuthState> signOut();
}

typedef AuthApiClientFactory = PerenniaApiClient Function(Uri baseUrl);

abstract interface class SocialIdTokenProvider {
  Future<SocialIdToken> idTokenFor(AuthSocialProvider provider);
}

abstract interface class AuthSessionTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> delete();
}

class SecureAuthSessionTokenStore implements AuthSessionTokenStore {
  SecureAuthSessionTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() {
    return _storage.read(key: _authSessionTokenKey);
  }

  @override
  Future<void> write(String token) {
    return _storage.write(key: _authSessionTokenKey, value: token);
  }

  @override
  Future<void> delete() {
    return _storage.delete(key: _authSessionTokenKey);
  }
}

class UnsupportedSocialIdTokenProvider implements SocialIdTokenProvider {
  const UnsupportedSocialIdTokenProvider();

  @override
  Future<SocialIdToken> idTokenFor(AuthSocialProvider provider) {
    throw AuthException('${provider.label} sign-in is not configured.');
  }
}

class DeviceSocialIdTokenProvider implements SocialIdTokenProvider {
  static Future<void>? _googleInitialize;

  @override
  Future<SocialIdToken> idTokenFor(AuthSocialProvider provider) {
    return switch (provider) {
      AuthSocialProvider.google => _googleIdToken(),
      AuthSocialProvider.apple => _appleIdToken(),
    };
  }

  Future<SocialIdToken> _googleIdToken() async {
    if (_googleClientId.isEmpty && _googleServerClientId.isEmpty) {
      throw const AuthException(
        'Google sign-in is not configured for this build.',
      );
    }
    try {
      await _initializeGoogle();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const AuthException('Google sign-in is not supported here.');
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('Google did not return an ID token.');
      }
      return SocialIdToken(token: idToken);
    } on AuthException {
      rethrow;
    } on GoogleSignInException catch (error) {
      throw AuthException(_googleSignInMessage(error));
    } on PlatformException catch (error) {
      throw AuthException(_platformSignInMessage('Google', error));
    }
  }

  Future<void> _initializeGoogle() {
    return _googleInitialize ??= GoogleSignIn.instance.initialize(
      clientId: _emptyToNull(_googleClientId),
      serverClientId: _emptyToNull(_googleServerClientId),
    );
  }

  Future<SocialIdToken> _appleIdToken() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final identityToken = credential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw const AuthException('Apple did not return an identity token.');
    }
    return SocialIdToken(token: identityToken);
  }
}

class FileAuthRepository implements AuthRepository {
  FileAuthRepository({
    required Future<File> Function() authFile,
    AuthApiClientFactory? apiClientFactory,
    SocialIdTokenProvider? socialIdTokenProvider,
    AuthSessionTokenStore? tokenStore,
  })  : _authFile = authFile,
        _apiClientFactory = apiClientFactory ?? _defaultApiClient,
        _socialIdTokenProvider =
            socialIdTokenProvider ?? DeviceSocialIdTokenProvider(),
        _tokenStore = tokenStore ?? SecureAuthSessionTokenStore();

  factory FileAuthRepository.openDefault({
    AuthApiClientFactory? apiClientFactory,
    SocialIdTokenProvider? socialIdTokenProvider,
    AuthSessionTokenStore? tokenStore,
  }) {
    return FileAuthRepository(
      authFile: _defaultAuthFile,
      apiClientFactory: apiClientFactory,
      socialIdTokenProvider: socialIdTokenProvider,
      tokenStore: tokenStore,
    );
  }

  final Future<File> Function() _authFile;
  final AuthApiClientFactory _apiClientFactory;
  final SocialIdTokenProvider _socialIdTokenProvider;
  final AuthSessionTokenStore _tokenStore;

  @override
  Future<AuthState> load() async {
    try {
      final file = await _authFile();
      if (!await file.exists()) {
        return AuthState.defaults;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final legacySessionToken = _legacySessionToken(decoded);
        final state = AuthState.fromJson(
          decoded,
          sessionToken: await _readStoredSessionToken() ?? legacySessionToken,
        );
        if (legacySessionToken != null && state.session != null) {
          await _save(state);
        } else if (decoded['session'] is Map<String, Object?> &&
            state.session == null) {
          await _saveMetadata(
            AuthState(serverUrl: state.serverUrl),
          );
        }
        return state;
      }
    } on Object {
      return AuthState.defaults;
    }
    return AuthState.defaults;
  }

  @override
  Future<AuthState> saveServerUrl(Uri serverUrl) async {
    final next =
        (await load()).copyWith(serverUrl: normalizeServerUrl(serverUrl));
    await _save(next);
    return next;
  }

  @override
  Future<AuthSession> signInWithEmail({
    required Uri serverUrl,
    required String email,
    required String password,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final client = _apiClientFactory(normalizedServerUrl);
    try {
      final response = await client.signInEmail(
        email: email.trim(),
        password: password,
        callbackURL: _emailVerificationCallbackUrl(
          normalizedServerUrl,
        ).toString(),
      );
      final session = AuthSession(
        provider: AuthSessionProvider.email,
        serverUrl: normalizedServerUrl,
        token: response.token,
        userEmail: response.user.email,
        userId: response.user.id,
        userName: response.user.name,
      );
      await _save(AuthState(serverUrl: normalizedServerUrl, session: session));
      return session;
    } on ApiException catch (error) {
      throw _emailSignInException(error);
    } finally {
      client.close();
    }
  }

  @override
  Future<AuthSignUpOutcome> signUpWithEmail({
    required Uri serverUrl,
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final client = _apiClientFactory(normalizedServerUrl);
    try {
      final response = await client.signUpWithEmailAndPassword(
        name: name.trim(),
        email: email.trim(),
        password: password,
        callbackURL: _emailVerificationCallbackUrl(
          normalizedServerUrl,
        ).toString(),
      );
      final token = response.token;
      final session = token == null || token.isEmpty
          ? null
          : AuthSession(
              provider: AuthSessionProvider.email,
              serverUrl: normalizedServerUrl,
              token: token,
              userEmail: response.user.email,
              userId: response.user.id,
              userName: response.user.name,
            );
      await _save(AuthState(serverUrl: normalizedServerUrl, session: session));
      return AuthSignUpOutcome(
        serverUrl: normalizedServerUrl,
        userEmail: response.user.email,
        session: session,
      );
    } on ApiException catch (error) {
      throw _emailSignUpException(error);
    } finally {
      client.close();
    }
  }

  @override
  Future<void> resendVerificationEmail({
    required Uri serverUrl,
    required String email,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final client = _apiClientFactory(normalizedServerUrl);
    try {
      await client.sendVerificationEmail(
        email: email.trim(),
        callbackURL: _emailVerificationCallbackUrl(
          normalizedServerUrl,
        ).toString(),
      );
      await saveServerUrl(normalizedServerUrl);
    } on ApiException catch (error) {
      throw _resendVerificationEmailException(error);
    } finally {
      client.close();
    }
  }

  @override
  Future<AuthSession> signInWithSocial({
    required Uri serverUrl,
    required AuthSocialProvider provider,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    final idToken = await _socialIdTokenProvider.idTokenFor(provider);
    final client = _apiClientFactory(normalizedServerUrl);
    try {
      final response = await client.socialSignIn(
        provider: provider.id,
        idToken: idToken,
        disableRedirect: true,
      );
      final token = response.token;
      final user = response.user;
      if (token == null || token.isEmpty || user == null) {
        throw const AuthException('Social sign-in did not return a session.');
      }
      final session = AuthSession(
        provider: provider.sessionProvider,
        serverUrl: normalizedServerUrl,
        token: token,
        userEmail: user.email,
        userId: user.id,
        userName: user.name,
      );
      await _save(AuthState(serverUrl: normalizedServerUrl, session: session));
      return session;
    } on ApiException catch (error) {
      throw _socialSignInException(provider, error);
    } finally {
      client.close();
    }
  }

  @override
  Future<AuthState> signOut() async {
    final current = await load();
    final next = AuthState(serverUrl: current.serverUrl);
    final session = current.session;
    if (session != null) {
      final client = _apiClientFactory(current.serverUrl);
      try {
        await client.signOut(bearerToken: session.token);
      } on Object {
        // Local sign-out must still complete when the server is unreachable.
      } finally {
        client.close();
      }
    }
    await _save(next);
    return next;
  }

  Future<String?> _readStoredSessionToken() async {
    try {
      return await _tokenStore.read();
    } on Object {
      return null;
    }
  }

  Future<void> _save(AuthState state) async {
    final session = state.session;
    if (session == null) {
      await _tokenStore.delete();
    } else {
      await _tokenStore.write(session.token);
    }
    await _saveMetadata(state);
  }

  Future<void> _saveMetadata(AuthState state) async {
    final file = await _authFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  static Future<File> _defaultAuthFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(path.join(directory.path, 'auth_session.json'));
  }

  static String? _legacySessionToken(Map<String, Object?> json) {
    final session = json['session'];
    if (session is! Map<String, Object?>) {
      return null;
    }
    final token = session['token'];
    return token is String && token.isNotEmpty ? token : null;
  }
}

class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository([AuthState? initial])
      : _state = initial ?? AuthState.defaults;

  AuthState _state;
  final emailAttempts = <AuthAttempt>[];
  final signUpAttempts = <AuthSignUpAttempt>[];
  final verificationEmailAttempts = <AuthVerificationEmailAttempt>[];
  final socialAttempts = <SocialAuthAttempt>[];
  final signOutAttempts = <Uri>[];

  @override
  Future<AuthState> load() async => _state;

  @override
  Future<AuthState> saveServerUrl(Uri serverUrl) async {
    _state = _state.copyWith(serverUrl: normalizeServerUrl(serverUrl));
    return _state;
  }

  @override
  Future<AuthSession> signInWithEmail({
    required Uri serverUrl,
    required String email,
    required String password,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    emailAttempts.add(
      AuthAttempt(
        serverUrl: normalizedServerUrl,
        email: email,
        password: password,
      ),
    );
    final session = AuthSession(
      provider: AuthSessionProvider.email,
      serverUrl: normalizedServerUrl,
      token: 'memory-email-token',
      userEmail: email,
      userId: 'memory-user',
      userName: email.split('@').first,
    );
    _state = AuthState(serverUrl: normalizedServerUrl, session: session);
    return session;
  }

  @override
  Future<AuthSignUpOutcome> signUpWithEmail({
    required Uri serverUrl,
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    signUpAttempts.add(
      AuthSignUpAttempt(
        serverUrl: normalizedServerUrl,
        name: name,
        email: email,
        password: password,
      ),
    );
    _state = AuthState(serverUrl: normalizedServerUrl);
    return AuthSignUpOutcome(
      serverUrl: normalizedServerUrl,
      userEmail: email,
    );
  }

  @override
  Future<void> resendVerificationEmail({
    required Uri serverUrl,
    required String email,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    verificationEmailAttempts.add(
      AuthVerificationEmailAttempt(
        serverUrl: normalizedServerUrl,
        email: email,
      ),
    );
    _state = AuthState(serverUrl: normalizedServerUrl);
  }

  @override
  Future<AuthSession> signInWithSocial({
    required Uri serverUrl,
    required AuthSocialProvider provider,
  }) async {
    final normalizedServerUrl = normalizeServerUrl(serverUrl);
    socialAttempts.add(
      SocialAuthAttempt(serverUrl: normalizedServerUrl, provider: provider),
    );
    final session = AuthSession(
      provider: provider.sessionProvider,
      serverUrl: normalizedServerUrl,
      token: 'memory-${provider.id}-token',
      userEmail: '${provider.id}@example.com',
      userId: 'memory-${provider.id}-user',
      userName: provider.label,
    );
    _state = AuthState(serverUrl: normalizedServerUrl, session: session);
    return session;
  }

  @override
  Future<AuthState> signOut() async {
    signOutAttempts.add(_state.serverUrl);
    _state = AuthState(serverUrl: _state.serverUrl);
    return _state;
  }
}

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() {
    return ref.watch(authRepositoryProvider).load();
  }

  Future<void> saveServerUrl(String rawServerUrl) async {
    final serverUrl = parseServerUrl(rawServerUrl);
    final next =
        await ref.read(authRepositoryProvider).saveServerUrl(serverUrl);
    state = AsyncData<AuthState>(next);
  }

  Future<void> signInWithEmail({
    required String rawServerUrl,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading<AuthState>();
    try {
      _validateEmailSignInInput(email: email, password: password);
      final session = await ref.read(authRepositoryProvider).signInWithEmail(
            serverUrl: parseServerUrl(rawServerUrl),
            email: email,
            password: password,
          );
      state = AsyncData<AuthState>(
        AuthState(serverUrl: session.serverUrl, session: session),
      );
    } on Object catch (error, stackTrace) {
      state = AsyncError<AuthState>(error, stackTrace);
    }
  }

  Future<AuthSignUpOutcome?> signUpWithEmail({
    required String rawServerUrl,
    required String name,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading<AuthState>();
    try {
      _validateEmailSignUpInput(name: name, email: email, password: password);
      final outcome = await ref.read(authRepositoryProvider).signUpWithEmail(
            serverUrl: parseServerUrl(rawServerUrl),
            name: name,
            email: email,
            password: password,
          );
      state = AsyncData<AuthState>(
        AuthState(serverUrl: outcome.serverUrl, session: outcome.session),
      );
      return outcome;
    } on Object catch (error, stackTrace) {
      state = AsyncError<AuthState>(error, stackTrace);
      return null;
    }
  }

  Future<bool> resendVerificationEmail({
    required String rawServerUrl,
    required String email,
  }) async {
    state = const AsyncLoading<AuthState>();
    try {
      _validateEmailAddress(email);
      final serverUrl = parseServerUrl(rawServerUrl);
      await ref.read(authRepositoryProvider).resendVerificationEmail(
            serverUrl: serverUrl,
            email: email,
          );
      state = AsyncData<AuthState>(AuthState(serverUrl: serverUrl));
      return true;
    } on Object catch (error, stackTrace) {
      state = AsyncError<AuthState>(error, stackTrace);
      return false;
    }
  }

  Future<void> signInWithSocial({
    required String rawServerUrl,
    required AuthSocialProvider provider,
  }) async {
    state = const AsyncLoading<AuthState>();
    try {
      final session = await ref.read(authRepositoryProvider).signInWithSocial(
            serverUrl: parseServerUrl(rawServerUrl),
            provider: provider,
          );
      state = AsyncData<AuthState>(
        AuthState(serverUrl: session.serverUrl, session: session),
      );
    } on Object catch (error, stackTrace) {
      state = AsyncError<AuthState>(error, stackTrace);
    }
  }

  Future<void> signOut() async {
    final next = await ref.read(authRepositoryProvider).signOut();
    state = AsyncData<AuthState>(next);
  }
}

@immutable
class AuthState {
  const AuthState({
    required this.serverUrl,
    this.session,
  });

  factory AuthState.fromJson(
    Map<String, Object?> json, {
    String? sessionToken,
  }) {
    final serverUrl = json['serverUrl'];
    return AuthState(
      serverUrl: serverUrl is String
          ? parseServerUrl(serverUrl)
          : Uri.parse(defaultAuthServerUrl),
      session: json['session'] is Map<String, Object?>
          ? _authSessionFromJson(
              json['session']! as Map<String, Object?>,
              token: sessionToken,
            )
          : null,
    );
  }

  static final defaults = AuthState(
    serverUrl: Uri.parse(defaultAuthServerUrl),
  );

  final Uri serverUrl;
  final AuthSession? session;

  bool get isSignedIn => session != null;

  AuthState copyWith({
    Uri? serverUrl,
    AuthSession? session,
    bool clearSession = false,
  }) {
    return AuthState(
      serverUrl: serverUrl ?? this.serverUrl,
      session: clearSession ? null : session ?? this.session,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'serverUrl': serverUrl.toString(),
      if (session != null) 'session': session!.toJson(),
    };
  }
}

@immutable
class AuthSession {
  const AuthSession({
    required this.provider,
    required this.serverUrl,
    required this.token,
    required this.userEmail,
    required this.userId,
    required this.userName,
  });

  factory AuthSession.fromJson(
    Map<String, Object?> json, {
    String? token,
  }) {
    return AuthSession(
      provider: _enumValue(
        AuthSessionProvider.values,
        json['provider'],
        AuthSessionProvider.email,
      ),
      serverUrl: json['serverUrl'] is String
          ? parseServerUrl(json['serverUrl']! as String)
          : Uri.parse(defaultAuthServerUrl),
      token: token ?? _requiredString(json, 'token'),
      userEmail: _requiredString(json, 'userEmail'),
      userId: _requiredString(json, 'userId'),
      userName: _requiredString(json, 'userName'),
    );
  }

  final AuthSessionProvider provider;
  final Uri serverUrl;
  final String token;
  final String userEmail;
  final String userId;
  final String userName;

  Map<String, Object?> toJson({bool includeToken = false}) {
    return <String, Object?>{
      'provider': provider.name,
      'serverUrl': serverUrl.toString(),
      if (includeToken) 'token': token,
      'userEmail': userEmail,
      'userId': userId,
      'userName': userName,
    };
  }
}

AuthSession? _authSessionFromJson(
  Map<String, Object?> json, {
  String? token,
}) {
  final jsonToken = json['token'];
  final resolvedToken =
      token ?? (jsonToken is String && jsonToken.isNotEmpty ? jsonToken : null);
  if (resolvedToken == null) {
    return null;
  }
  try {
    return AuthSession.fromJson(json, token: resolvedToken);
  } on FormatException {
    return null;
  }
}

@immutable
class AuthAttempt {
  const AuthAttempt({
    required this.serverUrl,
    required this.email,
    required this.password,
  });

  final Uri serverUrl;
  final String email;
  final String password;
}

@immutable
class SocialAuthAttempt {
  const SocialAuthAttempt({
    required this.serverUrl,
    required this.provider,
  });

  final Uri serverUrl;
  final AuthSocialProvider provider;
}

@immutable
class AuthSignUpAttempt {
  const AuthSignUpAttempt({
    required this.serverUrl,
    required this.name,
    required this.email,
    required this.password,
  });

  final Uri serverUrl;
  final String name;
  final String email;
  final String password;
}

@immutable
class AuthVerificationEmailAttempt {
  const AuthVerificationEmailAttempt({
    required this.serverUrl,
    required this.email,
  });

  final Uri serverUrl;
  final String email;
}

@immutable
class AuthSignUpOutcome {
  const AuthSignUpOutcome({
    required this.serverUrl,
    required this.userEmail,
    this.session,
  });

  final Uri serverUrl;
  final String userEmail;
  final AuthSession? session;

  bool get requiresEmailVerification => session == null;
}

enum AuthSocialProvider {
  google,
  apple;

  String get id => name;

  String get label {
    return switch (this) {
      AuthSocialProvider.google => 'Google',
      AuthSocialProvider.apple => 'Apple',
    };
  }

  AuthSessionProvider get sessionProvider {
    return switch (this) {
      AuthSocialProvider.google => AuthSessionProvider.google,
      AuthSocialProvider.apple => AuthSessionProvider.apple,
    };
  }
}

enum AuthSessionProvider {
  email,
  google,
  apple;
}

class AuthException implements Exception {
  const AuthException(
    this.message, {
    this.code = AuthFailureCode.unknown,
  });

  final String message;
  final AuthFailureCode code;

  @override
  String toString() => message;
}

enum AuthFailureCode {
  unknown,
  validation,
  invalidCredentials,
  emailNotVerified,
  rateLimited,
  unavailable,
}

Uri parseServerUrl(String rawValue) {
  return normalizeServerUrl(Uri.parse(rawValue.trim()));
}

Uri normalizeServerUrl(Uri uri) {
  if (!uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw const FormatException(
        'Server URL must start with http:// or https://.');
  }
  if (uri.scheme == 'http' && !kDebugMode) {
    throw const FormatException(
      'Server URL must use https:// in production builds.',
    );
  }
  if (uri.host.isEmpty) {
    throw const FormatException('Server URL must include a host.');
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw const FormatException('Server URL cannot include query or fragment.');
  }
  return uri.replace(path: _normalizedBasePath(uri.path), query: null);
}

PerenniaApiClient _defaultApiClient(Uri baseUrl) {
  return PerenniaApiClient(baseUrl: baseUrl);
}

String _normalizedBasePath(String path) {
  if (path.isEmpty) {
    return '/';
  }
  return path.endsWith('/') ? path : '$path/';
}

String? _emptyToNull(String value) {
  return value.isEmpty ? null : value;
}

Uri _emailVerificationCallbackUrl(Uri serverUrl) {
  return serverUrl.resolve('/auth/verified');
}

AuthException _emailSignInException(ApiException error) {
  return switch (error.statusCode) {
    400 || 401 => const AuthException(
        'Invalid email or password.',
        code: AuthFailureCode.invalidCredentials,
      ),
    403 => const AuthException(
        'Check your email to verify your account before signing in.',
        code: AuthFailureCode.emailNotVerified,
      ),
    429 => const AuthException(
        'Too many sign-in attempts. Try again later.',
        code: AuthFailureCode.rateLimited,
      ),
    503 => const AuthException(
        'Email sign-in is temporarily unavailable.',
        code: AuthFailureCode.unavailable,
      ),
    404 => const AuthException(
        'Server URL does not look like a Perennia server.',
        code: AuthFailureCode.unavailable,
      ),
    _ => const AuthException('Email sign-in failed.'),
  };
}

AuthException _emailSignUpException(ApiException error) {
  return switch (error.statusCode) {
    400 => const AuthException(
        'Check the sign-up fields and try again.',
        code: AuthFailureCode.validation,
      ),
    429 => const AuthException(
        'Too many sign-up attempts. Try again later.',
        code: AuthFailureCode.rateLimited,
      ),
    503 => const AuthException(
        'Email sign-up is temporarily unavailable.',
        code: AuthFailureCode.unavailable,
      ),
    404 => const AuthException(
        'Server URL does not look like a Perennia server.',
        code: AuthFailureCode.unavailable,
      ),
    _ => const AuthException('Email sign-up failed.'),
  };
}

AuthException _resendVerificationEmailException(ApiException error) {
  return switch (error.statusCode) {
    429 => const AuthException(
        'Too many verification email requests. Try again later.',
        code: AuthFailureCode.rateLimited,
      ),
    503 => const AuthException(
        'Verification email is temporarily unavailable.',
        code: AuthFailureCode.unavailable,
      ),
    404 => const AuthException(
        'Server URL does not look like a Perennia server.',
        code: AuthFailureCode.unavailable,
      ),
    _ => const AuthException('Could not send a verification email.'),
  };
}

AuthException _socialSignInException(
  AuthSocialProvider provider,
  ApiException error,
) {
  return switch (error.statusCode) {
    429 => const AuthException(
        'Too many sign-in attempts. Try again later.',
        code: AuthFailureCode.rateLimited,
      ),
    503 => AuthException(
        '${provider.label} sign-in is temporarily unavailable.',
        code: AuthFailureCode.unavailable,
      ),
    404 => const AuthException(
        'Server URL does not look like a Perennia server.',
        code: AuthFailureCode.unavailable,
      ),
    _ => AuthException('${provider.label} sign-in failed.'),
  };
}

void _validateEmailSignInInput({
  required String email,
  required String password,
}) {
  _validateEmailAddress(email);
  if (password.isEmpty) {
    throw const AuthException(
      'Enter your password.',
      code: AuthFailureCode.validation,
    );
  }
}

void _validateEmailSignUpInput({
  required String name,
  required String email,
  required String password,
}) {
  if (name.trim().isEmpty) {
    throw const AuthException(
      'Enter your name.',
      code: AuthFailureCode.validation,
    );
  }
  _validateEmailAddress(email);
  if (password.length < 8) {
    throw const AuthException(
      'Use at least 8 characters for your password.',
      code: AuthFailureCode.validation,
    );
  }
  if (password.length > 128) {
    throw const AuthException(
      'Use 128 characters or fewer for your password.',
      code: AuthFailureCode.validation,
    );
  }
}

void _validateEmailAddress(String email) {
  final trimmedEmail = email.trim();
  final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!emailPattern.hasMatch(trimmedEmail)) {
    throw const AuthException(
      'Enter a valid email address.',
      code: AuthFailureCode.validation,
    );
  }
}

String _googleSignInMessage(GoogleSignInException error) {
  return switch (error.code) {
    GoogleSignInExceptionCode.canceled => 'Google sign-in was cancelled.',
    GoogleSignInExceptionCode.clientConfigurationError ||
    GoogleSignInExceptionCode.providerConfigurationError =>
      _withOptionalDetail(
        'Google sign-in is not configured for this build.',
        error.description,
      ),
    GoogleSignInExceptionCode.uiUnavailable =>
      'Google sign-in UI is not available right now.',
    GoogleSignInExceptionCode.interrupted =>
      'Google sign-in was interrupted. Try again.',
    GoogleSignInExceptionCode.userMismatch =>
      'Google sign-in returned a different user than expected.',
    _ => _withOptionalDetail('Google sign-in failed.', error.description),
  };
}

String _platformSignInMessage(String provider, PlatformException error) {
  final detail = error.message;
  return _withOptionalDetail('$provider sign-in failed.', detail);
}

String _withOptionalDetail(String fallback, String? detail) {
  if (detail == null || detail.trim().isEmpty) {
    return fallback;
  }
  return '$fallback ${detail.trim()}';
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('$key must be a non-empty string.');
}

T _enumValue<T extends Enum>(
  Iterable<T> values,
  Object? rawValue,
  T fallback,
) {
  if (rawValue is! String) {
    return fallback;
  }
  for (final value in values) {
    if (value.name == rawValue) {
      return value;
    }
  }
  return fallback;
}
