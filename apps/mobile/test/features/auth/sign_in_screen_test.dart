import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/auth/widgets/sign_in_screen.dart';
import 'package:perennia/theme/theme.dart';

void main() {
  testWidgets('email sign-in uses the custom server URL', (tester) async {
    final repository = InMemoryAuthRepository();
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await tester.enterText(
      find.byKey(SignInScreen.serverUrlFieldKey),
      'https://self.example',
    );
    await tester.enterText(
      find.byKey(SignInScreen.emailFieldKey),
      'lifter@example.com',
    );
    await tester.enterText(find.byKey(SignInScreen.passwordFieldKey), 'secret');
    await tester.tap(find.byKey(SignInScreen.emailSignInButtonKey));
    await tester.pumpAndSettle();

    expect(repository.emailAttempts.single.serverUrl.toString(),
        'https://self.example/');
    expect(repository.emailAttempts.single.email, 'lifter@example.com');
    expect(find.text('Signed in as lifter@example.com'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.byKey(SignInScreen.authModeKey), findsNothing);
    expect(find.byKey(SignInScreen.serverUrlFieldKey), findsNothing);
    expect(find.byKey(SignInScreen.emailFieldKey), findsNothing);
    expect(find.byKey(SignInScreen.passwordFieldKey), findsNothing);
    expect(find.byKey(SignInScreen.googleSignInButtonKey), findsNothing);
    expect(find.byKey(SignInScreen.appleSignInButtonKey), findsNothing);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('https://self.example/'), findsOneWidget);

    await tester.tap(find.byKey(SignInScreen.signOutButtonKey));
    await tester.pumpAndSettle();

    expect(
        repository.signOutAttempts.single.toString(), 'https://self.example/');
    expect(find.text('Sign in'), findsWidgets);
    expect(find.byKey(SignInScreen.emailSignInButtonKey), findsOneWidget);
  });

  testWidgets('email sign-up uses the custom server URL', (tester) async {
    final repository = InMemoryAuthRepository();
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(SignInScreen.serverUrlFieldKey),
      'https://self.example',
    );
    await tester.enterText(
      find.byKey(SignInScreen.nameFieldKey),
      'QA Lifter',
    );
    await tester.enterText(
      find.byKey(SignInScreen.emailFieldKey),
      'qa@example.test',
    );
    await tester.enterText(
      find.byKey(SignInScreen.passwordFieldKey),
      'correct horse battery staple',
    );
    await tester.ensureVisible(find.byKey(SignInScreen.emailSignUpButtonKey));
    await tester.tap(find.byKey(SignInScreen.emailSignUpButtonKey));
    await tester.pumpAndSettle();

    expect(repository.signUpAttempts.single.serverUrl.toString(),
        'https://self.example/');
    expect(repository.signUpAttempts.single.name, 'QA Lifter');
    expect(repository.signUpAttempts.single.email, 'qa@example.test');
    await tester.scrollUntilVisible(
      find.byKey(SignInScreen.noticeTextKey),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Check your email to verify qa@example.test, then sign in.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byKey(SignInScreen.resendVerificationEmailButtonKey),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(SignInScreen.resendVerificationEmailButtonKey),
    );
    await tester.pumpAndSettle();

    expect(repository.verificationEmailAttempts.single.serverUrl.toString(),
        'https://self.example/');
    expect(
        repository.verificationEmailAttempts.single.email, 'qa@example.test');
    expect(
      find.text('Verification email sent to qa@example.test.'),
      findsOneWidget,
    );
  });

  testWidgets('sign-up validates fields before sending a request', (
    tester,
  ) async {
    final repository = InMemoryAuthRepository();
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(SignInScreen.emailFieldKey),
      'not-an-email',
    );
    await tester.enterText(find.byKey(SignInScreen.passwordFieldKey), 'short');
    await tester.ensureVisible(find.byKey(SignInScreen.emailSignUpButtonKey));
    await tester.tap(find.byKey(SignInScreen.emailSignUpButtonKey));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(SignInScreen.errorTextKey),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(repository.signUpAttempts, isEmpty);
  });

  testWidgets('Google and Apple buttons route auth without workout sync', (
    tester,
  ) async {
    final repository = InMemoryAuthRepository();
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await tester.enterText(
      find.byKey(SignInScreen.serverUrlFieldKey),
      'https://staging.example',
    );
    await tester.tap(find.byKey(SignInScreen.googleSignInButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as google@example.com'), findsOneWidget);
    expect(find.byKey(SignInScreen.appleSignInButtonKey), findsNothing);

    await tester.tap(find.byKey(SignInScreen.signOutButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SignInScreen.appleSignInButtonKey));
    await tester.pumpAndSettle();

    expect(
      repository.socialAttempts.map((attempt) => attempt.provider),
      <AuthSocialProvider>[AuthSocialProvider.google, AuthSocialProvider.apple],
    );
    expect(
      repository.socialAttempts.map((attempt) => attempt.serverUrl.toString()),
      <String>['https://staging.example/', 'https://staging.example/'],
    );
  });

  testWidgets('social buttons stay available in sign-up mode', (tester) async {
    final repository = InMemoryAuthRepository();
    await tester.pumpWidget(_AuthTestApp(repository: repository));
    await tester.pump();

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });
}

class _AuthTestApp extends StatelessWidget {
  const _AuthTestApp({required this.repository});

  final AuthRepository repository;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SignInScreen(),
      ),
    );
  }
}
