import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perennia/features/auth/repositories/auth_repository.dart';
import 'package:perennia/features/auth/widgets/sign_in_screen.dart';
import 'package:perennia/features/sync/controllers/sync_status_controller.dart';
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
  group('expired sign-in', () {
    testWidgets('says the sign-in expired instead of signed in', (
      tester,
    ) async {
      final repository = InMemoryAuthRepository(_expiredAccount());
      await tester.pumpWidget(
        _AuthTestApp(
          repository: repository,
          syncStatus: _authExpiredStatus(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account'), findsOneWidget);
      expect(
        find.text('Sign-in expired for lifter@example.com'),
        findsOneWidget,
      );
      expect(find.textContaining('Signed in as'), findsNothing);
      expect(find.byKey(SignInScreen.sessionExpiredNoticeKey), findsOneWidget);
      expect(find.byKey(SignInScreen.signInAgainButtonKey), findsOneWidget);
      // Signing out stays available, and nothing interrupts with a dialog.
      expect(find.byKey(SignInScreen.signOutButtonKey), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a session sync accepts still reads as signed in', (
      tester,
    ) async {
      final repository = InMemoryAuthRepository(_expiredAccount());
      await tester.pumpWidget(
        _AuthTestApp(
          repository: repository,
          syncStatus: SyncStatusState(
            kind: SyncStatusKind.failed,
            observedAt: DateTime.utc(2026, 11, 8, 9),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Signed in as lifter@example.com'), findsOneWidget);
      expect(find.byKey(SignInScreen.signInAgainButtonKey), findsNothing);
    });

    testWidgets('Sign in again replaces the session without signing out', (
      tester,
    ) async {
      final repository = InMemoryAuthRepository(_expiredAccount());
      await tester.pumpWidget(
        _AuthTestApp(
          repository: repository,
          syncStatus: _authExpiredStatus(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SignInScreen.signInAgainButtonKey));
      await tester.pumpAndSettle();

      expect(find.byKey(SignInScreen.sessionExpiredNoticeKey), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(SignInScreen.emailFieldKey))
            .controller
            ?.text,
        'lifter@example.com',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(SignInScreen.serverUrlFieldKey))
            .controller
            ?.text,
        'https://self.example/',
      );

      await tester.enterText(
        find.byKey(SignInScreen.passwordFieldKey),
        'secret',
      );
      await tester.ensureVisible(find.byKey(SignInScreen.emailSignInButtonKey));
      await tester.tap(find.byKey(SignInScreen.emailSignInButtonKey));
      await tester.pumpAndSettle();

      expect(repository.signOutAttempts, isEmpty);
      expect(repository.emailAttempts.single.email, 'lifter@example.com');
      expect(
        repository.emailAttempts.single.serverUrl.toString(),
        'https://self.example/',
      );
      expect(
        (await repository.load()).session?.token,
        'memory-email-token',
      );
      // Sync status still holds the old session's verdict until the Sync Run
      // the new session starts records over it; the screen does not repeat it.
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Signed in as lifter@example.com'), findsOneWidget);
      expect(
        find.text('Signed in again. Changes on this phone are syncing.'),
        findsOneWidget,
      );
      expect(find.byKey(SignInScreen.signInAgainButtonKey), findsNothing);
    });

    testWidgets('cancelling Sign in again keeps the expired session', (
      tester,
    ) async {
      final repository = InMemoryAuthRepository(_expiredAccount());
      await tester.pumpWidget(
        _AuthTestApp(
          repository: repository,
          syncStatus: _authExpiredStatus(),
          signInAgain: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(SignInScreen.emailSignInButtonKey), findsOneWidget);

      await tester.tap(find.byKey(SignInScreen.cancelSignInAgainButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text('Sign-in expired for lifter@example.com'),
        findsOneWidget,
      );
      expect(repository.signOutAttempts, isEmpty);
      expect((await repository.load()).session?.token, 'expired-token');
    });
  });
}

AuthState _expiredAccount() {
  final serverUrl = Uri.parse('https://self.example/');
  return AuthState(
    serverUrl: serverUrl,
    session: AuthSession(
      provider: AuthSessionProvider.email,
      serverUrl: serverUrl,
      token: 'expired-token',
      userEmail: 'lifter@example.com',
      userId: 'user-1',
      userName: 'QA Lifter',
    ),
  );
}

SyncStatusState _authExpiredStatus() {
  return SyncStatusState(
    kind: SyncStatusKind.authExpired,
    lastSuccessfulSyncAt: DateTime.utc(2026, 11, 6, 8),
    lastFailureAt: DateTime.utc(2026, 11, 8, 8),
    observedAt: DateTime.utc(2026, 11, 8, 9),
  );
}

class _AuthTestApp extends StatelessWidget {
  const _AuthTestApp({
    required this.repository,
    this.syncStatus,
    this.signInAgain = false,
  });

  final AuthRepository repository;
  final SyncStatusState? syncStatus;
  final bool signInAgain;

  @override
  Widget build(BuildContext context) {
    final status =
        syncStatus ?? SyncStatusState.initial(DateTime.utc(2026, 11, 8));
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => repository),
        syncStatusControllerProvider.overrideWith(
          () => _StubSyncStatusController(status),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: SignInScreen(signInAgain: signInAgain),
      ),
    );
  }
}

class _StubSyncStatusController extends SyncStatusController {
  _StubSyncStatusController(this.status);

  final SyncStatusState status;

  @override
  Stream<SyncStatusState> build() => Stream<SyncStatusState>.value(status);
}
