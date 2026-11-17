import '../../../domain/nutrition/nutrition.dart';

/// A Portion as the user entered it, for example "250 ml": the Food Entry
/// amount on the Nutrition Day view and the Last Portion in the add-food
/// picker.
String formatPortionAmount(Portion portion) {
  return '${portion.entered} ${portionUnitLabel(portion.unit)}';
}
