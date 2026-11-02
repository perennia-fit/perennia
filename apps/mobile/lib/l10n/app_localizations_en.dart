// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Perennia';

  @override
  String get homeTodayDestination => 'Today';

  @override
  String get homeProgressDestination => 'Progress';

  @override
  String get homeLibraryDestination => 'Library';

  @override
  String get homeProgressTitle => 'Progress';

  @override
  String get homeBodyTitle => 'Body';

  @override
  String get homeHealthMetricsTitle => 'Health metrics';

  @override
  String get homeLibraryTitle => 'Library';

  @override
  String get homeLibraryTrainingSection => 'TRAINING';

  @override
  String get homeLibraryProtocolsSection => 'PROTOCOLS';

  @override
  String get homeCreateExercise => 'Create exercise';

  @override
  String get homeCreateExerciseSubtitle =>
      'Add an exercise to your User Library';

  @override
  String get exerciseCatalogCreateExercise => 'Create exercise';

  @override
  String exerciseCatalogCreateNamedExercise(String name) {
    return 'Create \"$name\"';
  }

  @override
  String get exerciseCatalogEmptyLibrary => 'No exercises in your library yet';

  @override
  String get exerciseCatalogNoMatches =>
      'No exercises match your search and filters';

  @override
  String get homeAccountAndAppTitle => 'Account & app';

  @override
  String get homeAccountStatusLoading => 'Checking account status';

  @override
  String get homeAccountStatusUnavailable => 'Account status unavailable';

  @override
  String get homeLocalOnlyStatus => 'Local only';

  @override
  String get homeSignInToSync => 'Sign in to sync';

  @override
  String get homeManageAccountAndSync => 'Manage account and sync';

  @override
  String get homeLogAction => 'Log';

  @override
  String get homeLogSheetTitle => 'Log for this day';

  @override
  String get homeLogWorkout => 'Workout';

  @override
  String get homeStartWorkoutFailed => 'Could not start workout. Try again.';

  @override
  String get homeLogFood => 'Food';

  @override
  String get homeLogDose => 'Dose';

  @override
  String get homeDomainToggleLabel => 'Home domain';

  @override
  String get homeTrainingDomain => 'Training';

  @override
  String get homeNutritionDomain => 'Nutrition';

  @override
  String get homeUnavailable => 'Home unavailable';

  @override
  String get homeNutritionUnavailable => 'Nutrition Day unavailable';

  @override
  String get homeStartNewWorkout => 'Start workout';

  @override
  String get homeLoadRoutine => 'Routines';

  @override
  String get homeAddExercise => 'Add exercise';

  @override
  String homeSessionHeader(String time) {
    return 'Session $time';
  }

  @override
  String get homeSaveCommentTooltip => 'Save comment';

  @override
  String get homeCopyWorkoutTooltip => 'Copy workout';

  @override
  String get homeMoveWorkoutTooltip => 'Move workout';

  @override
  String get homeShareWorkoutTooltip => 'Share workout';

  @override
  String get homeWorkoutCommentLabel => 'Workout comment';

  @override
  String get homeWorkoutSummaryCopied => 'Workout summary copied';

  @override
  String get homePreviousDayTooltip => 'Previous day';

  @override
  String get homeNextDayTooltip => 'Next day';

  @override
  String get homeNoExercisesLoggedYet => 'No exercises logged yet';

  @override
  String get homeNoSetsYet => 'No sets yet';

  @override
  String get homeUpNextTitle => 'Up next';

  @override
  String homeUpNextRoutineSubtitle(String routineName, String slotLabel) {
    return '$routineName · $slotLabel';
  }

  @override
  String homeUpNextStartTooltip(String templateName) {
    return 'Start $templateName';
  }

  @override
  String homeUpNextDoneLabel(String templateName) {
    return '$templateName, done';
  }

  @override
  String get homeUpNextStartFailed =>
      'Could not start this session. Try again.';

  @override
  String get templatePickerPreviewStart => 'Start workout';

  @override
  String get templatePickerPreviewExercisesHeading => 'Exercises';

  @override
  String get templatePickerPreviewEmptyExercises =>
      'No exercises in this workout yet.';

  @override
  String get routinesSheetTitle => 'Routines';

  @override
  String get routinesSheetManage => 'Manage';

  @override
  String get routinesSheetEdit => 'Edit';

  @override
  String get routinesSheetBack => 'All routines';

  @override
  String routinesSheetNext(String name) {
    return 'Next: $name';
  }

  @override
  String get routinesSheetUpNext => 'Up next';

  @override
  String get routinesSheetDone => 'Done';

  @override
  String routinesSheetWorkoutCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count workouts',
      one: '1 workout',
    );
    return '$_temp0';
  }

  @override
  String routinesSheetExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
      zero: 'No exercises',
    );
    return '$_temp0';
  }

  @override
  String get routinesSheetOtherWorkouts => 'Other saved workouts';

  @override
  String get routinesSheetNotInRoutine => 'Not in a routine';

  @override
  String routinesSheetPreviewTooltip(String name) {
    return 'Preview $name';
  }

  @override
  String get routinesSheetEmptyTitle => 'No routines yet';

  @override
  String get routinesSheetEmptyMessage =>
      'Create a routine to start its workouts from here.';

  @override
  String get routinesSheetEmptyAction => 'Create a routine';

  @override
  String get workoutTitle => 'Workout';

  @override
  String get workoutUnavailable => 'Workout unavailable';

  @override
  String get workoutSummaryListTitle => 'Workouts';

  @override
  String get workoutExercisesTitle => 'Exercises';

  @override
  String get workoutNotesTitle => 'Notes';

  @override
  String get workoutNotesButton => 'Notes';

  @override
  String get workoutOptionsTooltip => 'Workout options';

  @override
  String get workoutOpenStatus => 'Open';

  @override
  String get workoutFinishedStatus => 'Finished';

  @override
  String workoutStartedAt(String time) {
    return 'Started $time';
  }

  @override
  String workoutTimeRange(String start, String end) {
    return '$start-$end';
  }

  @override
  String get workoutFinish => 'Finish Workout';

  @override
  String get workoutResume => 'Resume Workout';

  @override
  String get workoutFinished => 'Workout finished';

  @override
  String get workoutResumed => 'Workout resumed';

  @override
  String get workoutShareAction => 'Share';

  @override
  String get workoutEditStartTime => 'Edit start time';

  @override
  String get workoutEditFinishTime => 'Edit finish time';

  @override
  String get workoutStartTimeUpdated => 'Start time updated';

  @override
  String get workoutFinishTimeUpdated => 'Finish time updated';

  @override
  String get workoutStartTimeAfterFinish =>
      'Start time must be before finish time';

  @override
  String get workoutFinishTimeBeforeStart =>
      'Finish time must be after start time';

  @override
  String get workoutDelete => 'Delete workout';

  @override
  String get workoutDeleteTitle => 'Delete workout?';

  @override
  String get workoutDeleteMessage =>
      'This removes the workout and its sets from your log. History can still be recovered from the Activity Log.';

  @override
  String get workoutCopied => 'Workout copied';

  @override
  String get workoutMoved => 'Workout moved';

  @override
  String get workoutRemoveExerciseTooltip => 'Remove exercise';

  @override
  String get workoutReorderExerciseTooltip => 'Reorder exercise';

  @override
  String workoutLinkSupersetTooltip(String firstName, String secondName) {
    return 'Link $firstName and $secondName as a superset';
  }

  @override
  String workoutUnlinkSupersetTooltip(
      String firstName, String secondName, String groupName) {
    return 'Unlink $firstName and $secondName from $groupName';
  }

  @override
  String get workoutSupersetUpdateFailed =>
      'Could not update superset. Try again.';

  @override
  String get workoutExerciseRemoved => 'Exercise removed';

  @override
  String get workoutSaveNote => 'Save note';

  @override
  String get workoutDeleteNote => 'Delete note';

  @override
  String get workoutNoteSaved => 'Workout note saved';

  @override
  String get workoutNoteDeleted => 'Workout note deleted';

  @override
  String get workoutNoExercises => 'No exercises';

  @override
  String get workoutOneExercise => '1 exercise';

  @override
  String workoutExerciseCount(int count) {
    return '$count exercises';
  }

  @override
  String get workoutNoSets => 'No sets';

  @override
  String get workoutOneSet => '1 set';

  @override
  String workoutSetCount(int count) {
    return '$count sets';
  }

  @override
  String get cancelAction => 'Cancel';

  @override
  String get workoutDurationInProgress => 'In progress';

  @override
  String workoutDurationHours(int hours) {
    return '${hours}h';
  }

  @override
  String workoutDurationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String workoutDurationMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String workoutDurationSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String get navSignIn => 'Sign in';

  @override
  String get navRecentActivity => 'Recent activity';

  @override
  String get navRoutines => 'Routines';

  @override
  String get navCompounds => 'Compounds';

  @override
  String get protocolsDomainTitle => 'Protocols';

  @override
  String get protocolsLibrarySubtitle =>
      'What you take, when, and for how long';

  @override
  String get compoundsLibrarySubtitle =>
      'Everything you take, and each one\'s history';

  @override
  String get protocolsYourProtocols => 'Your protocols';

  @override
  String get protocolsNewProtocol => 'New protocol';

  @override
  String get protocolsLogDose => 'Log a dose';

  @override
  String get protocolsLoggedHeading => 'Logged';

  @override
  String get protocolsNothingToday => 'Nothing planned or logged on this day.';

  @override
  String get protocolsIntroTitle => 'Plan what you take';

  @override
  String get protocolsIntroMessage =>
      'A protocol lists what you take and when. With times set, it can remind you when each dose is due.';

  @override
  String get protocolsLockedTitle => 'Protocols are locked';

  @override
  String get protocolsLockUnavailableTitle => 'Protocols lock unavailable';

  @override
  String get protocolsLockUnavailableMessage =>
      'Protocols stay hidden because the device\'s secure storage could not be read.';

  @override
  String get privacyShowProtocolsOnToday => 'Show Protocols on Today';

  @override
  String get privacyShowProtocolsOnTodaySubtitle =>
      'Off hides the tab on this device. Protocols stay in Library.';

  @override
  String get navSettings => 'Settings';

  @override
  String get navBodyTracker => 'Body Tracker';

  @override
  String get navMetrics => 'Metrics';

  @override
  String get agentKeysSignedOutTitle => 'Sign in to manage agent keys';

  @override
  String get agentKeysSignIn => 'Sign in';

  @override
  String get agentKeysNameLabel => 'Agent key name';

  @override
  String get agentKeysCreate => 'Create key';

  @override
  String get agentKeysSecretShownOnceSemanticLabel =>
      'Agent API key secret shown once';

  @override
  String get agentKeysSecretShownOnceTitle => 'Secret shown once';

  @override
  String get agentKeysCopySecretTooltip => 'Copy secret';

  @override
  String get agentKeysCopiedMessage => 'Agent key copied';

  @override
  String get agentKeysSecretWarning =>
      'Copy it now. It will not be shown again.';

  @override
  String get agentKeysDone => 'Done';

  @override
  String get agentKeysEmpty => 'No agent keys';

  @override
  String get agentKeysRevokeTooltip => 'Revoke key';

  @override
  String get agentKeysNeverUsed => 'Never';

  @override
  String agentKeysStarts(String start) {
    return 'Starts $start';
  }

  @override
  String agentKeysCreated(String created) {
    return 'Created $created';
  }

  @override
  String agentKeysLastUsed(String lastUsed) {
    return 'Last used $lastUsed';
  }

  @override
  String get bodyTrackerTitle => 'Body Tracker';

  @override
  String get bodyTrackerUnavailable => 'Body Tracker unavailable';

  @override
  String get metricsTitle => 'Metrics';

  @override
  String get metricsUnavailable => 'Metrics unavailable';

  @override
  String get metricsEmpty => 'No monitoring readings yet';

  @override
  String metricsLatestReading(String time) {
    return 'Last reading $time';
  }

  @override
  String get metricsIntegrationProvenance => 'Integration';

  @override
  String get metricsManualProvenance => 'Manual';

  @override
  String get metricsAgentProvenance => 'Agent';

  @override
  String metricsSource(String source) {
    return 'Source $source';
  }

  @override
  String get metricsAddMetric => 'Add Metric';

  @override
  String get metricsAddMetricTooltip => 'Add a Metric';

  @override
  String get metricsCreateMetricTitle => 'New Metric';

  @override
  String get metricsNameLabel => 'Name';

  @override
  String get metricsNameRequired => 'Name is required';

  @override
  String get metricsUnitLabel => 'Unit';

  @override
  String get metricsUnitRequired => 'Unit is required';

  @override
  String get metricsUnitHint => 'e.g. ng/dL, kg, bpm';

  @override
  String get metricsCreate => 'Create';

  @override
  String get metricsMetricCreated => 'Metric created';

  @override
  String get metricsLogReadingTooltip => 'Log a reading';

  @override
  String get metricsLogReadingTitle => 'Log Reading';

  @override
  String get metricsValueLabel => 'Value';

  @override
  String get metricsMeasuredAtLabel => 'Measured at';

  @override
  String get metricsCommentLabel => 'Comment';

  @override
  String get metricsSaveReading => 'Save';

  @override
  String get metricsReadingSaved => 'Reading saved';

  @override
  String get metricsInvalidValue => 'Enter a valid number';

  @override
  String get metricsInvalidDateTime =>
      'Enter a valid date and time (yyyy-MM-dd HH:mm)';

  @override
  String get bodyTrackerNoValueYet => 'No value yet';

  @override
  String bodyTrackerLatestRecency(String recency) {
    return 'Last measured $recency';
  }

  @override
  String bodyTrackerValueWithUnit(String value, String unit) {
    return '$value $unit';
  }

  @override
  String get bodyTrackerValueLabel => 'Value';

  @override
  String get bodyTrackerMeasuredAtLabel => 'Date/time';

  @override
  String get bodyTrackerCommentLabel => 'Comment';

  @override
  String get bodyTrackerSaveEntry => 'Save entry';

  @override
  String get bodyTrackerUpdateEntry => 'Update entry';

  @override
  String get bodyTrackerEntrySaved => 'Measurement saved';

  @override
  String get bodyTrackerEntryUpdated => 'Measurement updated';

  @override
  String get bodyTrackerEntryDeleted => 'Measurement deleted';

  @override
  String get bodyTrackerHistoryTitle => 'History';

  @override
  String get bodyTrackerHistoryTooltip => 'Open history';

  @override
  String get bodyTrackerHistoryEmpty => 'No measurement history yet';

  @override
  String get bodyTrackerHistoryFilterLabel => 'Measurement';

  @override
  String get bodyTrackerHistoryAllMeasurements => 'All measurements';

  @override
  String get bodyTrackerProgressTitle => 'Progress';

  @override
  String get bodyTrackerProgressTooltip => 'Open progress graph';

  @override
  String get bodyTrackerProgressEmpty => 'No measurement entries yet';

  @override
  String bodyTrackerProgressGraphSemanticLabel(String measurement, int raw) {
    return 'Progress graph, $measurement, $raw raw points';
  }

  @override
  String get bodyTrackerProgressGraphHint => 'Tap to inspect a raw graph value';

  @override
  String bodyTrackerProgressTargetLine(String value, String unit) {
    return 'Target $value $unit';
  }

  @override
  String bodyTrackerProgressDownsampled(int rendered, int raw) {
    return 'Rendering $rendered of $raw raw points';
  }

  @override
  String bodyTrackerProgressSelected(
      String measurement, String value, String unit, String date) {
    return '$measurement: $value $unit on $date';
  }

  @override
  String get bodyTrackerManageTooltip => 'Manage measurements';

  @override
  String get bodyTrackerManageTitle => 'Manage measurements';

  @override
  String get bodyTrackerAddMeasurement => 'Add measurement';

  @override
  String get bodyTrackerCreateMeasurementTitle => 'New measurement';

  @override
  String get bodyTrackerMeasurementNameLabel => 'Name';

  @override
  String get bodyTrackerMeasurementUnitLabel => 'Unit';

  @override
  String get bodyTrackerMeasurementGoalLabel => 'Goal';

  @override
  String get bodyTrackerMeasurementEnabledLabel => 'Enabled';

  @override
  String get bodyTrackerMeasurementTargetLabel => 'Target value';

  @override
  String get bodyTrackerMeasurementNameRequired => 'Enter a name';

  @override
  String get bodyTrackerMeasurementTargetRequired =>
      'Enter a non-negative target';

  @override
  String get bodyTrackerMeasurementCreated => 'Measurement created';

  @override
  String get bodyTrackerMeasurementDeleted => 'Measurement archived';

  @override
  String get bodyTrackerMeasurementReset => 'Measurements reset';

  @override
  String get bodyTrackerResetMeasurementsTooltip => 'Reset measurements';

  @override
  String get bodyTrackerReorderMeasurementTooltip => 'Reorder measurement';

  @override
  String get bodyTrackerDeleteMeasurementTooltip => 'Archive measurement';

  @override
  String get bodyTrackerDeleteMeasurementTitle => 'Archive measurement?';

  @override
  String get bodyTrackerDeleteMeasurementMessage =>
      'This measurement will leave Body Tracker, but its entries stay in history.';

  @override
  String get bodyTrackerResetMeasurementsTitle => 'Reset measurements?';

  @override
  String get bodyTrackerResetMeasurementsMessage =>
      'This restores Body Weight and Body Fat, enables them, and archives custom measurements.';

  @override
  String get bodyTrackerCancel => 'Cancel';

  @override
  String get bodyTrackerCreate => 'Create';

  @override
  String get bodyTrackerArchive => 'Archive';

  @override
  String get bodyTrackerReset => 'Reset';

  @override
  String get bodyTrackerGoalIncrease => 'Increase';

  @override
  String get bodyTrackerGoalDecrease => 'Decrease';

  @override
  String get bodyTrackerGoalTarget => 'Target';

  @override
  String get bodyTrackerDeleteEntryTooltip => 'Delete measurement entry';

  @override
  String get bodyTrackerDeleteEntryTitle => 'Delete measurement entry?';

  @override
  String get bodyTrackerDeleteEntryMessage =>
      'This entry will be removed from History.';

  @override
  String get bodyTrackerDeleteEntryCancel => 'Cancel';

  @override
  String get bodyTrackerDeleteEntryConfirm => 'Delete';

  @override
  String get bodyTrackerInvalidValue =>
      'Enter a non-negative value with up to 5 decimals';

  @override
  String get bodyTrackerInvalidDateTime => 'Use YYYY-MM-DD HH:mm';

  @override
  String get bodyTrackerSuspiciousValueTitle => 'Unusual measurement value';

  @override
  String bodyTrackerSuspiciousValueMessage(String value, String unit) {
    return '$value $unit is outside the usual range. Save it anyway?';
  }

  @override
  String get bodyTrackerSuspiciousValueCancel => 'Review';

  @override
  String get bodyTrackerSuspiciousValueConfirm => 'Save anyway';

  @override
  String get bodyTrackerUnitKilogram => 'kg';

  @override
  String get bodyTrackerUnitPound => 'lb';

  @override
  String get bodyTrackerUnitCentimeter => 'cm';

  @override
  String get bodyTrackerUnitInch => 'in';

  @override
  String get bodyTrackerUnitPercent => '%';

  @override
  String get activityUndoSuccess => 'Activity undone';

  @override
  String get activityUnavailable => 'Recent activity unavailable';

  @override
  String get activityEmpty => 'No recent activity';

  @override
  String activityChangeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return '$_temp0';
  }

  @override
  String activityFeedSemanticLabel(
      String summary, String actor, String changes, String timestamp) {
    return '$summary, $actor, $changes, $timestamp';
  }

  @override
  String activityFeedSubtitle(String actor, String changes) {
    return '$actor - $changes';
  }

  @override
  String get activityAgentActor => 'Agent';

  @override
  String activityAgentActorWithKey(String keyId) {
    return 'Agent key $keyId';
  }

  @override
  String get activityUndoTooltip => 'Undo activity';

  @override
  String activityUndoConflict(int count, String entityTable, String entityId) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Could not undo $count changed rows: $entityTable $entityId',
      one: 'Could not undo 1 changed row: $entityTable $entityId',
    );
    return '$_temp0';
  }

  @override
  String get activityUndoGenericConflict => 'Activity could not be undone';

  @override
  String get activityRelativeLessThanOneMinuteAgo => 'less than 1 min ago';

  @override
  String activityRelativeMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String activityRelativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String activityRelativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get trainingBackgroundAlertsDenied =>
      'Background timer alerts are off. In-app countdowns still work while Perennia is open.';

  @override
  String get trainingFallbackTitle => 'Exercise';

  @override
  String get trainingUnavailable => 'Exercise unavailable';

  @override
  String get trainingOpenNavigationTooltip => 'Open navigation';

  @override
  String get trainingSetSaved => 'Set saved';

  @override
  String get trainingExercisesTitle => 'Exercises';

  @override
  String get trainingNoExercisesYet => 'No exercises yet';

  @override
  String get trainingGroupsTitle => 'Groups';

  @override
  String get trainingCreateGroupTooltip => 'Create group';

  @override
  String get trainingNoGroupsYet => 'No groups yet';

  @override
  String trainingSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets',
      one: '1 set',
    );
    return '$_temp0';
  }

  @override
  String get trainingOpenExerciseOverviewTooltip => 'Open exercise overview';

  @override
  String trainingGroupExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
    );
    return '$_temp0';
  }

  @override
  String get trainingEditGroupTooltip => 'Edit group';

  @override
  String get trainingGroupNameLabel => 'Group name';

  @override
  String get trainingGroupColorLabel => 'Color';

  @override
  String get trainingExerciseUngroupedIndicator => 'Exercise is not in a group';

  @override
  String trainingExerciseGroupIndicator(String groupName) {
    return 'Exercise group $groupName';
  }

  @override
  String trainingGroupColorIndicator(String groupName) {
    return 'Group color for $groupName';
  }

  @override
  String get trainingCancel => 'Cancel';

  @override
  String get trainingSaveGroup => 'Save group';

  @override
  String get trainingRestTimer => 'Rest timer';

  @override
  String trainingRestCountdown(String remaining) {
    return 'Rest $remaining';
  }

  @override
  String get trainingRestComplete => 'Rest complete';

  @override
  String get trainingRestSecondsLabel => 'Rest sec';

  @override
  String get trainingStartTimer => 'Start';

  @override
  String get trainingUpdateTimer => 'Update';

  @override
  String get trainingCancelTimerTooltip => 'Cancel timer';

  @override
  String get trainingPersonalRecordTooltip => 'Personal record';

  @override
  String get trainingEditSetTooltip => 'Edit set';

  @override
  String get trainingDeleteSetTooltip => 'Delete set';

  @override
  String get trainingMarkSetCompleteLabel => 'Mark set complete';

  @override
  String get trainingMarkSetIncompleteLabel => 'Mark set incomplete';

  @override
  String get trainingReorderSetLabel => 'Reorder set';

  @override
  String trainingDecreaseDimensionTooltip(String dimension) {
    return 'Decrease $dimension';
  }

  @override
  String trainingIncreaseDimensionTooltip(String dimension) {
    return 'Increase $dimension';
  }

  @override
  String get trainingCommentLabel => 'Comment';

  @override
  String get trainingSideLeft => 'L';

  @override
  String get trainingSideLeftTooltip => 'Left side';

  @override
  String get trainingSideRight => 'R';

  @override
  String get trainingSideRightTooltip => 'Right side';

  @override
  String get trainingRpeLabel => 'RPE';

  @override
  String get trainingSaveSet => 'Save set';

  @override
  String get trainingSaveChanges => 'Save changes';

  @override
  String get trainingCompletedSet => 'Completed set';

  @override
  String get trainingSetComplete => 'Complete';

  @override
  String get trainingSetInProgress => 'In progress';

  @override
  String trainingSetRpe(String rpe) {
    return 'RPE $rpe';
  }

  @override
  String get trainingDurationHoursLabel => 'Hours';

  @override
  String get trainingDurationMinutesLabel => 'Minutes';

  @override
  String get trainingDurationSecondsLabel => 'Seconds';

  @override
  String get trainingDimensionLoad => 'Load';

  @override
  String get trainingDimensionReps => 'Reps';

  @override
  String get trainingDimensionDuration => 'Duration';

  @override
  String get trainingDimensionDistance => 'Distance';

  @override
  String get trainingUnitKilogram => 'kg';

  @override
  String get trainingUnitPound => 'lb';

  @override
  String get trainingUnitRepetition => 'reps';

  @override
  String get trainingUnitHour => 'h';

  @override
  String get trainingUnitMinute => 'min';

  @override
  String get trainingUnitSecond => 'sec';

  @override
  String get trainingUnitKilometer => 'km';

  @override
  String get trainingUnitMile => 'mi';

  @override
  String get workoutTemplatesTitle => 'Saved workouts';

  @override
  String get workoutTemplatesLibrarySubtitle =>
      'Reusable plans for one workout';

  @override
  String get workoutTemplatesNew => 'New saved workout';

  @override
  String get workoutTemplatesCreateTitle => 'Create saved workout';

  @override
  String get workoutTemplatesCreate => 'Create saved workout';

  @override
  String get workoutTemplatesNameLabel => 'Workout name';

  @override
  String get workoutTemplatesNotesLabel => 'Standing notes';

  @override
  String get workoutTemplatesCancel => 'Cancel';

  @override
  String get workoutTemplatesActiveHeading => 'Active';

  @override
  String get workoutTemplatesArchivedHeading => 'Archived';

  @override
  String get workoutTemplatesShowArchived => 'Show archived workouts';

  @override
  String get workoutTemplatesHideArchived => 'Hide archived workouts';

  @override
  String get workoutTemplatesEmptyTitle => 'No saved workouts yet';

  @override
  String get workoutTemplatesEmptyMessage =>
      'Create a reusable plan for one Workout.';

  @override
  String get workoutTemplatesArchivedEmpty => 'No archived workouts.';

  @override
  String workoutTemplatesExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
      zero: 'No exercises',
    );
    return '$_temp0';
  }

  @override
  String workoutTemplatesOpenTooltip(String name) {
    return 'Open $name';
  }

  @override
  String get workoutTemplatesArchive => 'Archive saved workout';

  @override
  String get workoutTemplatesArchiveTitle => 'Archive saved workout?';

  @override
  String get workoutTemplatesArchiveMessage =>
      'This hides it from active lists and pickers. Logged workouts remain unchanged.';

  @override
  String get workoutTemplatesRestore => 'Restore saved workout';

  @override
  String get workoutTemplatesActionFailed =>
      'The saved workout could not be updated.';

  @override
  String workoutTemplatesStartTooltip(String name) {
    return 'Start $name';
  }

  @override
  String get workoutTemplatesStartFailed => 'The Workout could not be started.';

  @override
  String get workoutTemplateEditorTitle => 'Edit saved workout';

  @override
  String get workoutTemplateSaveDetails => 'Save details';

  @override
  String get workoutTemplateDetailsSaved => 'Details saved';

  @override
  String get workoutTemplateExercisesHeading => 'Exercises';

  @override
  String get workoutTemplateAddExercise => 'Add exercise';

  @override
  String get workoutTemplateNoExercises =>
      'No exercises. Add one to build the plan.';

  @override
  String get workoutTemplateExerciseNotes => 'Exercise standing notes';

  @override
  String get workoutTemplateEditExerciseNotes => 'Edit exercise notes';

  @override
  String get workoutTemplateSaveExerciseNotes => 'Save exercise notes';

  @override
  String get workoutTemplateRemoveExercise => 'Remove exercise';

  @override
  String get workoutTemplateRemoveExerciseTitle => 'Remove exercise?';

  @override
  String get workoutTemplateRemoveExerciseMessage =>
      'Its Prescriptions are removed from this plan. Logged Workouts remain unchanged.';

  @override
  String get workoutTemplateReorderExercise => 'Reorder exercise';

  @override
  String get workoutTemplatePrescriptionsHeading => 'Prescriptions';

  @override
  String get workoutTemplateAddPrescription => 'Add Prescription';

  @override
  String get workoutTemplateNoPrescriptions => 'No Prescriptions';

  @override
  String get workoutTemplateEditPrescription => 'Edit Prescription';

  @override
  String get workoutTemplatePrescriptionMode => 'Prescription mode';

  @override
  String get workoutTemplatePrescriptionFixed => 'Fixed values';

  @override
  String get workoutTemplatePrescriptionCopyPrevious => 'Copy previous';

  @override
  String get workoutTemplatePrescriptionCopyPreviousHelp =>
      'Use the values from the previous session when this workout is started.';

  @override
  String get workoutTemplatePrescriptionRepeat => 'Repeat';

  @override
  String get workoutTemplatePrescriptionRestAfter => 'Rest after';

  @override
  String get workoutTemplatePrescriptionSeconds => 'sec';

  @override
  String get workoutTemplateSavePrescription => 'Save Prescription';

  @override
  String get workoutTemplateRemovePrescription => 'Remove Prescription';

  @override
  String get workoutTemplateReorderPrescription => 'Reorder Prescription';

  @override
  String get workoutTemplatePrescriptionCompletion => 'Completion';

  @override
  String get workoutTemplatePrescriptionCopyPreviousSummary =>
      'Copy previous values';

  @override
  String get workoutTemplatePrescriptionInvalid =>
      'Enter valid non-negative values, a repeat of at least 1, and optional non-negative rest.';

  @override
  String get workoutTemplatePrescriptionWarningTitle =>
      'Check Prescription values';

  @override
  String get workoutTemplatePrescriptionSaveAnyway => 'Save anyway';

  @override
  String get workoutTemplateUnavailable => 'Saved workout unavailable';

  @override
  String get workoutTemplateExercisePickerTitle => 'Add exercise';

  @override
  String get workoutTemplateGroupsHeading => 'Groups';

  @override
  String get workoutTemplateAddGroup => 'Add Group';

  @override
  String get workoutTemplateNoGroups =>
      'No Groups. Add a superset or circuit to this plan.';

  @override
  String get workoutTemplateGroupNeedsExercises =>
      'Add at least two ungrouped exercises first.';

  @override
  String get workoutTemplateCreateGroup => 'Create Group';

  @override
  String get workoutTemplateEditGroup => 'Edit Group';

  @override
  String get workoutTemplateGroupName => 'Group name';

  @override
  String get workoutTemplateGroupColor => 'Group color';

  @override
  String workoutTemplateGroupColorPreview(String color) {
    return 'Group color preview $color';
  }

  @override
  String get workoutTemplateGroupRounds => 'Rounds';

  @override
  String get workoutTemplateGroupRoundsHelp =>
      'A round is one pass through every exercise in this Group.';

  @override
  String get workoutTemplateGroupMembers => 'Exercises';

  @override
  String get workoutTemplateSelectedGroupMembers => 'Selected exercises';

  @override
  String get workoutTemplateAvailableGroupMembers => 'Available exercises';

  @override
  String get workoutTemplateNoSelectedGroupMembers =>
      'Select at least two exercises below.';

  @override
  String workoutTemplateReorderGroupMember(String name) {
    return 'Reorder $name';
  }

  @override
  String workoutTemplateGroupMemberActions(String name) {
    return 'Group member actions for $name';
  }

  @override
  String get workoutTemplateRemoveGroupMember => 'Remove from Group';

  @override
  String workoutTemplateGroupInOtherGroup(String name) {
    return 'In $name';
  }

  @override
  String get workoutTemplateGroupNameRequired => 'Enter a Group name.';

  @override
  String get workoutTemplateGroupColorInvalid => 'Enter a color as #RRGGBB.';

  @override
  String get workoutTemplateGroupRoundsInvalid =>
      'Rounds must be a whole number of at least 1.';

  @override
  String get workoutTemplateGroupMembersInvalid =>
      'Select at least two exercises.';

  @override
  String get workoutTemplateSaveGroup => 'Save Group';

  @override
  String get workoutTemplateGroupActionFailed =>
      'The Group could not be updated.';

  @override
  String workoutTemplateGroupRoundsCount(int rounds) {
    String _temp0 = intl.Intl.pluralLogic(
      rounds,
      locale: localeName,
      other: '$rounds rounds',
      one: '1 round',
    );
    return '$_temp0';
  }

  @override
  String workoutTemplateGroupMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
    );
    return '$_temp0';
  }

  @override
  String workoutTemplateGroupMembership(String name, int rounds) {
    String _temp0 = intl.Intl.pluralLogic(
      rounds,
      locale: localeName,
      other: '$rounds rounds',
      one: '1 round',
    );
    return '$name · $_temp0';
  }

  @override
  String workoutTemplateGroupColorIndicator(String name) {
    return 'Group color for $name';
  }

  @override
  String workoutTemplateReorderGroup(String name) {
    return 'Reorder Group $name';
  }

  @override
  String workoutTemplateGroupActions(String name) {
    return 'Group actions for $name';
  }

  @override
  String get workoutTemplateMoveGroupEarlier => 'Move earlier';

  @override
  String get workoutTemplateMoveGroupLater => 'Move later';

  @override
  String get workoutTemplateDissolveGroup => 'Dissolve Group';

  @override
  String workoutTemplateDissolveGroupTitle(String name) {
    return 'Dissolve $name?';
  }

  @override
  String get workoutTemplateDissolveGroupMessage =>
      'Exercises and Prescriptions stay in this saved workout.';

  @override
  String get workoutTemplateDissolveGroupSuccess => 'Group dissolved';

  @override
  String workoutTemplateGroupedExerciseRemoveTitle(String name) {
    return 'Remove from $name first';
  }

  @override
  String get workoutTemplateGroupedExerciseRemoveMessage =>
      'Edit or dissolve the Group before removing this exercise.';

  @override
  String get routinePlansTitle => 'Routines';

  @override
  String get routinePlansNew => 'New Routine';

  @override
  String get routinePlansCreateTitle => 'Create Routine';

  @override
  String get routinePlansCreate => 'Create Routine';

  @override
  String get routinePlansNameLabel => 'Routine name';

  @override
  String get routinePlansNotesLabel => 'Notes';

  @override
  String get routinePlansNameRequired => 'Enter a Routine name.';

  @override
  String get routinePlansUnavailable => 'Routines unavailable';

  @override
  String get routinePlansActionFailed => 'The Routine could not be updated.';

  @override
  String get routinePlansEmptyTitle => 'No Routines yet';

  @override
  String get routinePlansEmptyMessage =>
      'Create a Routine to keep the workouts of one plan together.';

  @override
  String get routinePlansActiveHeading => 'ACTIVE';

  @override
  String get routinePlansShowArchived => 'Show archived Routines';

  @override
  String get routinePlansHideArchived => 'Hide archived Routines';

  @override
  String get routinePlansArchivedHeading => 'ARCHIVED';

  @override
  String get routinePlansArchivedEmpty => 'No archived Routines';

  @override
  String routinePlansTemplateCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count workouts',
      one: '1 workout',
    );
    return '$_temp0';
  }

  @override
  String routinePlansArchivedTemplateCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archived',
      one: '1 archived',
    );
    return '$_temp0';
  }

  @override
  String routinePlansOpenTooltip(String name) {
    return 'Open Routine $name';
  }

  @override
  String routinePlansArchivedTileLabel(String name) {
    return 'Archived Routine $name';
  }

  @override
  String get routinePlansArchive => 'Archive Routine';

  @override
  String get routinePlansRestore => 'Restore Routine';

  @override
  String get routinePlansCancel => 'Cancel';

  @override
  String routinePlansArchiveTitle(String name) {
    return 'Archive $name?';
  }

  @override
  String get routinePlansArchiveMessage =>
      'Its saved workouts remain unchanged, and the Routine can be restored.';

  @override
  String get routinePlansSaveDetails => 'Save Routine';

  @override
  String get routinePlansTemplatesHeading => 'Workouts';

  @override
  String get routinePlansAddTemplate => 'Add workout';

  @override
  String get routinePlansNoTemplates => 'No workouts in this Routine yet.';

  @override
  String get routinePlansTemplateLabel => 'Workout';

  @override
  String get routinePlansArchivedTemplateLabel => 'Archived workout';

  @override
  String get routinePlansRestoreTemplate => 'Restore workout';

  @override
  String routinePlansReorderTemplate(String name) {
    return 'Reorder $name';
  }

  @override
  String routinePlansEntryActions(String name) {
    return 'Routine entry actions for $name';
  }

  @override
  String get routinePlansMoveEarlier => 'Move earlier';

  @override
  String get routinePlansMoveLater => 'Move later';

  @override
  String get routinePlansRemoveReference => 'Remove from Routine';

  @override
  String routinePlansRemoveReferenceTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String routinePlansRemoveReferenceMessage(String name) {
    return 'This removes it only from $name. The saved workout remains available everywhere else.';
  }

  @override
  String get routinePlansTemplatePickerTitle => 'Add workout';

  @override
  String get routinePlansNoAvailableTemplates =>
      'Create a saved workout in Library before adding one to this Routine.';

  @override
  String get routinePlansCadenceHeading => 'Cadence';

  @override
  String get routinePlansCadenceLabel => 'Routine cadence';

  @override
  String get routinePlansCadenceNone => 'None';

  @override
  String get routinePlansCadenceWeekly => 'Weekly';

  @override
  String get routinePlansCadenceRotating => 'Rotating';

  @override
  String get routinePlansRotatingWindowLabel => 'Number of positions';

  @override
  String get routinePlansRotatingWindowHelp =>
      'Each position can hold more than one workout.';

  @override
  String get routinePlansRotatingWindowError =>
      'Enter a whole number of 1 or more.';

  @override
  String get routinePlansCadenceInvalid => 'Choose a valid Cadence.';

  @override
  String get routinePlansSaveCadence => 'Save Cadence';

  @override
  String get routinePlansCadenceWarningTitle => 'Save a long rotation?';

  @override
  String get routinePlansCadenceWarningMessage =>
      'A rotating Cadence above 31 positions is unusual. You can still save it.';

  @override
  String get routinePlansSaveAnyway => 'Save anyway';

  @override
  String get routinePlansMonday => 'Monday';

  @override
  String get routinePlansTuesday => 'Tuesday';

  @override
  String get routinePlansWednesday => 'Wednesday';

  @override
  String get routinePlansThursday => 'Thursday';

  @override
  String get routinePlansFriday => 'Friday';

  @override
  String get routinePlansSaturday => 'Saturday';

  @override
  String get routinePlansSunday => 'Sunday';

  @override
  String routinePlansRotatingSlot(int slot) {
    return 'Position $slot';
  }

  @override
  String routinePlansAddTemplateToSlot(String slot) {
    return 'Add workout to $slot';
  }

  @override
  String get routinePlansDropHere => 'Move here';

  @override
  String get routinePlansRest => 'Rest';

  @override
  String routinePlansRestSlotLabel(String slot) {
    return '$slot, Rest';
  }

  @override
  String get routinePlansMoveToSlot => 'Move to another slot';

  @override
  String routinePlansMoveToSlotTitle(String name) {
    return 'Move $name';
  }

  @override
  String get routinePlansCurrentSlot => 'Current slot';

  @override
  String get workoutCaptureMenuAction => 'Save for reuse';

  @override
  String get workoutCaptureTitle => 'Save workout for reuse';

  @override
  String get workoutCaptureLoading => 'Preparing capture preview';

  @override
  String get workoutCapturePreviewUnavailable =>
      'This workout could not be prepared for capture. Try again.';

  @override
  String get workoutCaptureRetry => 'Try again';

  @override
  String get workoutCaptureClose => 'Close capture sheet';

  @override
  String get workoutCapturePickerClose => 'Close picker';

  @override
  String workoutCaptureCountsSemantics(
      int exerciseCount, int setCount, int groupCount) {
    String _temp0 = intl.Intl.pluralLogic(
      exerciseCount,
      locale: localeName,
      other: '$exerciseCount exercises',
      one: '1 exercise',
      zero: 'no exercises',
    );
    String _temp1 = intl.Intl.pluralLogic(
      setCount,
      locale: localeName,
      other: '$setCount sets',
      one: '1 set',
      zero: 'no sets',
    );
    String _temp2 = intl.Intl.pluralLogic(
      groupCount,
      locale: localeName,
      other: '$groupCount groups',
      one: '1 group',
      zero: 'no groups',
    );
    return 'Capture preview: $_temp0, $_temp1, and $_temp2.';
  }

  @override
  String workoutCaptureExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count exercises',
      one: '1 exercise',
      zero: 'No exercises',
    );
    return '$_temp0';
  }

  @override
  String workoutCaptureSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets',
      one: '1 set',
      zero: 'No sets',
    );
    return '$_temp0';
  }

  @override
  String workoutCaptureGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups',
      one: '1 group',
      zero: 'No groups',
    );
    return '$_temp0';
  }

  @override
  String get workoutCaptureNameLabel => 'Workout name';

  @override
  String get workoutCaptureNameRequired => 'Enter a workout name.';

  @override
  String get workoutCaptureRoutineLabel => 'Add to Routine';

  @override
  String get workoutCaptureRoutineHelp =>
      'Optional. Collection Routines append the reference; Cadence Routines require a slot.';

  @override
  String get workoutCaptureRoutineNone => 'None';

  @override
  String get workoutCaptureRoutinesLoading => 'Loading Routines';

  @override
  String get workoutCaptureRoutinePickerTitle => 'Choose a Routine';

  @override
  String get workoutCaptureRoutineUnavailable =>
      'The selected Routine is no longer available. Choose another Routine or None.';

  @override
  String get workoutCaptureCadenceChanged =>
      'This Routine\'s Cadence changed. Review the placement and choose an available slot.';

  @override
  String workoutCaptureCadenceRoutineOption(String name) {
    return '$name - choose slot';
  }

  @override
  String workoutCaptureCollectionRoutineOption(String name) {
    return '$name - collection';
  }

  @override
  String get workoutCaptureSlotLabel => 'Cadence slot';

  @override
  String get workoutCaptureChooseSlot => 'Choose a slot';

  @override
  String get workoutCaptureSlotRequired => 'Choose a Cadence slot.';

  @override
  String get workoutCaptureSlotPickerTitle => 'Choose a Cadence slot';

  @override
  String get workoutCaptureSlotNumberLabel => 'Slot number';

  @override
  String workoutCaptureSlotRange(int count) {
    return 'Enter a number from 1 to $count or choose from the list.';
  }

  @override
  String get workoutCaptureSlotOutOfRange => 'Enter an available slot number.';

  @override
  String get workoutCaptureChooseSlotAction => 'Choose slot';

  @override
  String get workoutCaptureReferenceNote =>
      'This creates a new saved workout from what you logged. The logged workout stays unchanged; adding it to a Routine adds only a reference.';

  @override
  String get workoutCaptureErrorsTitle => 'Cannot save yet';

  @override
  String get workoutCaptureWarningsTitle => 'Review before saving';

  @override
  String get workoutCaptureAcceptWarnings =>
      'I reviewed these warnings and want to save anyway.';

  @override
  String get workoutCaptureSave => 'Save';

  @override
  String get workoutCaptureSaving => 'Saving...';

  @override
  String get workoutCaptureSaveFailed =>
      'The saved workout could not be created. Review your choices and try again.';

  @override
  String get workoutCaptureSaved => 'Saved for reuse.';

  @override
  String get workoutUpdateTemplateMenuAction => 'Update saved workout';

  @override
  String templateUpdatePromptTitle(String name) {
    return 'Update \"$name\"?';
  }

  @override
  String get templateUpdateDismissAction => 'Not now';

  @override
  String get templateUpdateConfirmAction => 'Update saved workout';

  @override
  String get templateUpdateConfirmedMessage => 'Saved workout updated.';

  @override
  String get templateUpdateNotLinkedMessage =>
      'This workout didn\'t start from a saved workout.';

  @override
  String get templateUpdateGroupsChangedNote => 'Exercise groups changed';

  @override
  String get templateUpdateNoChangesNote => 'No changes to update';

  @override
  String get templateStartNoExercises => 'No exercises';

  @override
  String templateStartEmptyTitle(String name) {
    return '\"$name\" has no exercises';
  }

  @override
  String get templateStartEmptyMessage =>
      'Starting it opens an empty workout. Add exercises to it to have them load when you start it.';

  @override
  String get templateStartEmptyConfirmAction => 'Start empty workout';

  @override
  String get workoutTemplateNotesTitle => 'Plan notes';

  @override
  String workoutTemplateNotesSource(String name) {
    return 'From $name';
  }

  @override
  String get workoutTemplateNotesShowMore => 'Show more';

  @override
  String get workoutTemplateNotesShowLess => 'Show less';

  @override
  String get activityBackupRestoreActor => 'Backup restore';

  @override
  String get backupRestoreSectionTitle => 'Restore';

  @override
  String get backupRestoreDescription =>
      'Bring in workouts, food, and body readings from a Perennia backup file. Restoring only adds and updates; nothing on this device is erased.';

  @override
  String get backupRestoreButton => 'Restore from backup';

  @override
  String get backupRestoreReadingProgress => 'Reading backup…';

  @override
  String get backupRestoreRestoringProgress => 'Restoring…';

  @override
  String get backupRestorePassphraseTitle => 'Encrypted backup';

  @override
  String get backupRestorePassphraseMessage =>
      'Enter the passphrase this backup was made with.';

  @override
  String get backupRestorePassphraseLabel => 'Backup passphrase';

  @override
  String get backupRestorePassphraseRejected =>
      'That passphrase didn\'t unlock this backup.';

  @override
  String get backupRestoreUnlockAction => 'Unlock';

  @override
  String get backupRestoreCancelAction => 'Cancel';

  @override
  String get backupRestoreConfirmTitle => 'Restore this backup?';

  @override
  String backupRestoreCreatedAt(String date) {
    return 'Made $date';
  }

  @override
  String backupRestoreWorkoutCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count workouts',
      one: '1 workout',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreSetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets',
      one: '1 set',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreFoodEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count food entries',
      one: '1 food entry',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreMetricReadingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count metric readings',
      one: '1 metric reading',
    );
    return '$_temp0';
  }

  @override
  String get backupRestoreMergeExplanation =>
      'Restoring adds anything this device is missing. Nothing here is erased: when the backup and this device both have the same item, the more recently edited one is kept. You can undo the restore from Recent activity.';

  @override
  String get backupRestoreConfirmAction => 'Restore';

  @override
  String get backupRestoreDoneTitle => 'Backup restored';

  @override
  String backupRestoreChangedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items added or updated.',
      one: '1 item added or updated.',
      zero: 'Nothing new: this device already had everything in the backup.',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreUnchangedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items were already up to date.',
      one: '1 item was already up to date.',
    );
    return '$_temp0';
  }

  @override
  String get backupRestoreDoneAction => 'Done';

  @override
  String get backupRestoreFailedTitle => 'Couldn\'t restore this backup';

  @override
  String get backupRestoreUnreadableMessage =>
      'This file isn\'t a Perennia backup, or it\'s damaged. Nothing on this device was changed.';

  @override
  String get backupRestoreNewerVersionMessage =>
      'This backup was made by a newer version of Perennia. Update the app, then try again. Nothing on this device was changed.';

  @override
  String get backupSettingsTitle => 'Backup & restore';

  @override
  String get backupSettingsHubSubtitle => 'Back up to a file or restore one';

  @override
  String get backupNowSectionTitle => 'Back up';

  @override
  String get backupNowDescription =>
      'Save your workouts, food, and body readings to a backup file. Keep it somewhere off this phone, like a cloud drive, so you can restore it on a new one.';

  @override
  String get backupNowButton => 'Back up now';

  @override
  String get backupNowProgress => 'Backing up…';

  @override
  String get backupNowSavedMessage => 'Backup saved.';

  @override
  String get backupNowFailedTitle => 'Couldn\'t save the backup';

  @override
  String get backupNowFailedMessage =>
      'The backup file couldn\'t be written there. Try again, or choose another place.';

  @override
  String get backupNowUnsupportedMessage =>
      'This device can\'t save a backup file.';

  @override
  String get backupPassphraseLabel => 'Backup passphrase';

  @override
  String get backupPassphraseHelper =>
      'Optional. When set, backups are encrypted, and restoring one asks for this passphrase. Without it the backup can\'t be opened.';

  @override
  String get autoBackupSwitchTitle => 'Auto-backup';

  @override
  String get autoBackupChooseFolderButton => 'Choose backup folder';

  @override
  String get autoBackupFolderWarningLabel => 'Auto-backup folder warning';

  @override
  String get autoBackupGrantPrompt =>
      'Choose a backup folder again to resume auto-backup.';

  @override
  String get startWorkoutSheetTitle => 'Start a workout';

  @override
  String get startWorkoutFocusSection => 'Focus';

  @override
  String get startWorkoutEditFocusesTooltip => 'Edit focuses';

  @override
  String get startWorkoutEmpty => 'Empty workout';

  @override
  String get startWorkoutEmptySubtitle => 'Start without a focus';

  @override
  String startWorkoutFocusTileLabel(String focus) {
    return 'Start a workout: $focus';
  }

  @override
  String get workoutNoFocus => 'No focus';

  @override
  String workoutFocusSemanticLabel(String focus) {
    return 'Focus: $focus. Change focus';
  }

  @override
  String get workoutChooseFocus => 'Choose a focus';

  @override
  String workoutFocusChanged(String focus) {
    return 'Focus set to $focus';
  }

  @override
  String get workoutFocusCleared => 'Focus removed';

  @override
  String get focusPickerTitle => 'Focus';

  @override
  String get focusPickerNone => 'No focus';

  @override
  String get focusPickerEdit => 'Edit focuses';

  @override
  String focusArchivedName(String focus) {
    return '$focus (archived)';
  }

  @override
  String focusLibraryYourExercises(String focus) {
    return 'Recent under $focus';
  }

  @override
  String focusLibraryCatalog(String focus) {
    return 'More $focus exercises';
  }

  @override
  String focusLibraryBrowseAll(String focus) {
    return 'Browse all $focus exercises';
  }

  @override
  String get focusLibrarySearchAll => 'Search all exercises';

  @override
  String focusLibraryAddExerciseTooltip(String exercise) {
    return 'Add $exercise';
  }

  @override
  String get focusUseToday => 'Today';

  @override
  String get focusUseYesterday => 'Yesterday';

  @override
  String focusUseWorkoutCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count workouts',
      one: '1 workout',
    );
    return '$_temp0';
  }

  @override
  String focusUseSubtitle(String when, String count) {
    return '$when · $count';
  }

  @override
  String get exerciseCatalogFocusAll => 'All';

  @override
  String get exerciseCatalogFocusFilterLabel => 'Focus';

  @override
  String exerciseCatalogInFocus(String focus) {
    return 'In $focus';
  }

  @override
  String get exerciseCatalogOtherExercises => 'Other exercises';

  @override
  String get focusManagerTitle => 'Focuses';

  @override
  String get focusManagerLibrarySubtitle =>
      'What you train, for starting a workout';

  @override
  String get focusManagerAdd => 'Add focus';

  @override
  String get focusManagerNameLabel => 'Name';

  @override
  String get focusManagerRename => 'Rename';

  @override
  String get focusManagerArchive => 'Archive';

  @override
  String get focusManagerSave => 'Save';

  @override
  String get focusManagerReorderHint => 'Press and hold to reorder.';

  @override
  String focusManagerArchiveTitle(String focus) {
    return 'Archive $focus?';
  }

  @override
  String get focusColorMenu => 'Color';

  @override
  String focusColorDialogTitle(String name) {
    return 'Color for $name';
  }

  @override
  String get focusColorBack => 'Back';

  @override
  String get focusColorCardio => 'Cardio';

  @override
  String get focusColorCore => 'Core';

  @override
  String get focusColorShoulders => 'Shoulders';

  @override
  String get focusColorArms => 'Arms';

  @override
  String get focusColorLegs => 'Legs';

  @override
  String get focusColorChest => 'Chest';

  @override
  String get focusManagerArchiveBody =>
      'Workouts already logged under it keep it. It stops being offered when you start a workout.';

  @override
  String get focusManagerDuplicateName =>
      'A focus with that name already exists.';

  @override
  String get focusManagerEmptyName => 'Enter a name.';

  @override
  String get focusManagerEmpty =>
      'No focuses. Add one to start workouts from it.';

  @override
  String get exerciseEditorFocusesLabel => 'Focuses';

  @override
  String get exerciseEditorFocusesHelp =>
      'Offered first when you start a workout under one of these.';

  @override
  String get workoutTemplateFocusLabel => 'Focus';

  @override
  String homeSessionHeaderWithFocus(String focus, String time) {
    return '$focus · $time';
  }

  @override
  String get focusLibraryHeading => 'Add your first exercise';

  @override
  String focusLibraryStaples(String focus) {
    return '$focus staples';
  }

  @override
  String get focusManagerSaveFailed => 'Could not save the focus. Try again.';

  @override
  String get protocolEditorNewTitle => 'New Protocol';

  @override
  String get protocolEditorEditTitle => 'Edit Protocol';

  @override
  String get protocolEditorNameLabel => 'Name';

  @override
  String get protocolEditorStartDateLabel => 'Start date';

  @override
  String get protocolEditorPeriodHeading => 'Period';

  @override
  String get protocolEditorUntilLabel => 'Until an end date';

  @override
  String get protocolEditorOngoing => 'Ongoing, with no end date';

  @override
  String get protocolEditorEndDateLabel => 'End date';

  @override
  String get protocolEditorDoseCountButton =>
      'Set the end date from a number of doses';

  @override
  String get protocolEditorDoseCountTitle => 'End after a number of doses';

  @override
  String get protocolEditorDoseCountMemberLabel => 'Count the doses of';

  @override
  String get protocolEditorDoseCountLabel => 'Number of doses';

  @override
  String protocolEditorDoseCountResult(String date) {
    return 'Ends $date';
  }

  @override
  String get protocolEditorDoseCountUnavailable =>
      'Unavailable for this Schedule';

  @override
  String protocolEditorDoseCountRange(int min, int max) {
    return 'Enter a number from $min to $max';
  }

  @override
  String get protocolEditorDoseCountApply => 'Set end date';

  @override
  String get protocolEditorCancel => 'Cancel';

  @override
  String get protocolEditorCycleLabel => 'Cycle';

  @override
  String get protocolEditorCycleSubtitle => 'Days on, then days off, repeating';

  @override
  String get protocolEditorCycleOnDaysLabel => 'Days on';

  @override
  String get protocolEditorCycleOffDaysLabel => 'Days off';

  @override
  String get protocolEditorCycleAnchorLabel => 'Cycle counted from';

  @override
  String protocolEditorAnchorIsStart(String date) {
    return '$date (the start date)';
  }

  @override
  String get protocolEditorPausesHeading => 'Pauses';

  @override
  String get protocolEditorPausesEmpty => 'No Pauses';

  @override
  String get protocolEditorAddPause => 'Add a Pause';

  @override
  String get protocolEditorRemovePause => 'Remove Pause';

  @override
  String protocolEditorDateRange(String from, String to) {
    return '$from – $to';
  }

  @override
  String get protocolEditorCompoundsHeading => 'Compounds';

  @override
  String get protocolEditorSchedulesHeading => 'Schedules';

  @override
  String protocolEditorScheduleTitle(String compound) {
    return '$compound Schedule';
  }

  @override
  String protocolEditorScheduleCurrentVersion(String date) {
    return 'Current Schedule applies from $date';
  }

  @override
  String get protocolEditorRuleTimed => 'At set times';

  @override
  String get protocolEditorRuleUntimed => 'Any time';

  @override
  String get protocolEditorRuleAsNeeded => 'As needed';

  @override
  String get protocolEditorRuleNone => 'No schedule';

  @override
  String get protocolEditorDaysDaily => 'Every day';

  @override
  String get protocolEditorDaysWeekdays => 'Weekdays';

  @override
  String get protocolEditorDaysEveryN => 'Every N days';

  @override
  String get protocolEditorEveryNLabel => 'Every how many days';

  @override
  String get protocolEditorEveryNAnchorLabel => 'Counted from';

  @override
  String get protocolEditorTimesHeading => 'Times';

  @override
  String get protocolEditorAddTime => 'Add a time';

  @override
  String protocolEditorRemoveTime(String time) {
    return 'Remove $time';
  }

  @override
  String get protocolEditorUntimedCountLabel => 'Doses a day';

  @override
  String get protocolEditorPlannedAmountLabel => 'Planned amount';

  @override
  String get protocolEditorUnitLabel => 'Unit';

  @override
  String get protocolEditorRouteLabel => 'Route';

  @override
  String get protocolEditorTargetOutcomesHeading =>
      'Target outcomes (optional)';

  @override
  String get protocolEditorTargetOutcomesHelp =>
      'Which Metrics or performance to correlate — seeds the later Effect view; no analysis happens here.';

  @override
  String get protocolEditorPerformance => 'Performance';

  @override
  String get protocolEditorSave => 'Save';

  @override
  String get protocolEditorArchive => 'Archive';

  @override
  String get protocolEditorNameRequired => 'Name is required.';

  @override
  String get protocolEditorCompoundRequired =>
      'A Protocol requires at least one Compound.';

  @override
  String get protocolEditorFixIssues => 'Fix the marked fields to save.';

  @override
  String protocolEditorSaveFailed(String error) {
    return 'Could not save the Protocol: $error';
  }

  @override
  String get protocolEditorCompoundFallback => 'Compound';

  @override
  String get protocolPlanIssueTimesFormat =>
      'Each time must be HH:MM, from 00:00 to 23:59.';

  @override
  String protocolPlanIssueTimesCount(int max) {
    return 'Plan 1 to $max times a day.';
  }

  @override
  String get protocolPlanIssueTimesDistinct =>
      'The same time is planned twice.';

  @override
  String protocolPlanIssueUntimedCount(int max) {
    return 'Plan 1 to $max doses a day.';
  }

  @override
  String get protocolPlanIssueWeekdaysValid => 'Choose at least one weekday.';

  @override
  String protocolPlanIssueEveryNRange(int min, int max) {
    return 'Every N days takes a number from $min to $max.';
  }

  @override
  String get protocolPlanIssueAnchorDate => 'Choose a real date to count from.';

  @override
  String get protocolPlanIssueAmountRequired =>
      'Enter a planned amount, unit and route that a Dose could log.';

  @override
  String get protocolPlanIssueAmountAbsent =>
      'As needed and No schedule carry no amount, unit or route.';

  @override
  String protocolPlanIssueCycleLengths(int max) {
    return 'A cycle is 1 to $max days on and 1 to $max days off.';
  }

  @override
  String get protocolPlanIssueBoundsOrder =>
      'The end date can\'t be before the start date.';

  @override
  String protocolPlanIssuePauseCount(int max) {
    return 'A Protocol holds at most $max Pauses.';
  }

  @override
  String get protocolPlanIssuePauseOrder =>
      'A Pause can\'t end before it starts.';

  @override
  String get protocolPlanIssuePauseBounds =>
      'Each Pause must fall within the Protocol\'s dates.';

  @override
  String get protocolPlanIssuePauseOverlap => 'Two Pauses can\'t overlap.';

  @override
  String protocolPlanIssueTimesMany(int count) {
    return 'More than $count times a day is unusual. Check the times before saving.';
  }

  @override
  String get effectPlanBreaksCountedAsDuring =>
      'Off-cycle and paused days are counted as during.';

  @override
  String get plannedListRowLogged => 'Logged';

  @override
  String get plannedListRowPending => 'Pending';

  @override
  String get plannedListRowNotLogged => 'Not logged';

  @override
  String get plannedListAnyTime => 'Any time';

  @override
  String get plannedListLogAll => 'Log all planned';

  @override
  String get logDoseDateLabel => 'Date';

  @override
  String get dayStatusNotPlanned => 'Not planned';

  @override
  String get dayStatusPaused => 'Paused';

  @override
  String get dayStatusOffCycle => 'Off cycle';

  @override
  String get dayStatusPending => 'Pending';

  @override
  String get dayStatusLogged => 'Logged';

  @override
  String get dayStatusPartlyLogged => 'Partly logged';

  @override
  String get dayStatusNotLogged => 'Not logged';

  @override
  String get notPlannedReasonNotScheduledToday => 'Not scheduled that day';

  @override
  String get notPlannedReasonAsNeeded => 'As needed';

  @override
  String get notPlannedReasonNoSchedule => 'No schedule';

  @override
  String get notPlannedReasonRemoved => 'Removed';

  @override
  String get notPlannedReasonOutside => 'Outside the Protocol\'s dates';

  @override
  String get consistencyButton => 'Consistency';

  @override
  String consistencyScreenTitle(String name) {
    return 'Consistency · $name';
  }

  @override
  String consistencyRangeDays(int count) {
    return '$count days';
  }

  @override
  String get consistencyRangeCustom => 'Custom';

  @override
  String get consistencyPlanned => 'Planned';

  @override
  String get consistencyExtra => 'Extra';

  @override
  String consistencyExtraCount(int count) {
    return '$count extra';
  }

  @override
  String get consistencyNotInProtocol =>
      'Not in a Protocol, so its days have no Day Status. Its Doses are listed by date.';

  @override
  String get consistencyNoDoses => 'No Doses logged in this range.';

  @override
  String get consistencyLoadError => 'Could not load this range.';

  @override
  String get consistencyChartEmpty =>
      'Nothing planned or logged in this range.';

  @override
  String get consistencyChartLoggedLegend => 'Logged Dose';

  @override
  String get consistencyChartExtraLegend => 'Extra Dose';

  @override
  String get consistencyChartPlannedLegend => 'Planned time';

  @override
  String consistencyChartSemantics(String from, String to) {
    return 'Dose times against planned times, $from – $to';
  }

  @override
  String get protocolReminderTitle => 'Protocols';

  @override
  String protocolReminderBody(String time) {
    return 'Planned for $time';
  }

  @override
  String get protocolReminderChannelName => 'Reminders';

  @override
  String get protocolRemindersSwitchLabel => 'Reminders';

  @override
  String get protocolRemindersSwitchSubtitle =>
      'A notification at each planned time';

  @override
  String get protocolRemindersPermissionDenied =>
      'Notifications are off for Perennia';

  @override
  String get protocolRemindersOpenSettings => 'Open settings';

  @override
  String protocolRemindersScheduledThrough(String date) {
    return 'Reminders scheduled through $date';
  }

  @override
  String get protocolRemindersBanner => 'Reminders are off on this device';

  @override
  String get protocolRemindersAllow => 'Allow';

  @override
  String get protocolRemindersSettingsTile => 'Protocol reminders';

  @override
  String get protocolRemindersSettingsTileSubtitle =>
      'Reminders on this device and notification permission';

  @override
  String get protocolRemindersSettingsTitle => 'Protocol reminders';

  @override
  String get protocolRemindersDeviceSwitch => 'Reminders on this device';

  @override
  String get protocolRemindersDeviceSwitchSubtitle =>
      'Applies to this device only';

  @override
  String get protocolRemindersPermissionLabel => 'Notifications';

  @override
  String get protocolRemindersPermissionGranted => 'Allowed';

  @override
  String get protocolRemindersPermissionNotDetermined => 'Not asked yet';

  @override
  String get protocolRemindersPermissionUnsupported =>
      'Not available on this device';

  @override
  String get progressPeriodWeeks4 => '4 wk';

  @override
  String get progressPeriodWeeks12 => '12 wk';

  @override
  String get progressPeriodYear => '1 yr';

  @override
  String get progressRoutinesAction => 'Routines';

  @override
  String get progressCardUnavailable => 'Unavailable right now';

  @override
  String get progressFocusesAction => 'Focuses';

  @override
  String get progressThisWeekTitle => 'This week';

  @override
  String get progressThisWeekEmpty => 'Plan your week with a Routine';

  @override
  String get progressThisWeekNothingLogged => 'Nothing logged yet this week';

  @override
  String progressThisWeekComparing(String names) {
    return 'Comparing $names';
  }

  @override
  String progressThisWeekComparingWeeklyOnly(String names) {
    return 'Comparing $names. Weekly Routines only.';
  }

  @override
  String get progressThisWeekWeeklyOnly => 'Weekly Routines only.';

  @override
  String progressThisWeekSemantics(String days) {
    return 'This week: $days.';
  }

  @override
  String progressThisWeekDaySemantics(String weekday, String status) {
    return '$weekday $status';
  }

  @override
  String get progressStatusDone => 'Done';

  @override
  String get progressStatusPartlyDone => 'Partly done';

  @override
  String get progressStatusDoneDifferently => 'Done differently';

  @override
  String get progressStatusNotDone => 'Not done';

  @override
  String get progressStatusPending => 'Pending';

  @override
  String get progressStatusPlanned => 'Planned';

  @override
  String get progressStatusTrained => 'Trained';

  @override
  String get progressStatusRest => 'Rest';

  @override
  String get progressStatusNoPlan => 'No plan';

  @override
  String progressStatusSpoken(String status) {
    String _temp0 = intl.Intl.selectLogic(
      status,
      {
        'done': 'done',
        'partly_done': 'partly done',
        'done_differently': 'done differently',
        'not_done': 'not done',
        'pending': 'pending',
        'planned': 'planned',
        'trained': 'trained',
        'rest': 'rest',
        'no_plan': 'no plan',
        'other': '',
      },
    );
    return '$_temp0';
  }

  @override
  String progressCountDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count done',
    );
    return '$_temp0';
  }

  @override
  String progressCountPartlyDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count partly done',
    );
    return '$_temp0';
  }

  @override
  String progressCountDoneDifferently(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count done differently',
    );
    return '$_temp0';
  }

  @override
  String progressCountNotDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count not done',
    );
    return '$_temp0';
  }

  @override
  String progressCountTrained(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trained',
    );
    return '$_temp0';
  }

  @override
  String get progressTrainedDaysTitle => 'Trained days';

  @override
  String progressTrainedDaysCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trained days',
      one: '1 trained day',
    );
    return '$_temp0';
  }

  @override
  String progressTrainedDaysSemantics(int count, int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trained days in the last $weeks weeks.',
      one: '1 trained day in the last $weeks weeks.',
    );
    return '$_temp0';
  }

  @override
  String get progressTrainedDaysEmpty => 'Logged workouts show here';

  @override
  String get progressFocusTimeTitle => 'Time by Focus';

  @override
  String get progressFocusTimeEmpty => 'Finished workouts show here';

  @override
  String get progressFocusTimeNoFocus => 'No Focus';

  @override
  String get progressFocusTimeUnknownFocus => 'Focus';

  @override
  String progressFocusTimeAxisHours(int hours) {
    return '${hours}h';
  }

  @override
  String progressFocusTimeEntry(String name, String duration) {
    return '$name $duration';
  }

  @override
  String progressFocusTimeSemantics(String entries) {
    return 'Time by Focus, this week: $entries';
  }

  @override
  String progressHoursSpoken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String progressMinutesSpoken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String progressHoursMinutesSpoken(String hours, String minutes) {
    return '$hours $minutes';
  }

  @override
  String get progressProtocolsTitle => 'Protocols';

  @override
  String get progressProtocolsUnlock => 'Unlock';

  @override
  String get progressProtocolsAll => 'All protocols';

  @override
  String get progressProtocolsEmpty => 'No protocol days in this period';

  @override
  String progressCountLogged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count logged',
    );
    return '$_temp0';
  }

  @override
  String progressCountPartlyLogged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count partly logged',
    );
    return '$_temp0';
  }

  @override
  String progressCountNotLogged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count not logged',
    );
    return '$_temp0';
  }

  @override
  String progressCountPaused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paused',
    );
    return '$_temp0';
  }

  @override
  String get progressKeyExercisesTitle => 'Key exercises';

  @override
  String get progressKeyExercisesEmpty =>
      'Mark exercises as favorites to chart them here';

  @override
  String get progressKeyExercisesNoCharted =>
      'Your favorites have no charted records';

  @override
  String get progressKeyExercisesNoSessions => 'No sessions this period';

  @override
  String get progressMeasureEstimatedOneRepMax => 'e1RM';

  @override
  String get progressMeasureMaxLoad => 'heaviest';

  @override
  String get progressMeasureMaxReps => 'most reps';

  @override
  String get progressMeasureMaxDuration => 'longest';

  @override
  String get progressMeasureMinDuration => 'shortest';

  @override
  String get progressMeasureMaxDistance => 'farthest';

  @override
  String get progressMeasureFastestPace => 'fastest pace';

  @override
  String progressBest(String value) {
    return 'Best $value';
  }

  @override
  String progressComparisonHigher(String difference) {
    return '↑ $difference on before';
  }

  @override
  String progressComparisonFaster(String difference) {
    return '$difference faster than before';
  }

  @override
  String progressComparisonShorter(String difference) {
    return '$difference shorter than before';
  }

  @override
  String get progressComparisonSame => 'Same as before';

  @override
  String progressComparisonBestBefore(String value) {
    return 'Best before $value';
  }

  @override
  String get progressComparisonFirst => 'First sessions';

  @override
  String progressNewBestOn(String date) {
    return 'New best on $date';
  }

  @override
  String get progressNewBestsTitle => 'New bests';

  @override
  String progressNewBestsTitleCount(int count) {
    return 'New bests · $count';
  }

  @override
  String get progressNewBestsEmpty => 'No new bests in this period';

  @override
  String progressNewBestRow(String exercise, String value) {
    return '$exercise · $value';
  }

  @override
  String progressNewBestEstimated(String value) {
    return 'e1RM $value';
  }

  @override
  String progressValueKilograms(String value) {
    return '$value kg';
  }

  @override
  String progressValuePounds(String value) {
    return '$value lb';
  }

  @override
  String progressValueReps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reps',
      one: '1 rep',
    );
    return '$_temp0';
  }

  @override
  String progressValueKilometers(String value) {
    return '$value km';
  }

  @override
  String progressValueMiles(String value) {
    return '$value mi';
  }

  @override
  String progressValuePacePerKilometer(String pace) {
    return '$pace /km';
  }

  @override
  String progressValuePacePerMile(String pace) {
    return '$pace /mi';
  }

  @override
  String progressValueSeconds(int seconds) {
    return '$seconds s';
  }
}
