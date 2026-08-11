import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme.dart';
import '../repositories/auth_repository.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

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
    final resendEmailAddress = _resendVerificationEmailAddress(
      authValue.error,
    );

    if (!_serverUrlEdited &&
        _serverUrlController.text != authState.serverUrl.toString()) {
      _serverUrlController.text = authState.serverUrl.toString();
    }

    return Scaffold(
      appBar: AppBar(title: Text(session == null ? 'Sign in' : 'Account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimens.base),
          children: session == null
              ? _signedOutContent(
                  context: context,
                  authValue: authValue,
                  isLoading: isLoading,
                  resendEmailAddress: resendEmailAddress,
                )
              : _signedInContent(
                  context: context,
                  session: session,
                  serverUrl: authState.serverUrl,
                  isLoading: isLoading,
                ),
        ),
      ),
    );
  }

  List<Widget> _signedOutContent({
    required BuildContext context,
    required AsyncValue<AuthState> authValue,
    required bool isLoading,
    required String? resendEmailAddress,
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
          unawaited(
            ref.read(authControllerProvider.notifier).saveServerUrl(
                  value,
                ),
          );
        },
      ),
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
      if (authValue.hasError) ...[
        const SizedBox(height: AppDimens.base),
        Text(
          _errorMessage(authValue.error!),
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
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      Icon(
        Icons.account_circle_outlined,
        size: AppDimens.touchTarget,
        color: colorScheme.primary,
      ),
      const SizedBox(height: AppDimens.base),
      Text(
        session.userName,
        textAlign: TextAlign.center,
        style: context.textStyles.h2,
      ),
      const SizedBox(height: AppDimens.dense),
      Text(
        'Signed in as ${session.userEmail}',
        key: SignInScreen.sessionStatusKey,
        textAlign: TextAlign.center,
        style: context.textStyles.body,
      ),
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
