/// A food's supermarket Aisle: the browsing group the add-food picker shows
/// for a bundled Open Food Facts product. The id is the enum value's `name`,
/// and the same id is written in the bundle, the labels file and the reference
/// set, and used on the agent surface.
///
/// The order is the order the picker shows. The enum stays in the
/// one-value-per-line `id('Label'),` form because a server test reads it with
/// a regular expression to check that the server's copy matches.
///
/// See docs/designs/food-aisles.md, "The Aisles".
enum FoodAisle {
  dairyEggs('Dairy & eggs'),
  breadBakery('Bread & bakery'),
  breakfastCereals('Breakfast cereals'),
  meatSeafood('Meat & seafood'),
  fruitVeg('Fruit & vegetables'),
  pantry('Pantry'),
  saucesSpreads('Sauces & spreads'),
  snacks('Snacks'),
  sweetsDesserts('Sweets & desserts'),
  drinks('Drinks'),
  alcohol('Alcohol'),
  readyMeals('Ready meals'),
  proteinSupplements('Protein & supplements'),
  babyFood('Baby food');

  const FoodAisle(this.label);

  final String label;
}

/// The Aisle with this id, or `null` for an unknown id.
FoodAisle? foodAisleById(String id) {
  for (final aisle in FoodAisle.values) {
    if (aisle.name == id) {
      return aisle;
    }
  }
  return null;
}

/// How many of an Aisle's most scanned products the picker lists, and so which
/// of them count as its Browse rows. This is the one definition of the number.
const aisleBrowseLimit = 100;
