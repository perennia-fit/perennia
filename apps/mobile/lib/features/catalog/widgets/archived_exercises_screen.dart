import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../domain/training/training_dimensions.dart';
import '../../../theme/theme.dart';

class ArchivedExercisesScreen extends ConsumerStatefulWidget {
  const ArchivedExercisesScreen({super.key});

  static const routeName = '/exercises/archived';

  static Key restoreButtonKey(String id) {
    return Key('archived-exercises-restore-$id');
  }

  @override
  ConsumerState<ArchivedExercisesScreen> createState() =>
      _ArchivedExercisesScreenState();
}

class _ArchivedExercisesScreenState
    extends ConsumerState<ArchivedExercisesScreen> {
  List<ExerciseRecord> _exercises = const <ExerciseRecord>[];
  String? _errorText;
  bool _isLoading = true;
  bool _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) {
      return;
    }
    _didLoad = true;
    _load();
  }

  Future<void> _load() async {
    final repositories = ref.read(trainingRepositoriesProvider);
    final exercises = await repositories.exercises.listArchivedUser();
    if (!mounted) {
      return;
    }

    setState(() {
      _exercises = exercises;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived exercises')),
      body: SafeArea(
        child: _isLoading
            ? const SizedBox.expand()
            : ListView(
                padding: const EdgeInsets.all(AppDimens.base),
                children: [
                  if (_errorText != null) ...[
                    Text(
                      _errorText!,
                      style: context.textStyles.body.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: AppDimens.base),
                  ],
                  if (_exercises.isEmpty)
                    Text(
                      'No archived exercises',
                      style: context.textStyles.body.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    )
                  else
                    for (final exercise in _exercises)
                      _ArchivedExerciseRow(
                        exercise: exercise,
                        onRestore: () => _restore(exercise.id),
                      ),
                ],
              ),
      ),
    );
  }

  Future<void> _restore(String id) async {
    try {
      await ref.read(trainingRepositoriesProvider).exercises.restore(id);
    } on DuplicateExerciseNameException {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText =
            'An active user exercise with this name already exists. Rename the '
            'active exercise before restoring.';
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() => _errorText = null);
    await _load();
  }
}

class _ArchivedExerciseRow extends StatelessWidget {
  const _ArchivedExerciseRow({
    required this.exercise,
    required this.onRestore,
  });

  final ExerciseRecord exercise;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.archive_outlined,
            size: 18,
            color: context.colors.textSecondary,
          ),
          const SizedBox(width: AppDimens.dense),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: context.textStyles.body),
                const SizedBox(height: 2),
                Text(
                  _dimensionLabel(exercise.type),
                  style: context.textStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ArchivedExercisesScreen.restoreButtonKey(exercise.id),
            tooltip: 'Restore exercise',
            onPressed: onRestore,
            icon: const Icon(Icons.restore),
          ),
        ],
      ),
    );
  }
}

String _dimensionLabel(ExerciseType type) {
  if (type.isCompletionOnly) {
    return 'Done';
  }

  return type.dimensions.map(_dimensionName).join(' + ');
}

String _dimensionName(DimensionId dimension) {
  return switch (dimension) {
    DimensionId.load => 'Load',
    DimensionId.reps => 'Reps',
    DimensionId.duration => 'Duration',
    DimensionId.distance => 'Distance',
  };
}
