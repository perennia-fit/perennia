import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/training_repositories.dart';
import '../../../theme/theme.dart';

class CategoryManagerScreen extends ConsumerStatefulWidget {
  const CategoryManagerScreen({super.key});

  static const routeName = '/categories';
  static const nameFieldKey = Key('category-manager-name');
  static const createButtonKey = Key('category-manager-create');
  static const alphabetizeButtonKey = Key('category-manager-alphabetize');
  static const renameFieldKey = Key('category-manager-rename-name');
  static const renameConfirmButtonKey = Key('category-manager-rename-confirm');

  static Key renameButtonKey(String id) => Key('category-manager-rename-$id');
  static Key archiveButtonKey(String id) => Key('category-manager-archive-$id');
  static Key moveUpButtonKey(String id) => Key('category-manager-up-$id');
  static Key moveDownButtonKey(String id) => Key('category-manager-down-$id');
  static Key colorButtonKey(String id, String colorHex) {
    return Key('category-manager-color-$id-${colorHex.substring(1)}');
  }

  @override
  ConsumerState<CategoryManagerScreen> createState() =>
      _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends ConsumerState<CategoryManagerScreen> {
  final _nameController = TextEditingController();
  final _scrollController = ScrollController();

  List<ExerciseCategoryRecord> _categories = const <ExerciseCategoryRecord>[];
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

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repositories = ref.read(trainingRepositoriesProvider);
    await repositories.catalog.ensurePlatformLibrarySeeded();
    final categories = await repositories.catalog.listCategories();
    if (!mounted) {
      return;
    }

    setState(() {
      _categories = categories;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: SafeArea(
        child: _isLoading
            ? const SizedBox.expand()
            : ListView(
                controller: _scrollController,
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
                  TextField(
                    key: CategoryManagerScreen.nameFieldKey,
                    controller: _nameController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'New category',
                    ),
                    onSubmitted: (_) => _createCategory(),
                  ),
                  const SizedBox(height: AppDimens.dense),
                  FilledButton.icon(
                    key: CategoryManagerScreen.createButtonKey,
                    onPressed: _createCategory,
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                  ),
                  const SizedBox(height: AppDimens.base),
                  OutlinedButton.icon(
                    key: CategoryManagerScreen.alphabetizeButtonKey,
                    onPressed: _alphabetizeCategories,
                    icon: const Icon(Icons.sort_by_alpha),
                    label: const Text('Alphabetize'),
                  ),
                  const SizedBox(height: AppDimens.base),
                  for (var index = 0; index < _categories.length; index += 1)
                    _CategoryRow(
                      category: _categories[index],
                      isFirst: index == 0,
                      isLast: index == _categories.length - 1,
                      onRename: () => _renameCategory(_categories[index]),
                      onRecolor: (colorHex) => _recolorCategory(
                        _categories[index],
                        colorHex,
                      ),
                      onMoveUp: () => _moveCategory(index, -1),
                      onMoveDown: () => _moveCategory(index, 1),
                      onArchive: () => _archiveCategory(_categories[index]),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _createCategory() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Category name is required.');
      return;
    }

    try {
      await ref.read(trainingRepositoriesProvider).catalog.createCategory(
            ExerciseCategoryDraft(name: name),
          );
    } on DuplicateExerciseCategoryNameException {
      if (!mounted) {
        return;
      }
      _showError('A category with this name already exists.');
      return;
    }

    if (!mounted) {
      return;
    }
    _nameController.clear();
    setState(() => _errorText = null);
    await _load();
  }

  Future<void> _renameCategory(ExerciseCategoryRecord category) async {
    final name = await _promptForName(category.name);
    if (name == null) {
      return;
    }

    try {
      await ref.read(trainingRepositoriesProvider).catalog.renameCategory(
            category.id,
            name: name,
          );
    } on DuplicateExerciseCategoryNameException {
      if (!mounted) {
        return;
      }
      _showError('A category with this name already exists.');
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _errorText = null);
    await _load();
  }

  Future<String?> _promptForName(String initialName) async {
    var draftName = initialName;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename category'),
        content: TextFormField(
          key: CategoryManagerScreen.renameFieldKey,
          initialValue: initialName,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => draftName = value,
          onFieldSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: CategoryManagerScreen.renameConfirmButtonKey,
            onPressed: () => Navigator.of(context).pop(draftName.trim()),
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _recolorCategory(
    ExerciseCategoryRecord category,
    String colorHex,
  ) async {
    await ref.read(trainingRepositoriesProvider).catalog.recolorCategory(
          category.id,
          colorHex: colorHex,
        );
    if (!mounted) {
      return;
    }
    setState(() => _errorText = null);
    await _load();
  }

  Future<void> _moveCategory(int index, int delta) async {
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= _categories.length) {
      return;
    }

    final orderedIds =
        _categories.map((category) => category.id).toList(growable: true);
    final id = orderedIds.removeAt(index);
    orderedIds.insert(targetIndex, id);
    await ref.read(trainingRepositoriesProvider).catalog.reorderCategories(
          orderedIds,
        );
    if (!mounted) {
      return;
    }
    setState(() => _errorText = null);
    await _load();
  }

  Future<void> _alphabetizeCategories() async {
    await ref
        .read(trainingRepositoriesProvider)
        .catalog
        .alphabetizeCategories();
    if (!mounted) {
      return;
    }
    setState(() => _errorText = null);
    await _load();
  }

  Future<void> _archiveCategory(ExerciseCategoryRecord category) async {
    try {
      await ref.read(trainingRepositoriesProvider).catalog.archiveCategory(
            category.id,
          );
    } on CategoryHasActiveExercisesException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(
        'Cannot archive ${category.name} while it has '
        '${error.activeExerciseCount} active '
        '${_exerciseCountLabel(error.activeExerciseCount)}. Reassign or '
        'archive ${_thoseExercisesLabel(error.activeExerciseCount)} first.',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _errorText = null);
    await _load();
  }

  void _showError(String message) {
    setState(() => _errorText = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.isFirst,
    required this.isLast,
    required this.onRename,
    required this.onRecolor,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onArchive,
  });

  final ExerciseCategoryRecord category;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onRename;
  final ValueChanged<String> onRecolor;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.dense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorFromHex(
                    category.colorHex,
                    fallback: context.colors.categoryColor('other'),
                  ),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 14),
              ),
              const SizedBox(width: AppDimens.dense),
              Expanded(
                child: Text(category.name, style: context.textStyles.body),
              ),
              IconButton(
                key: CategoryManagerScreen.renameButtonKey(category.id),
                tooltip: 'Rename category',
                onPressed: onRename,
                icon: const Icon(Icons.edit),
              ),
              IconButton(
                key: CategoryManagerScreen.moveUpButtonKey(category.id),
                tooltip: 'Move up',
                onPressed: isFirst ? null : onMoveUp,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton(
                key: CategoryManagerScreen.moveDownButtonKey(category.id),
                tooltip: 'Move down',
                onPressed: isLast ? null : onMoveDown,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton(
                key: CategoryManagerScreen.archiveButtonKey(category.id),
                tooltip: 'Archive category',
                onPressed: onArchive,
                icon: const Icon(Icons.archive_outlined),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.dense),
          Wrap(
            spacing: AppDimens.dense,
            runSpacing: AppDimens.dense,
            children: [
              for (final colorHex in _categoryColorPalette)
                IconButton(
                  key: CategoryManagerScreen.colorButtonKey(
                    category.id,
                    colorHex,
                  ),
                  tooltip: _colorTooltip(colorHex),
                  onPressed: category.colorHex == colorHex
                      ? null
                      : () => onRecolor(colorHex),
                  icon: Icon(
                    Icons.circle,
                    color: colorFromHex(
                      colorHex,
                      fallback: context.colors.categoryColor('other'),
                    ),
                  ),
                ),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }
}

String _colorTooltip(String colorHex) => 'Use $colorHex';

String _exerciseCountLabel(int count) => count == 1 ? 'exercise' : 'exercises';

String _thoseExercisesLabel(int count) =>
    count == 1 ? 'that exercise' : 'those exercises';

const _categoryColorPalette = <String>[
  '#2F6FED',
  '#1F9D55',
  '#E11D48',
  '#7C3AED',
  '#EA580C',
  '#0891B2',
];
