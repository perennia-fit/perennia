import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../../sync/controllers/sync_status_controller.dart';
import '../repositories/auth_repository.dart';

/// Sign in, sign up, and the Account view of the current session.
///
/// A stored session is not proof the server still accepts it: when the last
/// Sync Run was rejected as unauthorized, sync status is
/// [SyncStatusKind.authExpired] and this screen says the sign-in expired
/// instead of "Signed in as". **Sign in again** shows the sign-in form over the
/// expired session without signing out first, so backing out leaves the device
/// exactly as it was, and success replaces only the session: local data and
/// unsynced changes stay put, and the next Sync Run pushes them.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.signInAgain = false});

  /// Opens straight onto the sign-in form when the session has expired, for
  /// callers whose own button already said "Sign in again".
  final bool signInAgain;

  /// The route every "Sign in again" button pushes.
  static Route<void> signInAgainRoute() => MaterialPageRoute<void>(
        builder: (_) => const SignInScreen(signInAgain: true),
      );

  static const routeName = '/sign-in';
  static const serverUrlFieldKey = Key('auth.serverUrl');
  static const authModeKey = Key('auth.mode');
  static const nameFieldKey = Key('auth.name');
  static const emailFieldKey = Key('auth.email');
  static const passwordFieldKey = Key('auth.password');
  static const emailSignInButtonKey = Key('auth.emailSignIn');
  static const emailSignUpButtonKey = Key('auth.emailSignUp');
  static const googleSignInButtonKey = Key('auth.googleSignIn');
  static const appleSignInButtonKey = Key('auth.appleSignIn');
  static const resendVerificationEmailButtonKey =
      Key('auth.resendVerificationEmail');
  static const signOutButtonKey = Key('auth.signOut');
  static const signInAgainButtonKey = Key('auth.signInAgain');
  static const cancelSignInAgainButtonKey = Key('auth.cancelSignInAgain');
  static const sessionExpiredNoticeKey = Key('auth.sessionExpiredNotice');
  static const sessionStatusKey = Key('auth.sessionStatus');
  static const noticeTextKey = Key('auth.notice');
  static const errorTextKey = Key('auth.error');

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _serverUrlController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _AuthFormMode _formMode = _AuthFormMode.signIn;
  bool _serverUrlEdited = false;
  String? _noticeText;
  String? _verificationEmailAddress;

  /// The sign-in form is showing over an expired session.
  late bool _signingInAgain = widget.signInAgain;

  /// The session this screen just signed in again with, for the "Signed in
  /// again" notice.
  String? _signedInAgainToken;

  /// Set when Sign in again succeeds and cleared by the first sync status
  /// recorded after it. The old verdict is dropped when the session changes,
  /// but that lands a moment after the new session does, and until then the
  /// status on screen is still about the old session. Any status written after
  /// that (the clear, or the new session's own Sync Run outcome, even when the
  /// clear failed or the stream skipped straight to a new rejection) is about
  /// the new session and shows.
  bool _awaitingFreshVerdict = false;

  /// The sync status on screen when Sign in again succeeded: the old
  /// session's verdict, which [_awaitingFreshVerdict] hides.
  SyncStatusState? _statusAtSignInAgain;

  /// The email field was prefilled for this Sign in again, so a user who
  /// clears it to type another address does not get the old one back.
  bool _emailPrefilled = false;

  /// An auth error the user has already backed out of (Cancel, or leaving
  /// the screen), so going back into Sign in again does not show it as if it
  /// were new.
  Object? _dismissedError;

  @override
  void initState() {
    super.initState();
    // The auth controller outlives this screen, so an error from an attempt
    // made on an earlier visit would otherwise greet a fresh Sign in again
    // form before the user has typed anything.
    if (widget.signInAgain) {
      _dismissedError = ref.read(authControllerProvider).error;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authValue = ref.watch(authControllerProvider);
    final authState = authValue.value ?? AuthState.defaults;
    final session = authState.session;
    final isLoading = authValue.isLoading;
    final authError =
        identical(authValue.error, _dismissedError) ? null : authValue.error;
    final verdictExpired = ref.watch(sessionExpiredProvider);
    ref.listen<AsyncValue<SyncStatusState>>(syncStatusControllerProvider, (
      _,
      next,
    ) {
      final status = next.value;
      if (_awaitingFreshVerdict &&
          status != null &&
          !identical(status, _statusAtSignInAgain)) {
        setState(() {
          _awaitingFreshVerdict = false;
          _statusAtSignInAgain = null;
        });
      }
    });
    final sessionExpired = verdictExpired && !_awaitingFreshVerdict;
    final signingInAgain = session != null && sessionExpired && _signingInAgain;
    final resendEmailAddress =
        signingInAgain ? null : _resendVerificationEmailAddress(authError);

    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
      final nextSession = next.value?.session;
      if (!signingInAgain ||
          nextSession == null ||
          nextSession.token == previous?.value?.session?.token) {
        return;
      }
      setState(() {
        _signingInAgain = false;
        _signedInAgainToken = nextSession.token;
        _awaitingFreshVerdict = true;
        _statusAtSignInAgain = ref.read(syncStatusControllerProvider).value;
        _passwordController.clear();
      });
    });

    if (signingInAgain && !_emailPrefilled) {
      _emailPrefilled = true;
      if (_emailController.text.isEmpty) {
        _emailController.text = session.userEmail;
      }
    }

    if (!_serverUrlEdited &&
        _serverUrlController.text != authState.serverUrl.toString()) {
      _serverUrlController.text = authState.serverUrl.toString();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          session == null || signingInAgain ? 'Sign in' : 'Account',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: session == null || signingInAgain
              ? [
                  if (signingInAgain)
                    ..._signInAgainHeader(
                      context: context,
                      isLoading: isLoading,
                    ),
                  ..._signedOutContent(
                    context: context,
                    authError: authError,
                    isLoading: isLoading,
                    resendEmailAddress: resendEmailAddress,
                    signingInAgain: signingInAgain,
                  ),
                ]
              : _signedInContent(
                  context: context,
                  session: session,
                  serverUrl: authState.serverUrl,
                  isLoading: isLoading,
                  sessionExpired: sessionExpired,
                ),
        ),
      ),
    );
  }

  List<Widget> _signedOutContent({
    required BuildContext context,
    required Object? authError,
    required bool isLoading,
    required String? resendEmailAddress,
    required bool signingInAgain,
  }) {
    return [
      TextField(
        key: SignInScreen.serverUrlFieldKey,
        controller: _serverUrlController,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Server URL',
        ),
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        onChanged: (_) {
          _serverUrlEdited = true;
        },
        onSubmitted: (value) {
          // Over an expired session, saving the URL would point the stored
          // server away from the session's own before the user has signed
          // in, and Cancel would not undo it. Signing in saves it instead.
          if (signingInAgain) {
            return;
          }
          unawaited(
            ref.read(authControllerProvider.notifier).saveServerUrl(
                  value,
                ),
          );
        },
      ),
      // Sign in again only signs in. Signing up, or asking for a
      // verification email, would replace the expired session with none.
      if (!signingInAgain) ...[
        const SizedBox(height: AppDimens.base),
        SegmentedButton<_AuthFormMode>(
          key: SignInScreen.authModeKey,
          segments: const [
            ButtonSegment<_AuthFormMode>(
              value: _AuthFormMode.signIn,
              icon: Icon(Icons.login),
              label: Text('Sign in'),
            ),
            ButtonSegment<_AuthFormMode>(
              value: _AuthFormMode.signUp,
              icon: Icon(Icons.person_add_alt),
              label: Text('Sign up'),
            ),
          ],
          selected: {_formMode},
          onSelectionChanged: isLoading
              ? null
              : (selection) {
                  setState(() {
                    _formMode = selection.single;
                    _noticeText = null;
                    _verificationEmailAddress = null;
                  });
                },
        ),
      ],
      if (_formMode == _AuthFormMode.signUp) ...[
        const SizedBox(height: AppDimens.base),
        TextField(
          key: SignInScreen.nameFieldKey,
          controller: _nameController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Name',
          ),
          autofillHints: const [AutofillHints.name],
          textInputAction: TextInputAction.next,
        ),
      ],
      const SizedBox(height: AppDimens.base),
      TextField(
        key: SignInScreen.emailFieldKey,
        controller: _emailController,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Email',
        ),
        autofillHints: const [AutofillHints.email],
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: AppDimens.dense),
      TextField(
        key: SignInScreen.passwordFieldKey,
        controller: _passwordController,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Password',
          helperText: _formMode == _AuthFormMode.signUp
              ? 'Use at least 8 characters. Passphrases work well.'
              : null,
        ),
        autofillHints: const [AutofillHints.password],
        enableSuggestions: false,
        autocorrect: false,
        obscureText: true,
        onSubmitted: (_) => _submitEmail(),
      ),
      const SizedBox(height: AppDimens.base),
      FilledButton.icon(
        key: _formMode == _AuthFormMode.signIn
            ? SignInScreen.emailSignInButtonKey
            : SignInScreen.emailSignUpButtonKey,
        onPressed: isLoading ? null : _submitEmail,
        icon: Icon(
          _formMode == _AuthFormMode.signIn
              ? Icons.mail_outline
              : Icons.person_add_alt,
        ),
        label: Text(
          _formMode == _AuthFormMode.signIn ? 'Sign in' : 'Sign up',
        ),
      ),
      const SizedBox(height: AppDimens.dense),
      OutlinedButton.icon(
        key: SignInScreen.googleSignInButtonKey,
        onPressed: isLoading
            ? null
            : () => _signInWithSocial(AuthSocialProvider.google),
        icon: const Icon(Icons.g_mobiledata),
        label: const Text('Continue with Google'),
      ),
      const SizedBox(height: AppDimens.dense),
      OutlinedButton.icon(
        key: SignInScreen.appleSignInButtonKey,
        onPressed: isLoading
            ? null
            : () => _signInWithSocial(AuthSocialProvider.apple),
        icon: const Icon(Icons.apple),
        label: const Text('Continue with Apple'),
      ),
      if (resendEmailAddress != null) ...[
        const SizedBox(height: AppDimens.dense),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: SignInScreen.resendVerificationEmailButtonKey,
            onPressed: isLoading
                ? null
                : () => _resendVerificationEmail(resendEmailAddress),
            icon: const Icon(Icons.mark_email_unread_outlined),
            label: const Text('Resend verification email'),
          ),
        ),
      ],
      if (_noticeText != null) ...[
        const SizedBox(height: AppDimens.base),
        Text(
          _noticeText!,
          key: SignInScreen.noticeTextKey,
          style: context.textStyles.body,
        ),
      ],
      if (authError != null) ...[
        const SizedBox(height: AppDimens.base),
        Text(
          _errorMessage(authError),
          key: SignInScreen.errorTextKey,
          style: context.textStyles.body.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    ];
  }

  List<Widget> _signedInContent({
    required BuildContext context,
    required AuthSession session,
    required Uri serverUrl,
    required bool isLoading,
    required bool sessionExpired,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      Icon(
        sessionExpired
            ? Icons.person_off_outlined
            : Icons.account_circle_outlined,
        size: AppDimens.touchTarget,
        color: sessionExpired ? colorScheme.error : colorScheme.primary,
      ),
      const SizedBox(height: AppDimens.base),
      Text(
        session.userName,
        textAlign: TextAlign.center,
        style: context.textStyles.h2,
      ),
      const SizedBox(height: AppDimens.dense),
      Text(
        sessionExpired
            ? 'Sign-in expired for ${session.userEmail}'
            : 'Signed in as ${session.userEmail}',
        key: SignInScreen.sessionStatusKey,
        textAlign: TextAlign.center,
        style: context.textStyles.body,
      ),
      if (sessionExpired) ...[
        const SizedBox(height: AppDimens.base),
        Text(
          _sessionExpiredExplanation,
          key: SignInScreen.sessionExpiredNoticeKey,
          textAlign: TextAlign.center,
          style: context.textStyles.body,
        ),
        const SizedBox(height: AppDimens.base),
        FilledButton.icon(
          key: SignInScreen.signInAgainButtonKey,
          onPressed: isLoading ? null : _startSigningInAgain,
          icon: const Icon(Icons.login),
          label: const Text('Sign in again'),
        ),
      ],
      if (session.token == _signedInAgainToken && !sessionExpired) ...[
        const SizedBox(height: AppDimens.base),
        Text(
          'Signed in again. Changes on this phone will sync.',
          key: SignInScreen.noticeTextKey,
          textAlign: TextAlign.center,
          style: context.textStyles.body,
        ),
      ],
      const SizedBox(height: AppDimens.base),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.verified_user_outlined),
        title: const Text('Provider'),
        subtitle: Text(_providerLabel(session.provider)),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.dns_outlined),
        title: const Text('Server'),
        subtitle: Text(serverUrl.toString()),
      ),
      const SizedBox(height: AppDimens.base),
      OutlinedButton.icon(
        key: SignInScreen.signOutButtonKey,
        onPressed: isLoading
            ? null
            : () {
                unawaited(
                  ref.read(authControllerProvider.notifier).signOut(),
                );
              },
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ];
  }

  List<Widget> _signInAgainHeader({
    required BuildContext context,
    required bool isLoading,
  }) {
    return [
      Text(
        _sessionExpiredExplanation,
        key: SignInScreen.sessionExpiredNoticeKey,
        style: context.textStyles.body,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: SignInScreen.cancelSignInAgainButtonKey,
          onPressed: isLoading
              ? null
              : () => setState(() {
                    _signingInAgain = false;
                    _noticeText = null;
                    _passwordController.clear();
                    _dismissedError = ref.read(authControllerProvider).error;
                  }),
          child: const Text('Cancel'),
        ),
      ),
      const SizedBox(height: AppDimens.dense),
    ];
  }

  void _startSigningInAgain() {
    setState(() {
      _signingInAgain = true;
      _emailPrefilled = false;
      _formMode = _AuthFormMode.signIn;
      _noticeText = null;
      _verificationEmailAddress = null;
      _serverUrlEdited = false;
      _dismissedError = ref.read(authControllerProvider).error;
    });
  }

  void _submitEmail() {
    switch (_formMode) {
      case _AuthFormMode.signIn:
        _signInWithEmail();
      case _AuthFormMode.signUp:
        _signUpWithEmail();
    }
  }

  void _signInWithEmail() {
    setState(() {
      _noticeText = null;
      _verificationEmailAddress = null;
    });
    unawaited(
      ref.read(authControllerProvider.notifier).signInWithEmail(
            rawServerUrl: _serverUrlController.text,
            email: _emailController.text,
            password: _passwordController.text,
          ),
    );
  }

  void _signUpWithEmail() {
    setState(() {
      _noticeText = null;
      _verificationEmailAddress = null;
    });
    unawaited(_signUpWithEmailAsync());
  }

  Future<void> _signUpWithEmailAsync() async {
    final outcome =
        await ref.read(authControllerProvider.notifier).signUpWithEmail(
              rawServerUrl: _serverUrlController.text,
              name: _nameController.text,
              email: _emailController.text,
              password: _passwordController.text,
            );
    if (!mounted || outcome == null) {
      return;
    }
    setState(() {
      _verificationEmailAddress =
          outcome.requiresEmailVerification ? outcome.userEmail : null;
      _noticeText = outcome.requiresEmailVerification
          ? 'Check your email to verify ${outcome.userEmail}, then sign in.'
          : 'Signed up as ${outcome.userEmail}.';
    });
  }

  void _signInWithSocial(AuthSocialProvider provider) {
    setState(() {
      _noticeText = null;
      _verificationEmailAddress = null;
    });
    unawaited(
      ref.read(authControllerProvider.notifier).signInWithSocial(
            rawServerUrl: _serverUrlController.text,
            provider: provider,
          ),
    );
  }

  void _resendVerificationEmail(String email) {
    setState(() {
      _noticeText = null;
    });
    unawaited(_resendVerificationEmailAsync(email));
  }

  Future<void> _resendVerificationEmailAsync(String email) async {
    final wasSent =
        await ref.read(authControllerProvider.notifier).resendVerificationEmail(
              rawServerUrl: _serverUrlController.text,
              email: email,
            );
    if (!mounted || !wasSent) {
      return;
    }
    setState(() {
      _verificationEmailAddress = email;
      _noticeText = 'Verification email sent to $email.';
    });
  }

  String? _resendVerificationEmailAddress(Object? error) {
    if (_verificationEmailAddress != null) {
      return _verificationEmailAddress;
    }
    if (error is AuthException &&
        error.code == AuthFailureCode.emailNotVerified) {
      final email = _emailController.text.trim();
      return email.isEmpty ? null : email;
    }
    return null;
  }

  String _errorMessage(Object error) {
    if (error is AuthException) {
      return error.message;
    }
    if (error is FormatException) {
      return error.message;
    }
    return 'Sign-in failed';
  }
}

const _sessionExpiredExplanation =
    'The server no longer accepts this sign-in, so sync has stopped. '
    'Everything on this phone stays here, including changes that have not '
    'synced yet. Sign in again to send them.';

String _providerLabel(AuthSessionProvider provider) {
  return switch (provider) {
    AuthSessionProvider.email => 'Email',
    AuthSessionProvider.google => 'Google',
    AuthSessionProvider.apple => 'Apple',
  };
}

enum _AuthFormMode {
  signIn,
  signUp,
}
