import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Perennia'**
  String get appTitle;

  /// No description provided for @homeTodayDestination.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get homeTodayDestination;

  /// No description provided for @homeProgressDestination.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get homeProgressDestination;

  /// No description provided for @homeLibraryDestination.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get homeLibraryDestination;

  /// No description provided for @homeProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get homeProgressTitle;

  /// No description provided for @homeBodyTitle.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get homeBodyTitle;

  /// No description provided for @homeHealthMetricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Health metrics'**
  String get homeHealthMetricsTitle;

  /// No description provided for @homeLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get homeLibraryTitle;

  /// No description provided for @homeLibraryTrainingSection.
  ///
  /// In en, this message translates to:
  /// **'TRAINING'**
  String get homeLibraryTrainingSection;

  /// No description provided for @homeLibrarySupplementsSection.
  ///
  /// In en, this message translates to:
  /// **'SUPPLEMENTS'**
  String get homeLibrarySupplementsSection;

  /// No description provided for @homeCreateExercise.
  ///
  /// In en, this message translates to:
  /// **'Create exercise'**
  String get homeCreateExercise;

  /// No description provided for @homeCreateExerciseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add an exercise to your User Library'**
  String get homeCreateExerciseSubtitle;

  /// No description provided for @exerciseCatalogCreateExercise.
  ///
  /// In en, this message translates to:
  /// **'Create exercise'**
  String get exerciseCatalogCreateExercise;

  /// No description provided for @exerciseCatalogCreateNamedExercise.
  ///
  /// In en, this message translates to:
  /// **'Create \"{name}\"'**
  String exerciseCatalogCreateNamedExercise(String name);

  /// No description provided for @exerciseCatalogEmptyLibrary.
  ///
  /// In en, this message translates to:
  /// **'No exercises in your library yet'**
  String get exerciseCatalogEmptyLibrary;

  /// No description provided for @exerciseCatalogNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No exercises match your search and filters'**
  String get exerciseCatalogNoMatches;

  /// No description provided for @homeAccountAndAppTitle.
  ///
  /// In en, this message translates to:
  /// **'Account & app'**
  String get homeAccountAndAppTitle;

  /// No description provided for @homeAccountStatusLoading.
  ///
  /// In en, this message translates to:
  /// **'Checking account status'**
  String get homeAccountStatusLoading;

  /// No description provided for @homeAccountStatusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Account status unavailable'**
  String get homeAccountStatusUnavailable;

  /// No description provided for @homeLocalOnlyStatus.
  ///
  /// In en, this message translates to:
  /// **'Local only'**
  String get homeLocalOnlyStatus;

  /// No description provided for @homeSignInToSync.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync'**
  String get homeSignInToSync;

  /// No description provided for @homeManageAccountAndSync.
  ///
  /// In en, this message translates to:
  /// **'Manage account and sync'**
  String get homeManageAccountAndSync;

  /// No description provided for @homeManageRoutines.
  ///
  /// In en, this message translates to:
  /// **'Manage routines'**
  String get homeManageRoutines;

  /// No description provided for @homeLogAction.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get homeLogAction;

  /// No description provided for @homeLogSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Log for this day'**
  String get homeLogSheetTitle;

  /// No description provided for @homeLogWorkout.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get homeLogWorkout;

  /// No description provided for @homeStartWorkoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start workout. Try again.'**
  String get homeStartWorkoutFailed;

  /// No description provided for @homeLogFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get homeLogFood;

  /// No description provided for @homeLogSupplement.
  ///
  /// In en, this message translates to:
  /// **'Supplement'**
  String get homeLogSupplement;

  /// No description provided for @homeDomainToggleLabel.
  ///
  /// In en, this message translates to:
  /// **'Home domain'**
  String get homeDomainToggleLabel;

  /// No description provided for @homeTrainingDomain.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get homeTrainingDomain;

  /// No description provided for @homeNutritionDomain.
  ///
  /// In en, this message translates to:
  /// **'Nutrition'**
  String get homeNutritionDomain;

  /// No description provided for @homeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Home unavailable'**
  String get homeUnavailable;

  /// No description provided for @homeNutritionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Nutrition Day unavailable'**
  String get homeNutritionUnavailable;

  /// No description provided for @homeStartNewWorkout.
  ///
  /// In en, this message translates to:
  /// **'Start New Workout'**
  String get homeStartNewWorkout;

  /// No description provided for @homeLoadRoutine.
  ///
  /// In en, this message translates to:
  /// **'Load Routine'**
  String get homeLoadRoutine;

  /// No description provided for @homeAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add exercise'**
  String get homeAddExercise;

  /// No description provided for @homeSessionHeader.
  ///
  /// In en, this message translates to:
  /// **'Session {time}'**
  String homeSessionHeader(String time);

  /// No description provided for @homeSaveCommentTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save comment'**
  String get homeSaveCommentTooltip;

  /// No description provided for @homeCopyWorkoutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy workout'**
  String get homeCopyWorkoutTooltip;

  /// No description provided for @homeMoveWorkoutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move workout'**
  String get homeMoveWorkoutTooltip;

  /// No description provided for @homeShareWorkoutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share workout'**
  String get homeShareWorkoutTooltip;

  /// No description provided for @homeWorkoutCommentLabel.
  ///
  /// In en, this message translates to:
  /// **'Workout comment'**
  String get homeWorkoutCommentLabel;

  /// No description provided for @homeWorkoutSummaryCopied.
  ///
  /// In en, this message translates to:
  /// **'Workout summary copied'**
  String get homeWorkoutSummaryCopied;

  /// No description provided for @homePreviousDayTooltip.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get homePreviousDayTooltip;

  /// No description provided for @homeNextDayTooltip.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get homeNextDayTooltip;

  /// No description provided for @homeNoExercisesLoggedYet.
  ///
  /// In en, this message translates to:
  /// **'No exercises logged yet'**
  String get homeNoExercisesLoggedYet;

  /// No description provided for @homeNoSetsYet.
  ///
  /// In en, this message translates to:
  /// **'No sets yet'**
  String get homeNoSetsYet;

  /// No description provided for @homeUpNextTitle.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get homeUpNextTitle;

  /// No description provided for @homeUpNextRoutineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{routineName} · {slotLabel}'**
  String homeUpNextRoutineSubtitle(String routineName, String slotLabel);

  /// No description provided for @homeUpNextStartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start {templateName}'**
  String homeUpNextStartTooltip(String templateName);

  /// No description provided for @homeUpNextDoneLabel.
  ///
  /// In en, this message translates to:
  /// **'{templateName}, done'**
  String homeUpNextDoneLabel(String templateName);

  /// No description provided for @homeUpNextStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start this session. Try again.'**
  String get homeUpNextStartFailed;

  /// No description provided for @templatePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Load a Template'**
  String get templatePickerTitle;

  /// No description provided for @templatePickerTodayUpNextHeading.
  ///
  /// In en, this message translates to:
  /// **'Today / Up next'**
  String get templatePickerTodayUpNextHeading;

  /// No description provided for @templatePickerRoutinesHeading.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get templatePickerRoutinesHeading;

  /// No description provided for @templatePickerAllTemplatesHeading.
  ///
  /// In en, this message translates to:
  /// **'All Templates'**
  String get templatePickerAllTemplatesHeading;

  /// No description provided for @templatePickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search templates'**
  String get templatePickerSearchHint;

  /// No description provided for @templatePickerEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No plans yet'**
  String get templatePickerEmptyTitle;

  /// No description provided for @templatePickerEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Finish a workout, then save it as a template.'**
  String get templatePickerEmptyMessage;

  /// No description provided for @templatePickerNoSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No templates match your search.'**
  String get templatePickerNoSearchResults;

  /// No description provided for @templatePickerCustomizeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Customize {templateName}'**
  String templatePickerCustomizeTooltip(String templateName);

  /// No description provided for @templatePickerPreviewStart.
  ///
  /// In en, this message translates to:
  /// **'Start workout'**
  String get templatePickerPreviewStart;

  /// No description provided for @templatePickerPreviewExercisesHeading.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get templatePickerPreviewExercisesHeading;

  /// No description provided for @templatePickerPreviewEmptyExercises.
  ///
  /// In en, this message translates to:
  /// **'No exercises in this template yet.'**
  String get templatePickerPreviewEmptyExercises;

  /// No description provided for @workoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get workoutTitle;

  /// No description provided for @workoutUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Workout unavailable'**
  String get workoutUnavailable;

  /// No description provided for @workoutSummaryListTitle.
  ///
  /// In en, this message translates to:
  /// **'Workouts'**
  String get workoutSummaryListTitle;

  /// No description provided for @workoutExercisesTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get workoutExercisesTitle;

  /// No description provided for @workoutNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get workoutNotesTitle;

  /// No description provided for @workoutNotesButton.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get workoutNotesButton;

  /// No description provided for @workoutOptionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Workout options'**
  String get workoutOptionsTooltip;

  /// No description provided for @workoutOpenStatus.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get workoutOpenStatus;

  /// No description provided for @workoutFinishedStatus.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get workoutFinishedStatus;

  /// No description provided for @workoutStartedAt.
  ///
  /// In en, this message translates to:
  /// **'Started {time}'**
  String workoutStartedAt(String time);

  /// No description provided for @workoutTimeRange.
  ///
  /// In en, this message translates to:
  /// **'{start}-{end}'**
  String workoutTimeRange(String start, String end);

  /// No description provided for @workoutFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish Workout'**
  String get workoutFinish;

  /// No description provided for @workoutResume.
  ///
  /// In en, this message translates to:
  /// **'Resume Workout'**
  String get workoutResume;

  /// No description provided for @workoutFinished.
  ///
  /// In en, this message translates to:
  /// **'Workout finished'**
  String get workoutFinished;

  /// No description provided for @workoutResumed.
  ///
  /// In en, this message translates to:
  /// **'Workout resumed'**
  String get workoutResumed;

  /// No description provided for @workoutShareAction.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get workoutShareAction;

  /// No description provided for @workoutEditStartTime.
  ///
  /// In en, this message translates to:
  /// **'Edit start time'**
  String get workoutEditStartTime;

  /// No description provided for @workoutEditFinishTime.
  ///
  /// In en, this message translates to:
  /// **'Edit finish time'**
  String get workoutEditFinishTime;

  /// No description provided for @workoutStartTimeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Start time updated'**
  String get workoutStartTimeUpdated;

  /// No description provided for @workoutFinishTimeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Finish time updated'**
  String get workoutFinishTimeUpdated;

  /// No description provided for @workoutStartTimeAfterFinish.
  ///
  /// In en, this message translates to:
  /// **'Start time must be before finish time'**
  String get workoutStartTimeAfterFinish;

  /// No description provided for @workoutFinishTimeBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'Finish time must be after start time'**
  String get workoutFinishTimeBeforeStart;

  /// No description provided for @workoutDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete workout'**
  String get workoutDelete;

  /// No description provided for @workoutDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete workout?'**
  String get workoutDeleteTitle;

  /// No description provided for @workoutDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes the workout and its sets from your log. History can still be recovered from the Activity Log.'**
  String get workoutDeleteMessage;

  /// No description provided for @workoutCopied.
  ///
  /// In en, this message translates to:
  /// **'Workout copied'**
  String get workoutCopied;

  /// No description provided for @workoutMoved.
  ///
  /// In en, this message translates to:
  /// **'Workout moved'**
  String get workoutMoved;

  /// No description provided for @workoutRemoveExerciseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove exercise'**
  String get workoutRemoveExerciseTooltip;

  /// No description provided for @workoutReorderExerciseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reorder exercise'**
  String get workoutReorderExerciseTooltip;

  /// No description provided for @workoutLinkSupersetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Link {firstName} and {secondName} as a superset'**
  String workoutLinkSupersetTooltip(String firstName, String secondName);

  /// No description provided for @workoutUnlinkSupersetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unlink {firstName} and {secondName} from {groupName}'**
  String workoutUnlinkSupersetTooltip(
      String firstName, String secondName, String groupName);

  /// No description provided for @workoutSupersetUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update superset. Try again.'**
  String get workoutSupersetUpdateFailed;

  /// No description provided for @workoutExerciseRemoved.
  ///
  /// In en, this message translates to:
  /// **'Exercise removed'**
  String get workoutExerciseRemoved;

  /// No description provided for @workoutSaveNote.
  ///
  /// In en, this message translates to:
  /// **'Save note'**
  String get workoutSaveNote;

  /// No description provided for @workoutDeleteNote.
  ///
  /// In en, this message translates to:
  /// **'Delete note'**
  String get workoutDeleteNote;

  /// No description provided for @workoutNoteSaved.
  ///
  /// In en, this message translates to:
  /// **'Workout note saved'**
  String get workoutNoteSaved;

  /// No description provided for @workoutNoteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Workout note deleted'**
  String get workoutNoteDeleted;

  /// No description provided for @workoutNoExercises.
  ///
  /// In en, this message translates to:
  /// **'No exercises'**
  String get workoutNoExercises;

  /// No description provided for @workoutOneExercise.
  ///
  /// In en, this message translates to:
  /// **'1 exercise'**
  String get workoutOneExercise;

  /// No description provided for @workoutExerciseCount.
  ///
  /// In en, this message translates to:
  /// **'{count} exercises'**
  String workoutExerciseCount(int count);

  /// No description provided for @workoutNoSets.
  ///
  /// In en, this message translates to:
  /// **'No sets'**
  String get workoutNoSets;

  /// No description provided for @workoutOneSet.
  ///
  /// In en, this message translates to:
  /// **'1 set'**
  String get workoutOneSet;

  /// No description provided for @workoutSetCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sets'**
  String workoutSetCount(int count);

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @workoutDurationInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get workoutDurationInProgress;

  /// No description provided for @workoutDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String workoutDurationHours(int hours);

  /// No description provided for @workoutDurationHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String workoutDurationHoursMinutes(int hours, int minutes);

  /// No description provided for @workoutDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String workoutDurationMinutes(int minutes);

  /// No description provided for @workoutDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String workoutDurationSeconds(int seconds);

  /// No description provided for @navSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get navSignIn;

  /// No description provided for @navRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get navRecentActivity;

  /// No description provided for @navRoutines.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get navRoutines;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navBodyTracker.
  ///
  /// In en, this message translates to:
  /// **'Body Tracker'**
  String get navBodyTracker;

  /// No description provided for @navMetrics.
  ///
  /// In en, this message translates to:
  /// **'Metrics'**
  String get navMetrics;

  /// No description provided for @navSupplements.
  ///
  /// In en, this message translates to:
  /// **'Supplements'**
  String get navSupplements;

  /// No description provided for @agentKeysSignedOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to manage agent keys'**
  String get agentKeysSignedOutTitle;

  /// No description provided for @agentKeysSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get agentKeysSignIn;

  /// No description provided for @agentKeysNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent key name'**
  String get agentKeysNameLabel;

  /// No description provided for @agentKeysCreate.
  ///
  /// In en, this message translates to:
  /// **'Create key'**
  String get agentKeysCreate;

  /// No description provided for @agentKeysSecretShownOnceSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Agent API key secret shown once'**
  String get agentKeysSecretShownOnceSemanticLabel;

  /// No description provided for @agentKeysSecretShownOnceTitle.
  ///
  /// In en, this message translates to:
  /// **'Secret shown once'**
  String get agentKeysSecretShownOnceTitle;

  /// No description provided for @agentKeysCopySecretTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy secret'**
  String get agentKeysCopySecretTooltip;

  /// No description provided for @agentKeysCopiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Agent key copied'**
  String get agentKeysCopiedMessage;

  /// No description provided for @agentKeysSecretWarning.
  ///
  /// In en, this message translates to:
  /// **'Copy it now. It will not be shown again.'**
  String get agentKeysSecretWarning;

  /// No description provided for @agentKeysDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get agentKeysDone;

  /// No description provided for @agentKeysEmpty.
  ///
  /// In en, this message translates to:
  /// **'No agent keys'**
  String get agentKeysEmpty;

  /// No description provided for @agentKeysRevokeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Revoke key'**
  String get agentKeysRevokeTooltip;

  /// No description provided for @agentKeysNeverUsed.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get agentKeysNeverUsed;

  /// No description provided for @agentKeysStarts.
  ///
  /// In en, this message translates to:
  /// **'Starts {start}'**
  String agentKeysStarts(String start);

  /// No description provided for @agentKeysCreated.
  ///
  /// In en, this message translates to:
  /// **'Created {created}'**
  String agentKeysCreated(String created);

  /// No description provided for @agentKeysLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used {lastUsed}'**
  String agentKeysLastUsed(String lastUsed);

  /// No description provided for @bodyTrackerTitle.
  ///
  /// In en, this message translates to:
  /// **'Body Tracker'**
  String get bodyTrackerTitle;

  /// No description provided for @bodyTrackerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Body Tracker unavailable'**
  String get bodyTrackerUnavailable;

  /// No description provided for @metricsTitle.
  ///
  /// In en, this message translates to:
  /// **'Metrics'**
  String get metricsTitle;

  /// No description provided for @metricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Metrics unavailable'**
  String get metricsUnavailable;

  /// No description provided for @metricsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No monitoring readings yet'**
  String get metricsEmpty;

  /// No description provided for @metricsLatestReading.
  ///
  /// In en, this message translates to:
  /// **'Last reading {time}'**
  String metricsLatestReading(String time);

  /// No description provided for @metricsIntegrationProvenance.
  ///
  /// In en, this message translates to:
  /// **'Integration'**
  String get metricsIntegrationProvenance;

  /// No description provided for @metricsManualProvenance.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get metricsManualProvenance;

  /// No description provided for @metricsAgentProvenance.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get metricsAgentProvenance;

  /// No description provided for @metricsSource.
  ///
  /// In en, this message translates to:
  /// **'Source {source}'**
  String metricsSource(String source);

  /// No description provided for @metricsAddMetric.
  ///
  /// In en, this message translates to:
  /// **'Add Metric'**
  String get metricsAddMetric;

  /// No description provided for @metricsAddMetricTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add a Metric'**
  String get metricsAddMetricTooltip;

  /// No description provided for @metricsCreateMetricTitle.
  ///
  /// In en, this message translates to:
  /// **'New Metric'**
  String get metricsCreateMetricTitle;

  /// No description provided for @metricsNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get metricsNameLabel;

  /// No description provided for @metricsNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get metricsNameRequired;

  /// No description provided for @metricsUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get metricsUnitLabel;

  /// No description provided for @metricsUnitRequired.
  ///
  /// In en, this message translates to:
  /// **'Unit is required'**
  String get metricsUnitRequired;

  /// No description provided for @metricsUnitHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. ng/dL, kg, bpm'**
  String get metricsUnitHint;

  /// No description provided for @metricsCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get metricsCreate;

  /// No description provided for @metricsMetricCreated.
  ///
  /// In en, this message translates to:
  /// **'Metric created'**
  String get metricsMetricCreated;

  /// No description provided for @metricsLogReadingTooltip.
  ///
  /// In en, this message translates to:
  /// **'Log a reading'**
  String get metricsLogReadingTooltip;

  /// No description provided for @metricsLogReadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Reading'**
  String get metricsLogReadingTitle;

  /// No description provided for @metricsValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get metricsValueLabel;

  /// No description provided for @metricsMeasuredAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Measured at'**
  String get metricsMeasuredAtLabel;

  /// No description provided for @metricsCommentLabel.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get metricsCommentLabel;

  /// No description provided for @metricsSaveReading.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get metricsSaveReading;

  /// No description provided for @metricsReadingSaved.
  ///
  /// In en, this message translates to:
  /// **'Reading saved'**
  String get metricsReadingSaved;

  /// No description provided for @metricsInvalidValue.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get metricsInvalidValue;

  /// No description provided for @metricsInvalidDateTime.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date and time (yyyy-MM-dd HH:mm)'**
  String get metricsInvalidDateTime;

  /// No description provided for @bodyTrackerNoValueYet.
  ///
  /// In en, this message translates to:
  /// **'No value yet'**
  String get bodyTrackerNoValueYet;

  /// No description provided for @bodyTrackerLatestRecency.
  ///
  /// In en, this message translates to:
  /// **'Last measured {recency}'**
  String bodyTrackerLatestRecency(String recency);

  /// No description provided for @bodyTrackerValueWithUnit.
  ///
  /// In en, this message translates to:
  /// **'{value} {unit}'**
  String bodyTrackerValueWithUnit(String value, String unit);

  /// No description provided for @bodyTrackerValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get bodyTrackerValueLabel;

  /// No description provided for @bodyTrackerMeasuredAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Date/time'**
  String get bodyTrackerMeasuredAtLabel;

  /// No description provided for @bodyTrackerCommentLabel.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get bodyTrackerCommentLabel;

  /// No description provided for @bodyTrackerSaveEntry.
  ///
  /// In en, this message translates to:
  /// **'Save entry'**
  String get bodyTrackerSaveEntry;

  /// No description provided for @bodyTrackerUpdateEntry.
  ///
  /// In en, this message translates to:
  /// **'Update entry'**
  String get bodyTrackerUpdateEntry;

  /// No description provided for @bodyTrackerEntrySaved.
  ///
  /// In en, this message translates to:
  /// **'Measurement saved'**
  String get bodyTrackerEntrySaved;

  /// No description provided for @bodyTrackerEntryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Measurement updated'**
  String get bodyTrackerEntryUpdated;

  /// No description provided for @bodyTrackerEntryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Measurement deleted'**
  String get bodyTrackerEntryDeleted;

  /// No description provided for @bodyTrackerHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get bodyTrackerHistoryTitle;

  /// No description provided for @bodyTrackerHistoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open history'**
  String get bodyTrackerHistoryTooltip;

  /// No description provided for @bodyTrackerHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No measurement history yet'**
  String get bodyTrackerHistoryEmpty;

  /// No description provided for @bodyTrackerHistoryFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Measurement'**
  String get bodyTrackerHistoryFilterLabel;

  /// No description provided for @bodyTrackerHistoryAllMeasurements.
  ///
  /// In en, this message translates to:
  /// **'All measurements'**
  String get bodyTrackerHistoryAllMeasurements;

  /// No description provided for @bodyTrackerProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get bodyTrackerProgressTitle;

  /// No description provided for @bodyTrackerProgressTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open progress graph'**
  String get bodyTrackerProgressTooltip;

  /// No description provided for @bodyTrackerProgressEmpty.
  ///
  /// In en, this message translates to:
  /// **'No measurement entries yet'**
  String get bodyTrackerProgressEmpty;

  /// No description provided for @bodyTrackerProgressGraphSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Progress graph, {measurement}, {raw} raw points'**
  String bodyTrackerProgressGraphSemanticLabel(String measurement, int raw);

  /// No description provided for @bodyTrackerProgressGraphHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to inspect a raw graph value'**
  String get bodyTrackerProgressGraphHint;

  /// No description provided for @bodyTrackerProgressTargetLine.
  ///
  /// In en, this message translates to:
  /// **'Target {value} {unit}'**
  String bodyTrackerProgressTargetLine(String value, String unit);

  /// No description provided for @bodyTrackerProgressDownsampled.
  ///
  /// In en, this message translates to:
  /// **'Rendering {rendered} of {raw} raw points'**
  String bodyTrackerProgressDownsampled(int rendered, int raw);

  /// No description provided for @bodyTrackerProgressSelected.
  ///
  /// In en, this message translates to:
  /// **'{measurement}: {value} {unit} on {date}'**
  String bodyTrackerProgressSelected(
      String measurement, String value, String unit, String date);

  /// No description provided for @bodyTrackerManageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Manage measurements'**
  String get bodyTrackerManageTooltip;

  /// No description provided for @bodyTrackerManageTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage measurements'**
  String get bodyTrackerManageTitle;

  /// No description provided for @bodyTrackerAddMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Add measurement'**
  String get bodyTrackerAddMeasurement;

  /// No description provided for @bodyTrackerCreateMeasurementTitle.
  ///
  /// In en, this message translates to:
  /// **'New measurement'**
  String get bodyTrackerCreateMeasurementTitle;

  /// No description provided for @bodyTrackerMeasurementNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get bodyTrackerMeasurementNameLabel;

  /// No description provided for @bodyTrackerMeasurementUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get bodyTrackerMeasurementUnitLabel;

  /// No description provided for @bodyTrackerMeasurementGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get bodyTrackerMeasurementGoalLabel;

  /// No description provided for @bodyTrackerMeasurementEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get bodyTrackerMeasurementEnabledLabel;

  /// No description provided for @bodyTrackerMeasurementTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target value'**
  String get bodyTrackerMeasurementTargetLabel;

  /// No description provided for @bodyTrackerMeasurementNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get bodyTrackerMeasurementNameRequired;

  /// No description provided for @bodyTrackerMeasurementTargetRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-negative target'**
  String get bodyTrackerMeasurementTargetRequired;

  /// No description provided for @bodyTrackerMeasurementCreated.
  ///
  /// In en, this message translates to:
  /// **'Measurement created'**
  String get bodyTrackerMeasurementCreated;

  /// No description provided for @bodyTrackerMeasurementDeleted.
  ///
  /// In en, this message translates to:
  /// **'Measurement archived'**
  String get bodyTrackerMeasurementDeleted;

  /// No description provided for @bodyTrackerMeasurementReset.
  ///
  /// In en, this message translates to:
  /// **'Measurements reset'**
  String get bodyTrackerMeasurementReset;

  /// No description provided for @bodyTrackerResetMeasurementsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset measurements'**
  String get bodyTrackerResetMeasurementsTooltip;

  /// No description provided for @bodyTrackerReorderMeasurementTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reorder measurement'**
  String get bodyTrackerReorderMeasurementTooltip;

  /// No description provided for @bodyTrackerDeleteMeasurementTooltip.
  ///
  /// In en, this message translates to:
  /// **'Archive measurement'**
  String get bodyTrackerDeleteMeasurementTooltip;

  /// No description provided for @bodyTrackerDeleteMeasurementTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive measurement?'**
  String get bodyTrackerDeleteMeasurementTitle;

  /// No description provided for @bodyTrackerDeleteMeasurementMessage.
  ///
  /// In en, this message translates to:
  /// **'This measurement will leave Body Tracker, but its entries stay in history.'**
  String get bodyTrackerDeleteMeasurementMessage;

  /// No description provided for @bodyTrackerResetMeasurementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset measurements?'**
  String get bodyTrackerResetMeasurementsTitle;

  /// No description provided for @bodyTrackerResetMeasurementsMessage.
  ///
  /// In en, this message translates to:
  /// **'This restores Body Weight and Body Fat, enables them, and archives custom measurements.'**
  String get bodyTrackerResetMeasurementsMessage;

  /// No description provided for @bodyTrackerCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get bodyTrackerCancel;

  /// No description provided for @bodyTrackerCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get bodyTrackerCreate;

  /// No description provided for @bodyTrackerArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get bodyTrackerArchive;

  /// No description provided for @bodyTrackerReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get bodyTrackerReset;

  /// No description provided for @bodyTrackerGoalIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get bodyTrackerGoalIncrease;

  /// No description provided for @bodyTrackerGoalDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get bodyTrackerGoalDecrease;

  /// No description provided for @bodyTrackerGoalTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get bodyTrackerGoalTarget;

  /// No description provided for @bodyTrackerDeleteEntryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete measurement entry'**
  String get bodyTrackerDeleteEntryTooltip;

  /// No description provided for @bodyTrackerDeleteEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete measurement entry?'**
  String get bodyTrackerDeleteEntryTitle;

  /// No description provided for @bodyTrackerDeleteEntryMessage.
  ///
  /// In en, this message translates to:
  /// **'This entry will be removed from History.'**
  String get bodyTrackerDeleteEntryMessage;

  /// No description provided for @bodyTrackerDeleteEntryCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get bodyTrackerDeleteEntryCancel;

  /// No description provided for @bodyTrackerDeleteEntryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get bodyTrackerDeleteEntryConfirm;

  /// No description provided for @bodyTrackerInvalidValue.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-negative value with up to 5 decimals'**
  String get bodyTrackerInvalidValue;

  /// No description provided for @bodyTrackerInvalidDateTime.
  ///
  /// In en, this message translates to:
  /// **'Use YYYY-MM-DD HH:mm'**
  String get bodyTrackerInvalidDateTime;

  /// No description provided for @bodyTrackerSuspiciousValueTitle.
  ///
  /// In en, this message translates to:
  /// **'Unusual measurement value'**
  String get bodyTrackerSuspiciousValueTitle;

  /// No description provided for @bodyTrackerSuspiciousValueMessage.
  ///
  /// In en, this message translates to:
  /// **'{value} {unit} is outside the usual range. Save it anyway?'**
  String bodyTrackerSuspiciousValueMessage(String value, String unit);

  /// No description provided for @bodyTrackerSuspiciousValueCancel.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get bodyTrackerSuspiciousValueCancel;

  /// No description provided for @bodyTrackerSuspiciousValueConfirm.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get bodyTrackerSuspiciousValueConfirm;

  /// No description provided for @bodyTrackerUnitKilogram.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get bodyTrackerUnitKilogram;

  /// No description provided for @bodyTrackerUnitPound.
  ///
  /// In en, this message translates to:
  /// **'lb'**
  String get bodyTrackerUnitPound;

  /// No description provided for @bodyTrackerUnitCentimeter.
  ///
  /// In en, this message translates to:
  /// **'cm'**
  String get bodyTrackerUnitCentimeter;

  /// No description provided for @bodyTrackerUnitInch.
  ///
  /// In en, this message translates to:
  /// **'in'**
  String get bodyTrackerUnitInch;

  /// No description provided for @bodyTrackerUnitPercent.
  ///
  /// In en, this message translates to:
  /// **'%'**
  String get bodyTrackerUnitPercent;

  /// No description provided for @activityUndoSuccess.
  ///
  /// In en, this message translates to:
  /// **'Activity undone'**
  String get activityUndoSuccess;

  /// No description provided for @activityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Recent activity unavailable'**
  String get activityUnavailable;

  /// No description provided for @activityEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recent activity'**
  String get activityEmpty;

  /// No description provided for @activityChangeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change} other{{count} changes}}'**
  String activityChangeCount(int count);

  /// No description provided for @activityFeedSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'{summary}, {actor}, {changes}, {timestamp}'**
  String activityFeedSemanticLabel(
      String summary, String actor, String changes, String timestamp);

  /// No description provided for @activityFeedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{actor} - {changes}'**
  String activityFeedSubtitle(String actor, String changes);

  /// No description provided for @activityAgentActor.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get activityAgentActor;

  /// No description provided for @activityAgentActorWithKey.
  ///
  /// In en, this message translates to:
  /// **'Agent key {keyId}'**
  String activityAgentActorWithKey(String keyId);

  /// No description provided for @activityUndoTooltip.
  ///
  /// In en, this message translates to:
  /// **'Undo activity'**
  String get activityUndoTooltip;

  /// No description provided for @activityUndoConflict.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Could not undo 1 changed row: {entityTable} {entityId}} other{Could not undo {count} changed rows: {entityTable} {entityId}}}'**
  String activityUndoConflict(int count, String entityTable, String entityId);

  /// No description provided for @activityUndoGenericConflict.
  ///
  /// In en, this message translates to:
  /// **'Activity could not be undone'**
  String get activityUndoGenericConflict;

  /// No description provided for @activityRelativeLessThanOneMinuteAgo.
  ///
  /// In en, this message translates to:
  /// **'less than 1 min ago'**
  String get activityRelativeLessThanOneMinuteAgo;

  /// No description provided for @activityRelativeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String activityRelativeMinutesAgo(int count);

  /// No description provided for @activityRelativeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String activityRelativeHoursAgo(int count);

  /// No description provided for @activityRelativeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String activityRelativeDaysAgo(int count);

  /// No description provided for @trainingBackgroundAlertsDenied.
  ///
  /// In en, this message translates to:
  /// **'Background timer alerts are off. In-app countdowns still work while Perennia is open.'**
  String get trainingBackgroundAlertsDenied;

  /// No description provided for @trainingFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get trainingFallbackTitle;

  /// No description provided for @trainingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Exercise unavailable'**
  String get trainingUnavailable;

  /// No description provided for @trainingOpenNavigationTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open navigation'**
  String get trainingOpenNavigationTooltip;

  /// No description provided for @trainingSetSaved.
  ///
  /// In en, this message translates to:
  /// **'Set saved'**
  String get trainingSetSaved;

  /// No description provided for @trainingExercisesTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get trainingExercisesTitle;

  /// No description provided for @trainingNoExercisesYet.
  ///
  /// In en, this message translates to:
  /// **'No exercises yet'**
  String get trainingNoExercisesYet;

  /// No description provided for @trainingGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get trainingGroupsTitle;

  /// No description provided for @trainingCreateGroupTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get trainingCreateGroupTooltip;

  /// No description provided for @trainingNoGroupsYet.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get trainingNoGroupsYet;

  /// No description provided for @trainingSetCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 set} other{{count} sets}}'**
  String trainingSetCount(int count);

  /// No description provided for @trainingOpenExerciseOverviewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open exercise overview'**
  String get trainingOpenExerciseOverviewTooltip;

  /// No description provided for @trainingGroupExerciseCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 exercise} other{{count} exercises}}'**
  String trainingGroupExerciseCount(int count);

  /// No description provided for @trainingEditGroupTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get trainingEditGroupTooltip;

  /// No description provided for @trainingGroupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get trainingGroupNameLabel;

  /// No description provided for @trainingGroupColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get trainingGroupColorLabel;

  /// No description provided for @trainingExerciseUngroupedIndicator.
  ///
  /// In en, this message translates to:
  /// **'Exercise is not in a group'**
  String get trainingExerciseUngroupedIndicator;

  /// No description provided for @trainingExerciseGroupIndicator.
  ///
  /// In en, this message translates to:
  /// **'Exercise group {groupName}'**
  String trainingExerciseGroupIndicator(String groupName);

  /// No description provided for @trainingGroupColorIndicator.
  ///
  /// In en, this message translates to:
  /// **'Group color for {groupName}'**
  String trainingGroupColorIndicator(String groupName);

  /// No description provided for @trainingCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get trainingCancel;

  /// No description provided for @trainingSaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Save group'**
  String get trainingSaveGroup;

  /// No description provided for @trainingRestTimer.
  ///
  /// In en, this message translates to:
  /// **'Rest timer'**
  String get trainingRestTimer;

  /// No description provided for @trainingRestCountdown.
  ///
  /// In en, this message translates to:
  /// **'Rest {remaining}'**
  String trainingRestCountdown(String remaining);

  /// No description provided for @trainingRestComplete.
  ///
  /// In en, this message translates to:
  /// **'Rest complete'**
  String get trainingRestComplete;

  /// No description provided for @trainingRestSecondsLabel.
  ///
  /// In en, this message translates to:
  /// **'Rest sec'**
  String get trainingRestSecondsLabel;

  /// No description provided for @trainingStartTimer.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get trainingStartTimer;

  /// No description provided for @trainingUpdateTimer.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get trainingUpdateTimer;

  /// No description provided for @trainingCancelTimerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cancel timer'**
  String get trainingCancelTimerTooltip;

  /// No description provided for @trainingPersonalRecordTooltip.
  ///
  /// In en, this message translates to:
  /// **'Personal record'**
  String get trainingPersonalRecordTooltip;

  /// No description provided for @trainingEditSetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit set'**
  String get trainingEditSetTooltip;

  /// No description provided for @trainingDeleteSetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete set'**
  String get trainingDeleteSetTooltip;

  /// No description provided for @trainingMarkSetCompleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Mark set complete'**
  String get trainingMarkSetCompleteLabel;

  /// No description provided for @trainingMarkSetIncompleteLabel.
  ///
  /// In en, this message translates to:
  /// **'Mark set incomplete'**
  String get trainingMarkSetIncompleteLabel;

  /// No description provided for @trainingReorderSetLabel.
  ///
  /// In en, this message translates to:
  /// **'Reorder set'**
  String get trainingReorderSetLabel;

  /// No description provided for @trainingDecreaseDimensionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Decrease {dimension}'**
  String trainingDecreaseDimensionTooltip(String dimension);

  /// No description provided for @trainingIncreaseDimensionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Increase {dimension}'**
  String trainingIncreaseDimensionTooltip(String dimension);

  /// No description provided for @trainingCommentLabel.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get trainingCommentLabel;

  /// No description provided for @trainingSideLeft.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get trainingSideLeft;

  /// No description provided for @trainingSideLeftTooltip.
  ///
  /// In en, this message translates to:
  /// **'Left side'**
  String get trainingSideLeftTooltip;

  /// No description provided for @trainingSideRight.
  ///
  /// In en, this message translates to:
  /// **'R'**
  String get trainingSideRight;

  /// No description provided for @trainingSideRightTooltip.
  ///
  /// In en, this message translates to:
  /// **'Right side'**
  String get trainingSideRightTooltip;

  /// No description provided for @trainingRpeLabel.
  ///
  /// In en, this message translates to:
  /// **'RPE'**
  String get trainingRpeLabel;

  /// No description provided for @trainingSaveSet.
  ///
  /// In en, this message translates to:
  /// **'Save set'**
  String get trainingSaveSet;

  /// No description provided for @trainingSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get trainingSaveChanges;

  /// No description provided for @trainingCompletedSet.
  ///
  /// In en, this message translates to:
  /// **'Completed set'**
  String get trainingCompletedSet;

  /// No description provided for @trainingSetComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get trainingSetComplete;

  /// No description provided for @trainingSetInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get trainingSetInProgress;

  /// No description provided for @trainingSetRpe.
  ///
  /// In en, this message translates to:
  /// **'RPE {rpe}'**
  String trainingSetRpe(String rpe);

  /// No description provided for @trainingDurationHoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get trainingDurationHoursLabel;

  /// No description provided for @trainingDurationMinutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get trainingDurationMinutesLabel;

  /// No description provided for @trainingDurationSecondsLabel.
  ///
  /// In en, this message translates to:
  /// **'Seconds'**
  String get trainingDurationSecondsLabel;

  /// No description provided for @trainingDimensionLoad.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get trainingDimensionLoad;

  /// No description provided for @trainingDimensionReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get trainingDimensionReps;

  /// No description provided for @trainingDimensionDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get trainingDimensionDuration;

  /// No description provided for @trainingDimensionDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get trainingDimensionDistance;

  /// No description provided for @trainingUnitKilogram.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get trainingUnitKilogram;

  /// No description provided for @trainingUnitPound.
  ///
  /// In en, this message translates to:
  /// **'lb'**
  String get trainingUnitPound;

  /// No description provided for @trainingUnitRepetition.
  ///
  /// In en, this message translates to:
  /// **'reps'**
  String get trainingUnitRepetition;

  /// No description provided for @trainingUnitHour.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get trainingUnitHour;

  /// No description provided for @trainingUnitMinute.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get trainingUnitMinute;

  /// No description provided for @trainingUnitSecond.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get trainingUnitSecond;

  /// No description provided for @trainingUnitKilometer.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get trainingUnitKilometer;

  /// No description provided for @trainingUnitMile.
  ///
  /// In en, this message translates to:
  /// **'mi'**
  String get trainingUnitMile;

  /// No description provided for @workoutTemplatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Workout Templates'**
  String get workoutTemplatesTitle;

  /// No description provided for @workoutTemplatesLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reusable plans for one Workout'**
  String get workoutTemplatesLibrarySubtitle;

  /// No description provided for @workoutTemplatesNew.
  ///
  /// In en, this message translates to:
  /// **'New Workout Template'**
  String get workoutTemplatesNew;

  /// No description provided for @workoutTemplatesCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Workout Template'**
  String get workoutTemplatesCreateTitle;

  /// No description provided for @workoutTemplatesCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Workout Template'**
  String get workoutTemplatesCreate;

  /// No description provided for @workoutTemplatesNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Workout Template name'**
  String get workoutTemplatesNameLabel;

  /// No description provided for @workoutTemplatesNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Standing notes'**
  String get workoutTemplatesNotesLabel;

  /// No description provided for @workoutTemplatesCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get workoutTemplatesCancel;

  /// No description provided for @workoutTemplatesActiveHeading.
  ///
  /// In en, this message translates to:
  /// **'Active Workout Templates'**
  String get workoutTemplatesActiveHeading;

  /// No description provided for @workoutTemplatesArchivedHeading.
  ///
  /// In en, this message translates to:
  /// **'Archived Workout Templates'**
  String get workoutTemplatesArchivedHeading;

  /// No description provided for @workoutTemplatesShowArchived.
  ///
  /// In en, this message translates to:
  /// **'Show archived Workout Templates'**
  String get workoutTemplatesShowArchived;

  /// No description provided for @workoutTemplatesHideArchived.
  ///
  /// In en, this message translates to:
  /// **'Hide archived Workout Templates'**
  String get workoutTemplatesHideArchived;

  /// No description provided for @workoutTemplatesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No Workout Templates yet'**
  String get workoutTemplatesEmptyTitle;

  /// No description provided for @workoutTemplatesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a reusable plan for one Workout.'**
  String get workoutTemplatesEmptyMessage;

  /// No description provided for @workoutTemplatesArchivedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No archived Workout Templates.'**
  String get workoutTemplatesArchivedEmpty;

  /// No description provided for @workoutTemplatesExerciseCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No Template Exercises} =1{1 Template Exercise} other{{count} Template Exercises}}'**
  String workoutTemplatesExerciseCount(int count);

  /// No description provided for @workoutTemplatesOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String workoutTemplatesOpenTooltip(String name);

  /// No description provided for @workoutTemplatesArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive Workout Template'**
  String get workoutTemplatesArchive;

  /// No description provided for @workoutTemplatesArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive Workout Template?'**
  String get workoutTemplatesArchiveTitle;

  /// No description provided for @workoutTemplatesArchiveMessage.
  ///
  /// In en, this message translates to:
  /// **'This hides the template from active lists and pickers. Logged Workouts remain unchanged.'**
  String get workoutTemplatesArchiveMessage;

  /// No description provided for @workoutTemplatesRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore Workout Template'**
  String get workoutTemplatesRestore;

  /// No description provided for @workoutTemplatesActionFailed.
  ///
  /// In en, this message translates to:
  /// **'The Workout Template could not be updated.'**
  String get workoutTemplatesActionFailed;

  /// No description provided for @workoutTemplatesStartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start {name}'**
  String workoutTemplatesStartTooltip(String name);

  /// No description provided for @workoutTemplatesStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The Workout could not be started.'**
  String get workoutTemplatesStartFailed;

  /// No description provided for @workoutTemplateEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Workout Template'**
  String get workoutTemplateEditorTitle;

  /// No description provided for @workoutTemplateSaveDetails.
  ///
  /// In en, this message translates to:
  /// **'Save Workout Template details'**
  String get workoutTemplateSaveDetails;

  /// No description provided for @workoutTemplateDetailsSaved.
  ///
  /// In en, this message translates to:
  /// **'Workout Template details saved'**
  String get workoutTemplateDetailsSaved;

  /// No description provided for @workoutTemplateExercisesHeading.
  ///
  /// In en, this message translates to:
  /// **'Template Exercises'**
  String get workoutTemplateExercisesHeading;

  /// No description provided for @workoutTemplateAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add Template Exercise'**
  String get workoutTemplateAddExercise;

  /// No description provided for @workoutTemplateNoExercises.
  ///
  /// In en, this message translates to:
  /// **'No Template Exercises. Add one to build the plan.'**
  String get workoutTemplateNoExercises;

  /// No description provided for @workoutTemplateExerciseNotes.
  ///
  /// In en, this message translates to:
  /// **'Exercise standing notes'**
  String get workoutTemplateExerciseNotes;

  /// No description provided for @workoutTemplateEditExerciseNotes.
  ///
  /// In en, this message translates to:
  /// **'Edit exercise notes'**
  String get workoutTemplateEditExerciseNotes;

  /// No description provided for @workoutTemplateSaveExerciseNotes.
  ///
  /// In en, this message translates to:
  /// **'Save exercise notes'**
  String get workoutTemplateSaveExerciseNotes;

  /// No description provided for @workoutTemplateRemoveExercise.
  ///
  /// In en, this message translates to:
  /// **'Remove Template Exercise'**
  String get workoutTemplateRemoveExercise;

  /// No description provided for @workoutTemplateRemoveExerciseTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Template Exercise?'**
  String get workoutTemplateRemoveExerciseTitle;

  /// No description provided for @workoutTemplateRemoveExerciseMessage.
  ///
  /// In en, this message translates to:
  /// **'Its Prescriptions are removed from this plan. Logged Workouts remain unchanged.'**
  String get workoutTemplateRemoveExerciseMessage;

  /// No description provided for @workoutTemplateReorderExercise.
  ///
  /// In en, this message translates to:
  /// **'Reorder Template Exercise'**
  String get workoutTemplateReorderExercise;

  /// No description provided for @workoutTemplatePrescriptionsHeading.
  ///
  /// In en, this message translates to:
  /// **'Prescriptions'**
  String get workoutTemplatePrescriptionsHeading;

  /// No description provided for @workoutTemplateAddPrescription.
  ///
  /// In en, this message translates to:
  /// **'Add Prescription'**
  String get workoutTemplateAddPrescription;

  /// No description provided for @workoutTemplateNoPrescriptions.
  ///
  /// In en, this message translates to:
  /// **'No Prescriptions'**
  String get workoutTemplateNoPrescriptions;

  /// No description provided for @workoutTemplateEditPrescription.
  ///
  /// In en, this message translates to:
  /// **'Edit Prescription'**
  String get workoutTemplateEditPrescription;

  /// No description provided for @workoutTemplatePrescriptionMode.
  ///
  /// In en, this message translates to:
  /// **'Prescription mode'**
  String get workoutTemplatePrescriptionMode;

  /// No description provided for @workoutTemplatePrescriptionFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed values'**
  String get workoutTemplatePrescriptionFixed;

  /// No description provided for @workoutTemplatePrescriptionCopyPrevious.
  ///
  /// In en, this message translates to:
  /// **'Copy previous'**
  String get workoutTemplatePrescriptionCopyPrevious;

  /// No description provided for @workoutTemplatePrescriptionCopyPreviousHelp.
  ///
  /// In en, this message translates to:
  /// **'Use the values from the previous session when this template is loaded.'**
  String get workoutTemplatePrescriptionCopyPreviousHelp;

  /// No description provided for @workoutTemplatePrescriptionRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get workoutTemplatePrescriptionRepeat;

  /// No description provided for @workoutTemplatePrescriptionRestAfter.
  ///
  /// In en, this message translates to:
  /// **'Rest after'**
  String get workoutTemplatePrescriptionRestAfter;

  /// No description provided for @workoutTemplatePrescriptionSeconds.
  ///
  /// In en, this message translates to:
  /// **'sec'**
  String get workoutTemplatePrescriptionSeconds;

  /// No description provided for @workoutTemplateSavePrescription.
  ///
  /// In en, this message translates to:
  /// **'Save Prescription'**
  String get workoutTemplateSavePrescription;

  /// No description provided for @workoutTemplateRemovePrescription.
  ///
  /// In en, this message translates to:
  /// **'Remove Prescription'**
  String get workoutTemplateRemovePrescription;

  /// No description provided for @workoutTemplateReorderPrescription.
  ///
  /// In en, this message translates to:
  /// **'Reorder Prescription'**
  String get workoutTemplateReorderPrescription;

  /// No description provided for @workoutTemplatePrescriptionCompletion.
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get workoutTemplatePrescriptionCompletion;

  /// No description provided for @workoutTemplatePrescriptionCopyPreviousSummary.
  ///
  /// In en, this message translates to:
  /// **'Copy previous values'**
  String get workoutTemplatePrescriptionCopyPreviousSummary;

  /// No description provided for @workoutTemplatePrescriptionInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter valid non-negative values, a repeat of at least 1, and optional non-negative rest.'**
  String get workoutTemplatePrescriptionInvalid;

  /// No description provided for @workoutTemplatePrescriptionWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Check Prescription values'**
  String get workoutTemplatePrescriptionWarningTitle;

  /// No description provided for @workoutTemplatePrescriptionSaveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get workoutTemplatePrescriptionSaveAnyway;

  /// No description provided for @workoutTemplateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Workout Template unavailable'**
  String get workoutTemplateUnavailable;

  /// No description provided for @workoutTemplateExercisePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Template Exercise'**
  String get workoutTemplateExercisePickerTitle;

  /// No description provided for @workoutTemplateGroupsHeading.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get workoutTemplateGroupsHeading;

  /// No description provided for @workoutTemplateAddGroup.
  ///
  /// In en, this message translates to:
  /// **'Add Group'**
  String get workoutTemplateAddGroup;

  /// No description provided for @workoutTemplateNoGroups.
  ///
  /// In en, this message translates to:
  /// **'No Groups. Add a superset or circuit to this plan.'**
  String get workoutTemplateNoGroups;

  /// No description provided for @workoutTemplateGroupNeedsExercises.
  ///
  /// In en, this message translates to:
  /// **'Add at least two ungrouped Template Exercises first.'**
  String get workoutTemplateGroupNeedsExercises;

  /// No description provided for @workoutTemplateCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get workoutTemplateCreateGroup;

  /// No description provided for @workoutTemplateEditGroup.
  ///
  /// In en, this message translates to:
  /// **'Edit Group'**
  String get workoutTemplateEditGroup;

  /// No description provided for @workoutTemplateGroupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get workoutTemplateGroupName;

  /// No description provided for @workoutTemplateGroupColor.
  ///
  /// In en, this message translates to:
  /// **'Group color'**
  String get workoutTemplateGroupColor;

  /// No description provided for @workoutTemplateGroupColorPreview.
  ///
  /// In en, this message translates to:
  /// **'Group color preview {color}'**
  String workoutTemplateGroupColorPreview(String color);

  /// No description provided for @workoutTemplateGroupRounds.
  ///
  /// In en, this message translates to:
  /// **'Rounds'**
  String get workoutTemplateGroupRounds;

  /// No description provided for @workoutTemplateGroupRoundsHelp.
  ///
  /// In en, this message translates to:
  /// **'A round is one pass through every exercise in this Group.'**
  String get workoutTemplateGroupRoundsHelp;

  /// No description provided for @workoutTemplateGroupMembers.
  ///
  /// In en, this message translates to:
  /// **'Template Exercises'**
  String get workoutTemplateGroupMembers;

  /// No description provided for @workoutTemplateSelectedGroupMembers.
  ///
  /// In en, this message translates to:
  /// **'Selected Template Exercises'**
  String get workoutTemplateSelectedGroupMembers;

  /// No description provided for @workoutTemplateAvailableGroupMembers.
  ///
  /// In en, this message translates to:
  /// **'Available Template Exercises'**
  String get workoutTemplateAvailableGroupMembers;

  /// No description provided for @workoutTemplateNoSelectedGroupMembers.
  ///
  /// In en, this message translates to:
  /// **'Select at least two Template Exercises below.'**
  String get workoutTemplateNoSelectedGroupMembers;

  /// No description provided for @workoutTemplateReorderGroupMember.
  ///
  /// In en, this message translates to:
  /// **'Reorder {name}'**
  String workoutTemplateReorderGroupMember(String name);

  /// No description provided for @workoutTemplateGroupMemberActions.
  ///
  /// In en, this message translates to:
  /// **'Group member actions for {name}'**
  String workoutTemplateGroupMemberActions(String name);

  /// No description provided for @workoutTemplateRemoveGroupMember.
  ///
  /// In en, this message translates to:
  /// **'Remove from Group'**
  String get workoutTemplateRemoveGroupMember;

  /// No description provided for @workoutTemplateGroupInOtherGroup.
  ///
  /// In en, this message translates to:
  /// **'In {name}'**
  String workoutTemplateGroupInOtherGroup(String name);

  /// No description provided for @workoutTemplateGroupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a Group name.'**
  String get workoutTemplateGroupNameRequired;

  /// No description provided for @workoutTemplateGroupColorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a color as #RRGGBB.'**
  String get workoutTemplateGroupColorInvalid;

  /// No description provided for @workoutTemplateGroupRoundsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Rounds must be a whole number of at least 1.'**
  String get workoutTemplateGroupRoundsInvalid;

  /// No description provided for @workoutTemplateGroupMembersInvalid.
  ///
  /// In en, this message translates to:
  /// **'Select at least two Template Exercises.'**
  String get workoutTemplateGroupMembersInvalid;

  /// No description provided for @workoutTemplateSaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Save Group'**
  String get workoutTemplateSaveGroup;

  /// No description provided for @workoutTemplateGroupActionFailed.
  ///
  /// In en, this message translates to:
  /// **'The Group could not be updated.'**
  String get workoutTemplateGroupActionFailed;

  /// No description provided for @workoutTemplateGroupRoundsCount.
  ///
  /// In en, this message translates to:
  /// **'{rounds, plural, =1{1 round} other{{rounds} rounds}}'**
  String workoutTemplateGroupRoundsCount(int rounds);

  /// No description provided for @workoutTemplateGroupMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Template Exercise} other{{count} Template Exercises}}'**
  String workoutTemplateGroupMemberCount(int count);

  /// No description provided for @workoutTemplateGroupMembership.
  ///
  /// In en, this message translates to:
  /// **'{name} · {rounds, plural, =1{1 round} other{{rounds} rounds}}'**
  String workoutTemplateGroupMembership(String name, int rounds);

  /// No description provided for @workoutTemplateGroupColorIndicator.
  ///
  /// In en, this message translates to:
  /// **'Group color for {name}'**
  String workoutTemplateGroupColorIndicator(String name);

  /// No description provided for @workoutTemplateReorderGroup.
  ///
  /// In en, this message translates to:
  /// **'Reorder Group {name}'**
  String workoutTemplateReorderGroup(String name);

  /// No description provided for @workoutTemplateGroupActions.
  ///
  /// In en, this message translates to:
  /// **'Group actions for {name}'**
  String workoutTemplateGroupActions(String name);

  /// No description provided for @workoutTemplateMoveGroupEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get workoutTemplateMoveGroupEarlier;

  /// No description provided for @workoutTemplateMoveGroupLater.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get workoutTemplateMoveGroupLater;

  /// No description provided for @workoutTemplateDissolveGroup.
  ///
  /// In en, this message translates to:
  /// **'Dissolve Group'**
  String get workoutTemplateDissolveGroup;

  /// No description provided for @workoutTemplateDissolveGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Dissolve {name}?'**
  String workoutTemplateDissolveGroupTitle(String name);

  /// No description provided for @workoutTemplateDissolveGroupMessage.
  ///
  /// In en, this message translates to:
  /// **'Exercises and Prescriptions stay in this Workout Template.'**
  String get workoutTemplateDissolveGroupMessage;

  /// No description provided for @workoutTemplateDissolveGroupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Group dissolved'**
  String get workoutTemplateDissolveGroupSuccess;

  /// No description provided for @workoutTemplateGroupedExerciseRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove from {name} first'**
  String workoutTemplateGroupedExerciseRemoveTitle(String name);

  /// No description provided for @workoutTemplateGroupedExerciseRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit or dissolve the Group before removing this Template Exercise.'**
  String get workoutTemplateGroupedExerciseRemoveMessage;

  /// No description provided for @routinePlansTitle.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get routinePlansTitle;

  /// No description provided for @routinePlansNew.
  ///
  /// In en, this message translates to:
  /// **'New Routine'**
  String get routinePlansNew;

  /// No description provided for @routinePlansCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Routine'**
  String get routinePlansCreateTitle;

  /// No description provided for @routinePlansCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Routine'**
  String get routinePlansCreate;

  /// No description provided for @routinePlansNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Routine name'**
  String get routinePlansNameLabel;

  /// No description provided for @routinePlansNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get routinePlansNotesLabel;

  /// No description provided for @routinePlansNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a Routine name.'**
  String get routinePlansNameRequired;

  /// No description provided for @routinePlansUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Routines unavailable'**
  String get routinePlansUnavailable;

  /// No description provided for @routinePlansActionFailed.
  ///
  /// In en, this message translates to:
  /// **'The Routine could not be updated.'**
  String get routinePlansActionFailed;

  /// No description provided for @routinePlansEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No Routines yet'**
  String get routinePlansEmptyTitle;

  /// No description provided for @routinePlansEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a Routine to keep an ordered collection of Workout Templates.'**
  String get routinePlansEmptyMessage;

  /// No description provided for @routinePlansActiveHeading.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get routinePlansActiveHeading;

  /// No description provided for @routinePlansShowArchived.
  ///
  /// In en, this message translates to:
  /// **'Show archived Routines'**
  String get routinePlansShowArchived;

  /// No description provided for @routinePlansHideArchived.
  ///
  /// In en, this message translates to:
  /// **'Hide archived Routines'**
  String get routinePlansHideArchived;

  /// No description provided for @routinePlansArchivedHeading.
  ///
  /// In en, this message translates to:
  /// **'ARCHIVED'**
  String get routinePlansArchivedHeading;

  /// No description provided for @routinePlansArchivedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No archived Routines'**
  String get routinePlansArchivedEmpty;

  /// No description provided for @routinePlansTemplateCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Workout Template} other{{count} Workout Templates}}'**
  String routinePlansTemplateCount(int count);

  /// No description provided for @routinePlansArchivedTemplateCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 archived} other{{count} archived}}'**
  String routinePlansArchivedTemplateCount(int count);

  /// No description provided for @routinePlansOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open Routine {name}'**
  String routinePlansOpenTooltip(String name);

  /// No description provided for @routinePlansArchivedTileLabel.
  ///
  /// In en, this message translates to:
  /// **'Archived Routine {name}'**
  String routinePlansArchivedTileLabel(String name);

  /// No description provided for @routinePlansArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive Routine'**
  String get routinePlansArchive;

  /// No description provided for @routinePlansRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore Routine'**
  String get routinePlansRestore;

  /// No description provided for @routinePlansStartTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start {name}'**
  String routinePlansStartTooltip(String name);

  /// No description provided for @routinePlansStartSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Start {name}'**
  String routinePlansStartSheetTitle(String name);

  /// No description provided for @routinePlansStartEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add a Workout Template to this Routine first.'**
  String get routinePlansStartEmptyMessage;

  /// No description provided for @routinePlansStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The Workout could not be started.'**
  String get routinePlansStartFailed;

  /// No description provided for @routinePlansCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get routinePlansCancel;

  /// No description provided for @routinePlansArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive {name}?'**
  String routinePlansArchiveTitle(String name);

  /// No description provided for @routinePlansArchiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Workout Templates and this Routine\'s references remain unchanged and restorable.'**
  String get routinePlansArchiveMessage;

  /// No description provided for @routinePlansSaveDetails.
  ///
  /// In en, this message translates to:
  /// **'Save Routine'**
  String get routinePlansSaveDetails;

  /// No description provided for @routinePlansTemplatesHeading.
  ///
  /// In en, this message translates to:
  /// **'Workout Templates'**
  String get routinePlansTemplatesHeading;

  /// No description provided for @routinePlansAddTemplate.
  ///
  /// In en, this message translates to:
  /// **'Add Workout Template'**
  String get routinePlansAddTemplate;

  /// No description provided for @routinePlansNoTemplates.
  ///
  /// In en, this message translates to:
  /// **'No Workout Templates in this Routine yet.'**
  String get routinePlansNoTemplates;

  /// No description provided for @routinePlansTemplateLabel.
  ///
  /// In en, this message translates to:
  /// **'Workout Template'**
  String get routinePlansTemplateLabel;

  /// No description provided for @routinePlansArchivedTemplateLabel.
  ///
  /// In en, this message translates to:
  /// **'Archived Workout Template'**
  String get routinePlansArchivedTemplateLabel;

  /// No description provided for @routinePlansRestoreTemplate.
  ///
  /// In en, this message translates to:
  /// **'Restore Workout Template'**
  String get routinePlansRestoreTemplate;

  /// No description provided for @routinePlansReorderTemplate.
  ///
  /// In en, this message translates to:
  /// **'Reorder {name}'**
  String routinePlansReorderTemplate(String name);

  /// No description provided for @routinePlansEntryActions.
  ///
  /// In en, this message translates to:
  /// **'Routine entry actions for {name}'**
  String routinePlansEntryActions(String name);

  /// No description provided for @routinePlansMoveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get routinePlansMoveEarlier;

  /// No description provided for @routinePlansMoveLater.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get routinePlansMoveLater;

  /// No description provided for @routinePlansRemoveReference.
  ///
  /// In en, this message translates to:
  /// **'Remove from Routine'**
  String get routinePlansRemoveReference;

  /// No description provided for @routinePlansRemoveReferenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String routinePlansRemoveReferenceTitle(String name);

  /// No description provided for @routinePlansRemoveReferenceMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes only the reference from {name}. The Workout Template remains available everywhere else.'**
  String routinePlansRemoveReferenceMessage(String name);

  /// No description provided for @routinePlansTemplatePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Workout Template'**
  String get routinePlansTemplatePickerTitle;

  /// No description provided for @routinePlansNoAvailableTemplates.
  ///
  /// In en, this message translates to:
  /// **'Create an active Workout Template in Library before adding one to this Routine.'**
  String get routinePlansNoAvailableTemplates;

  /// No description provided for @routinePlansCadenceHeading.
  ///
  /// In en, this message translates to:
  /// **'Cadence'**
  String get routinePlansCadenceHeading;

  /// No description provided for @routinePlansCadenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Routine cadence'**
  String get routinePlansCadenceLabel;

  /// No description provided for @routinePlansCadenceNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get routinePlansCadenceNone;

  /// No description provided for @routinePlansCadenceWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get routinePlansCadenceWeekly;

  /// No description provided for @routinePlansCadenceRotating.
  ///
  /// In en, this message translates to:
  /// **'Rotating'**
  String get routinePlansCadenceRotating;

  /// No description provided for @routinePlansRotatingWindowLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of positions'**
  String get routinePlansRotatingWindowLabel;

  /// No description provided for @routinePlansRotatingWindowHelp.
  ///
  /// In en, this message translates to:
  /// **'Each position can contain more than one Workout Template.'**
  String get routinePlansRotatingWindowHelp;

  /// No description provided for @routinePlansRotatingWindowError.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number of 1 or more.'**
  String get routinePlansRotatingWindowError;

  /// No description provided for @routinePlansCadenceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid Cadence.'**
  String get routinePlansCadenceInvalid;

  /// No description provided for @routinePlansSaveCadence.
  ///
  /// In en, this message translates to:
  /// **'Save Cadence'**
  String get routinePlansSaveCadence;

  /// No description provided for @routinePlansCadenceWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Save a long rotation?'**
  String get routinePlansCadenceWarningTitle;

  /// No description provided for @routinePlansCadenceWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'A rotating Cadence above 31 positions is unusual. You can still save it.'**
  String get routinePlansCadenceWarningMessage;

  /// No description provided for @routinePlansSaveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get routinePlansSaveAnyway;

  /// No description provided for @routinePlansMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get routinePlansMonday;

  /// No description provided for @routinePlansTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get routinePlansTuesday;

  /// No description provided for @routinePlansWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get routinePlansWednesday;

  /// No description provided for @routinePlansThursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get routinePlansThursday;

  /// No description provided for @routinePlansFriday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get routinePlansFriday;

  /// No description provided for @routinePlansSaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get routinePlansSaturday;

  /// No description provided for @routinePlansSunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get routinePlansSunday;

  /// No description provided for @routinePlansRotatingSlot.
  ///
  /// In en, this message translates to:
  /// **'Position {slot}'**
  String routinePlansRotatingSlot(int slot);

  /// No description provided for @routinePlansAddTemplateToSlot.
  ///
  /// In en, this message translates to:
  /// **'Add Workout Template to {slot}'**
  String routinePlansAddTemplateToSlot(String slot);

  /// No description provided for @routinePlansDropHere.
  ///
  /// In en, this message translates to:
  /// **'Move here'**
  String get routinePlansDropHere;

  /// No description provided for @routinePlansRest.
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get routinePlansRest;

  /// No description provided for @routinePlansRestSlotLabel.
  ///
  /// In en, this message translates to:
  /// **'{slot}, Rest'**
  String routinePlansRestSlotLabel(String slot);

  /// No description provided for @routinePlansMoveToSlot.
  ///
  /// In en, this message translates to:
  /// **'Move to another slot'**
  String get routinePlansMoveToSlot;

  /// No description provided for @routinePlansMoveToSlotTitle.
  ///
  /// In en, this message translates to:
  /// **'Move {name}'**
  String routinePlansMoveToSlotTitle(String name);

  /// No description provided for @routinePlansCurrentSlot.
  ///
  /// In en, this message translates to:
  /// **'Current slot'**
  String get routinePlansCurrentSlot;

  /// No description provided for @workoutCaptureMenuAction.
  ///
  /// In en, this message translates to:
  /// **'Save as Workout Template'**
  String get workoutCaptureMenuAction;

  /// No description provided for @workoutCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Save workout as template'**
  String get workoutCaptureTitle;

  /// No description provided for @workoutCaptureLoading.
  ///
  /// In en, this message translates to:
  /// **'Preparing capture preview'**
  String get workoutCaptureLoading;

  /// No description provided for @workoutCapturePreviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This workout could not be prepared for capture. Try again.'**
  String get workoutCapturePreviewUnavailable;

  /// No description provided for @workoutCaptureRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get workoutCaptureRetry;

  /// No description provided for @workoutCaptureClose.
  ///
  /// In en, this message translates to:
  /// **'Close capture sheet'**
  String get workoutCaptureClose;

  /// No description provided for @workoutCapturePickerClose.
  ///
  /// In en, this message translates to:
  /// **'Close picker'**
  String get workoutCapturePickerClose;

  /// No description provided for @workoutCaptureCountsSemantics.
  ///
  /// In en, this message translates to:
  /// **'Capture preview: {exerciseCount, plural, =0{no exercises} =1{1 exercise} other{{exerciseCount} exercises}}, {setCount, plural, =0{no sets} =1{1 set} other{{setCount} sets}}, and {groupCount, plural, =0{no groups} =1{1 group} other{{groupCount} groups}}.'**
  String workoutCaptureCountsSemantics(
      int exerciseCount, int setCount, int groupCount);

  /// No description provided for @workoutCaptureExerciseCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No exercises} =1{1 exercise} other{{count} exercises}}'**
  String workoutCaptureExerciseCount(int count);

  /// No description provided for @workoutCaptureSetCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No sets} =1{1 set} other{{count} sets}}'**
  String workoutCaptureSetCount(int count);

  /// No description provided for @workoutCaptureGroupCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No groups} =1{1 group} other{{count} groups}}'**
  String workoutCaptureGroupCount(int count);

  /// No description provided for @workoutCaptureNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Workout Template name'**
  String get workoutCaptureNameLabel;

  /// No description provided for @workoutCaptureNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a Workout Template name.'**
  String get workoutCaptureNameRequired;

  /// No description provided for @workoutCaptureRoutineLabel.
  ///
  /// In en, this message translates to:
  /// **'Add to Routine'**
  String get workoutCaptureRoutineLabel;

  /// No description provided for @workoutCaptureRoutineHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Collection Routines append the reference; Cadence Routines require a slot.'**
  String get workoutCaptureRoutineHelp;

  /// No description provided for @workoutCaptureRoutineNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get workoutCaptureRoutineNone;

  /// No description provided for @workoutCaptureRoutinesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading Routines'**
  String get workoutCaptureRoutinesLoading;

  /// No description provided for @workoutCaptureRoutinePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a Routine'**
  String get workoutCaptureRoutinePickerTitle;

  /// No description provided for @workoutCaptureRoutineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The selected Routine is no longer available. Choose another Routine or None.'**
  String get workoutCaptureRoutineUnavailable;

  /// No description provided for @workoutCaptureCadenceChanged.
  ///
  /// In en, this message translates to:
  /// **'This Routine\'s Cadence changed. Review the placement and choose an available slot.'**
  String get workoutCaptureCadenceChanged;

  /// No description provided for @workoutCaptureCadenceRoutineOption.
  ///
  /// In en, this message translates to:
  /// **'{name} - choose slot'**
  String workoutCaptureCadenceRoutineOption(String name);

  /// No description provided for @workoutCaptureCollectionRoutineOption.
  ///
  /// In en, this message translates to:
  /// **'{name} - collection'**
  String workoutCaptureCollectionRoutineOption(String name);

  /// No description provided for @workoutCaptureSlotLabel.
  ///
  /// In en, this message translates to:
  /// **'Cadence slot'**
  String get workoutCaptureSlotLabel;

  /// No description provided for @workoutCaptureChooseSlot.
  ///
  /// In en, this message translates to:
  /// **'Choose a slot'**
  String get workoutCaptureChooseSlot;

  /// No description provided for @workoutCaptureSlotRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a Cadence slot.'**
  String get workoutCaptureSlotRequired;

  /// No description provided for @workoutCaptureSlotPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a Cadence slot'**
  String get workoutCaptureSlotPickerTitle;

  /// No description provided for @workoutCaptureSlotNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Slot number'**
  String get workoutCaptureSlotNumberLabel;

  /// No description provided for @workoutCaptureSlotRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a number from 1 to {count} or choose from the list.'**
  String workoutCaptureSlotRange(int count);

  /// No description provided for @workoutCaptureSlotOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Enter an available slot number.'**
  String get workoutCaptureSlotOutOfRange;

  /// No description provided for @workoutCaptureChooseSlotAction.
  ///
  /// In en, this message translates to:
  /// **'Choose slot'**
  String get workoutCaptureChooseSlotAction;

  /// No description provided for @workoutCaptureReferenceNote.
  ///
  /// In en, this message translates to:
  /// **'This creates a new Workout Template from the workout facts. The workout and its existing Template Link stay unchanged; Routine placement adds only a reference.'**
  String get workoutCaptureReferenceNote;

  /// No description provided for @workoutCaptureErrorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot save yet'**
  String get workoutCaptureErrorsTitle;

  /// No description provided for @workoutCaptureWarningsTitle.
  ///
  /// In en, this message translates to:
  /// **'Review before saving'**
  String get workoutCaptureWarningsTitle;

  /// No description provided for @workoutCaptureAcceptWarnings.
  ///
  /// In en, this message translates to:
  /// **'I reviewed these warnings and want to save anyway.'**
  String get workoutCaptureAcceptWarnings;

  /// No description provided for @workoutCaptureSave.
  ///
  /// In en, this message translates to:
  /// **'Save Template'**
  String get workoutCaptureSave;

  /// No description provided for @workoutCaptureSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get workoutCaptureSaving;

  /// No description provided for @workoutCaptureSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The Workout Template could not be saved. Review your choices and try again.'**
  String get workoutCaptureSaveFailed;

  /// No description provided for @workoutCaptureSaved.
  ///
  /// In en, this message translates to:
  /// **'Workout Template saved.'**
  String get workoutCaptureSaved;

  /// No description provided for @workoutUpdateTemplateMenuAction.
  ///
  /// In en, this message translates to:
  /// **'Update template'**
  String get workoutUpdateTemplateMenuAction;

  /// No description provided for @templateUpdatePromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Update \"{name}\"?'**
  String templateUpdatePromptTitle(String name);

  /// No description provided for @templateUpdateDismissAction.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get templateUpdateDismissAction;

  /// No description provided for @templateUpdateConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Update template'**
  String get templateUpdateConfirmAction;

  /// No description provided for @templateUpdateConfirmedMessage.
  ///
  /// In en, this message translates to:
  /// **'Template updated.'**
  String get templateUpdateConfirmedMessage;

  /// No description provided for @templateUpdateNotLinkedMessage.
  ///
  /// In en, this message translates to:
  /// **'This workout isn\'t linked to a Workout Template.'**
  String get templateUpdateNotLinkedMessage;

  /// No description provided for @templateUpdateGroupsChangedNote.
  ///
  /// In en, this message translates to:
  /// **'Exercise groups changed'**
  String get templateUpdateGroupsChangedNote;

  /// No description provided for @templateUpdateNoChangesNote.
  ///
  /// In en, this message translates to:
  /// **'No changes to update'**
  String get templateUpdateNoChangesNote;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
