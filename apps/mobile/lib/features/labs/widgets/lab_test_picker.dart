import 'package:flutter/material.dart';

import '../../../domain/labs/lab_test.dart';
import '../../../domain/labs/lab_test_catalogue.generated.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/theme.dart';
import '../../protocols/widgets/protocols_lock_screen.dart';

/// Opens DESIGN.md's Picker sheet over the Lab Test catalogue
/// (docs/designs/lab-results.md, "Collection-based manual entry").
///
/// Single-select: tapping a Lab Test completes with its key. [readOnly] lists
/// the catalogue as the recognised-tests list: its rows are not tappable and
/// the sheet closes only by dismissal, completing with null. It completes with
/// null too when dismissed or when the app locks: the sheet sits behind
/// [ProtocolsLockSheetGuard], because lab results share the Protocols lock.
Future<String?> showLabTestPicker(
  BuildContext context, {
  bool readOnly = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: ProtocolsLockSheetGuard(
        child: FractionallySizedBox(
          heightFactor: _sheetHeightFactor,
          child: LabTestPicker(readOnly: readOnly),
        ),
      ),
    ),
  );
}

/// Nearly full height, leaving a strip of the screen below visible to tap.
const double _sheetHeightFactor = 0.92;

/// The Lab Test picker's content. Open it with [showLabTestPicker].
///
/// The catalogue is grouped by `panel`, panels in [labCataloguePanels] order
/// and Lab Tests in catalogue order. Search is a case-insensitive
/// substring match against the name and every variant: the catalogue is
/// lowercased once ([_searchIndex]), a keystroke filters it in memory, and
/// [ListView.builder] builds only the rows on screen.
class LabTestPicker extends StatefulWidget {
  const LabTestPicker({super.key, this.readOnly = false});

  final bool readOnly;

  static const searchFieldKey = Key('labs.labTestPicker.search');
  static const listKey = Key('labs.labTestPicker.list');
  static const emptyStateKey = Key('labs.labTestPicker.empty');

  static Key rowKey(String key) => Key('labs.labTestPicker.row.$key');

  static Key panelHeaderKey(String panel) =>
      Key('labs.labTestPicker.panel.$panel');

  @override
  State<LabTestPicker> createState() => _LabTestPickerState();
}

class _LabTestPickerState extends State<LabTestPicker> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  String _query = '';
  late List<_PickerItem> _items = _buildItems('');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    // The listener also fires for cursor moves, which change nothing here.
    if (query == _query) {
      return;
    }
    _query = query;
    setState(() => _items = _buildItems(query));
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.base),
          child: Text(
            widget.readOnly
                ? l10n.labTestPickerRecognisedTitle(labTestCatalogue.length)
                : l10n.labTestPickerTitle,
            style: context.textStyles.h2.copyWith(color: colors.textPrimary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppDimens.base),
          child: TextField(
            key: LabTestPicker.searchFieldKey,
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.labTestPickerSearchHint,
              filled: true,
              fillColor: colors.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.cardMd,
                borderSide: BorderSide(color: colors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.cardMd,
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  key: LabTestPicker.emptyStateKey,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.base),
                    child: Text(
                      l10n.labTestPickerEmpty,
                      style: context.textStyles.body.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  key: LabTestPicker.listKey,
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: _items.length,
                  itemBuilder: _buildItem,
                ),
        ),
      ],
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    return switch (_items[index]) {
      _PanelItem(:final panel, :final isFirst) => _PanelHeader(
          key: LabTestPicker.panelHeaderKey(panel),
          panel: panel,
          isFirst: isFirst,
        ),
      _LabTestItem(:final labTest) => _buildRow(labTest),
    };
  }

  Widget _buildRow(LabTest labTest) {
    final colors = context.colors;
    return ListTile(
      key: LabTestPicker.rowKey(labTest.key),
      minTileHeight: AppDimens.touchTarget,
      title: Text(
        labTest.name,
        style: context.textStyles.body.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        labTest.unit,
        style: context.textStyles.caption.copyWith(
          color: colors.textSecondary,
        ),
      ),
      onTap:
          widget.readOnly ? null : () => Navigator.of(context).pop(labTest.key),
    );
  }
}

/// The picker's list for [lowerQuery] (already lowercased and trimmed):
/// a header per panel that has a match, then its matching Lab Tests.
List<_PickerItem> _buildItems(String lowerQuery) {
  final items = <_PickerItem>[];
  String? currentPanel;
  for (final entry in _searchIndex) {
    if (lowerQuery.isNotEmpty && !entry.matches(lowerQuery)) {
      continue;
    }
    final panel = entry.labTest.panel;
    // [_searchIndex] keeps each panel's Lab Tests together, so a new panel
    // name starts a new section.
    if (panel != currentPanel) {
      items.add(_PanelItem(panel, isFirst: items.isEmpty));
      currentPanel = panel;
    }
    items.add(_LabTestItem(entry.labTest));
  }
  return items;
}

/// The catalogue in panel order ([labCataloguePanels], Lab Tests in catalogue
/// order within a panel), with each name and variant lowercased once for
/// search.
final List<_SearchEntry> _searchIndex = List<_SearchEntry>.unmodifiable(
  <_SearchEntry>[
    for (final panel in labCataloguePanels)
      for (final labTest in labTestCatalogue)
        if (labTest.panel == panel) _SearchEntry(labTest),
  ],
);

class _SearchEntry {
  _SearchEntry(this.labTest)
      : _lowerTerms = <String>[
          labTest.name.toLowerCase(),
          for (final variant in labTest.variants) variant.toLowerCase(),
        ];

  final LabTest labTest;
  final List<String> _lowerTerms;

  bool matches(String lowerQuery) =>
      _lowerTerms.any((term) => term.contains(lowerQuery));
}

sealed class _PickerItem {
  const _PickerItem();
}

final class _PanelItem extends _PickerItem {
  const _PanelItem(this.panel, {required this.isFirst});

  final String panel;
  final bool isFirst;
}

final class _LabTestItem extends _PickerItem {
  const _LabTestItem(this.labTest);

  final LabTest labTest;
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required super.key,
    required this.panel,
    required this.isFirst,
  });

  final String panel;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimens.base,
        isFirst ? 0 : AppDimens.base,
        AppDimens.base,
        AppDimens.dense,
      ),
      child: Semantics(
        header: true,
        child: Text(
          panel,
          style: context.textStyles.label.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
