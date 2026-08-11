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
  String get homeLibrarySupplementsSection => 'SUPPLEMENTS';

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
  String get homeManageRoutines => 'Manage routines';

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
  String get homeLogSupplement => 'Supplement';

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
  String get homeStartNewWorkout => 'Start New Workout';

  @override
  String get homeLoadRoutine => 'Load Routine';

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
  String get templatePickerTitle => 'Load a Template';

  @override
  String get templatePickerTodayUpNextHeading => 'Today / Up next';

  @override
  String get templatePickerRoutinesHeading => 'Routines';

  @override
  String get templatePickerAllTemplatesHeading => 'All Templates';

  @override
  String get templatePickerSearchHint => 'Search templates';

  @override
  String get templatePickerEmptyTitle => 'No plans yet';

  @override
  String get templatePickerEmptyMessage =>
      'Finish a workout, then save it as a template.';

  @override
  String get templatePickerNoSearchResults => 'No templates match your search.';

  @override
  String templatePickerCustomizeTooltip(String templateName) {
    return 'Customize $templateName';
  }

  @override
  String get templatePickerPreviewStart => 'Start workout';

  @override
  String get templatePickerPreviewExercisesHeading => 'Exercises';

  @override
  String get templatePickerPreviewEmptyExercises =>
      'No exercises in this template yet.';

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
  String get navSettings => 'Settings';

  @override
  String get navBodyTracker => 'Body Tracker';

  @override
  String get navMetrics => 'Metrics';

  @override
  String get navSupplements => 'Supplements';

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
  String get workoutTemplatesTitle => 'Workout Templates';

  @override
  String get workoutTemplatesLibrarySubtitle =>
      'Reusable plans for one Workout';

  @override
  String get workoutTemplatesNew => 'New Workout Template';

  @override
  String get workoutTemplatesCreateTitle => 'Create Workout Template';

  @override
  String get workoutTemplatesCreate => 'Create Workout Template';

  @override
  String get workoutTemplatesNameLabel => 'Workout Template name';

  @override
  String get workoutTemplatesNotesLabel => 'Standing notes';

  @override
  String get workoutTemplatesCancel => 'Cancel';

  @override
  String get workoutTemplatesActiveHeading => 'Active Workout Templates';

  @override
  String get workoutTemplatesArchivedHeading => 'Archived Workout Templates';

  @override
  String get workoutTemplatesShowArchived => 'Show archived Workout Templates';

  @override
  String get workoutTemplatesHideArchived => 'Hide archived Workout Templates';

  @override
  String get workoutTemplatesEmptyTitle => 'No Workout Templates yet';

  @override
  String get workoutTemplatesEmptyMessage =>
      'Create a reusable plan for one Workout.';

  @override
  String get workoutTemplatesArchivedEmpty => 'No archived Workout Templates.';

  @override
  String workoutTemplatesExerciseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Template Exercises',
      one: '1 Template Exercise',
      zero: 'No Template Exercises',
    );
    return '$_temp0';
  }

  @override
  String workoutTemplatesOpenTooltip(String name) {
    return 'Open $name';
  }

  @override
  String get workoutTemplatesArchive => 'Archive Workout Template';

  @override
  String get workoutTemplatesArchiveTitle => 'Archive Workout Template?';

  @override
  String get workoutTemplatesArchiveMessage =>
      'This hides the template from active lists and pickers. Logged Workouts remain unchanged.';

  @override
  String get workoutTemplatesRestore => 'Restore Workout Template';

  @override
  String get workoutTemplatesActionFailed =>
      'The Workout Template could not be updated.';

  @override
  String workoutTemplatesStartTooltip(String name) {
    return 'Start $name';
  }

  @override
  String get workoutTemplatesStartFailed => 'The Workout could not be started.';

  @override
  String get workoutTemplateEditorTitle => 'Edit Workout Template';

  @override
  String get workoutTemplateSaveDetails => 'Save Workout Template details';

  @override
  String get workoutTemplateDetailsSaved => 'Workout Template details saved';

  @override
  String get workoutTemplateExercisesHeading => 'Template Exercises';

  @override
  String get workoutTemplateAddExercise => 'Add Template Exercise';

  @override
  String get workoutTemplateNoExercises =>
      'No Template Exercises. Add one to build the plan.';

  @override
  String get workoutTemplateExerciseNotes => 'Exercise standing notes';

  @override
  String get workoutTemplateEditExerciseNotes => 'Edit exercise notes';

  @override
  String get workoutTemplateSaveExerciseNotes => 'Save exercise notes';

  @override
  String get workoutTemplateRemoveExercise => 'Remove Template Exercise';

  @override
  String get workoutTemplateRemoveExerciseTitle => 'Remove Template Exercise?';

  @override
  String get workoutTemplateRemoveExerciseMessage =>
      'Its Prescriptions are removed from this plan. Logged Workouts remain unchanged.';

  @override
  String get workoutTemplateReorderExercise => 'Reorder Template Exercise';

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
      'Use the values from the previous session when this template is loaded.';

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
  String get workoutTemplateUnavailable => 'Workout Template unavailable';

  @override
  String get workoutTemplateExercisePickerTitle => 'Add Template Exercise';

  @override
  String get workoutTemplateGroupsHeading => 'Groups';

  @override
  String get workoutTemplateAddGroup => 'Add Group';

  @override
  String get workoutTemplateNoGroups =>
      'No Groups. Add a superset or circuit to this plan.';

  @override
  String get workoutTemplateGroupNeedsExercises =>
      'Add at least two ungrouped Template Exercises first.';

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
  String get workoutTemplateGroupMembers => 'Template Exercises';

  @override
  String get workoutTemplateSelectedGroupMembers =>
      'Selected Template Exercises';

  @override
  String get workoutTemplateAvailableGroupMembers =>
      'Available Template Exercises';

  @override
  String get workoutTemplateNoSelectedGroupMembers =>
      'Select at least two Template Exercises below.';

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
      'Select at least two Template Exercises.';

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
      other: '$count Template Exercises',
      one: '1 Template Exercise',
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
      'Exercises and Prescriptions stay in this Workout Template.';

  @override
  String get workoutTemplateDissolveGroupSuccess => 'Group dissolved';

  @override
  String workoutTemplateGroupedExerciseRemoveTitle(String name) {
    return 'Remove from $name first';
  }

  @override
  String get workoutTemplateGroupedExerciseRemoveMessage =>
      'Edit or dissolve the Group before removing this Template Exercise.';

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
      'Create a Routine to keep an ordered collection of Workout Templates.';

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
      other: '$count Workout Templates',
      one: '1 Workout Template',
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
  String routinePlansStartTooltip(String name) {
    return 'Start $name';
  }

  @override
  String routinePlansStartSheetTitle(String name) {
    return 'Start $name';
  }

  @override
  String get routinePlansStartEmptyMessage =>
      'Add a Workout Template to this Routine first.';

  @override
  String get routinePlansStartFailed => 'The Workout could not be started.';

  @override
  String get routinePlansCancel => 'Cancel';

  @override
  String routinePlansArchiveTitle(String name) {
    return 'Archive $name?';
  }

  @override
  String get routinePlansArchiveMessage =>
      'Workout Templates and this Routine\'s references remain unchanged and restorable.';

  @override
  String get routinePlansSaveDetails => 'Save Routine';

  @override
  String get routinePlansTemplatesHeading => 'Workout Templates';

  @override
  String get routinePlansAddTemplate => 'Add Workout Template';

  @override
  String get routinePlansNoTemplates =>
      'No Workout Templates in this Routine yet.';

  @override
  String get routinePlansTemplateLabel => 'Workout Template';

  @override
  String get routinePlansArchivedTemplateLabel => 'Archived Workout Template';

  @override
  String get routinePlansRestoreTemplate => 'Restore Workout Template';

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
    return 'This removes only the reference from $name. The Workout Template remains available everywhere else.';
  }

  @override
  String get routinePlansTemplatePickerTitle => 'Add Workout Template';

  @override
  String get routinePlansNoAvailableTemplates =>
      'Create an active Workout Template in Library before adding one to this Routine.';

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
      'Each position can contain more than one Workout Template.';

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
    return 'Add Workout Template to $slot';
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
  String get workoutCaptureMenuAction => 'Save as Workout Template';

  @override
  String get workoutCaptureTitle => 'Save workout as template';

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
  String get workoutCaptureNameLabel => 'Workout Template name';

  @override
  String get workoutCaptureNameRequired => 'Enter a Workout Template name.';

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
      'This creates a new Workout Template from the workout facts. The workout and its existing Template Link stay unchanged; Routine placement adds only a reference.';

  @override
  String get workoutCaptureErrorsTitle => 'Cannot save yet';

  @override
  String get workoutCaptureWarningsTitle => 'Review before saving';

  @override
  String get workoutCaptureAcceptWarnings =>
      'I reviewed these warnings and want to save anyway.';

  @override
  String get workoutCaptureSave => 'Save Template';

  @override
  String get workoutCaptureSaving => 'Saving...';

  @override
  String get workoutCaptureSaveFailed =>
      'The Workout Template could not be saved. Review your choices and try again.';

  @override
  String get workoutCaptureSaved => 'Workout Template saved.';

  @override
  String get workoutUpdateTemplateMenuAction => 'Update template';

  @override
  String templateUpdatePromptTitle(String name) {
    return 'Update \"$name\"?';
  }

  @override
  String get templateUpdateDismissAction => 'Not now';

  @override
  String get templateUpdateConfirmAction => 'Update template';

  @override
  String get templateUpdateConfirmedMessage => 'Template updated.';

  @override
  String get templateUpdateNotLinkedMessage =>
      'This workout isn\'t linked to a Workout Template.';

  @override
  String get templateUpdateGroupsChangedNote => 'Exercise groups changed';

  @override
  String get templateUpdateNoChangesNote => 'No changes to update';
}
