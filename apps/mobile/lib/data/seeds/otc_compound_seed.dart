import '../../domain/protocols/protocols.dart';

/// The tiny built-in **OTC seed** `Compound` library (PROTOCOLS.md §3).
///
/// A handful of neutral starter rows so a first-run user can pick a `Compound`
/// and log a `Dose` immediately, rather than typing a name from scratch. Each
/// row carries only a name + a sensible default unit/route (from the curated
/// registries) and, where it reads naturally, an optional strength.
///
/// CRITICAL neutral-instrument posture: a seed row is **never** named
/// or categorized by substance type or legality. There is deliberately no
/// "category"/"class"/"schedule"/"controlled"/"type" field anywhere in the seed
/// — the genericity IS the legal posture. This is a neutral logbook, not a
/// facilitator. A reviewer will reject any categorization-by-type/legality.
abstract interface class OtcCompoundSeedSource {
  /// The seed rows to load. Implementations must return STABLE ids so the load
  /// is idempotent across re-runs (mirroring the platform-exercise/usda-food
  /// seed precedent).
  List<OtcCompoundSeedRow> load();
}

/// A single OTC seed `Compound`: a stable id plus the same neutral catalogue
/// shape as a user-created `Compound` (name + default unit/route + optional
/// strength). No type/legality field, by design.
class OtcCompoundSeedRow {
  const OtcCompoundSeedRow({
    required this.id,
    required this.name,
    required this.defaultUnit,
    required this.defaultRoute,
    this.strength,
  });

  /// A STABLE id, fixed per seed row so re-running the seed never duplicates it
  /// (idempotency). UUIDv7-shaped with a reserved seed block so it can never
  /// collide with a runtime-generated `Compound` id.
  final String id;
  final String name;
  final DoseUnit defaultUnit;
  final DoseRoute defaultRoute;

  /// The optional structured strength (curated units, never free-text), present
  /// only where one reads naturally (e.g. vitamin D's per-capsule IU). Null
  /// where a default strength would be arbitrary (e.g. caffeine, magnesium).
  final CompoundStrength? strength;
}

/// The default, in-code OTC seed. Six neutral, everyday compounds, each with a
/// sensible default unit/route. The set is deliberately small and generic
/// — it is a starting point, not a typed or exhaustive catalogue.
///
/// Ids live in a reserved UUIDv7 seed block (`019200ff-…-7…-8000-0000000000NN`)
/// distinct from the platform-exercise seed block, so they are stable across
/// runs yet never collide with runtime ids.
class DefaultOtcCompoundSeedSource implements OtcCompoundSeedSource {
  const DefaultOtcCompoundSeedSource();

  @override
  List<OtcCompoundSeedRow> load() {
    return <OtcCompoundSeedRow>[
      OtcCompoundSeedRow(
        id: '019200ff-0000-7000-8000-000000000001',
        name: 'Creatine',
        defaultUnit: DoseUnit.gram,
        defaultRoute: DoseRoute.oral,
      ),
      OtcCompoundSeedRow(
        id: '019200ff-0000-7000-8000-000000000002',
        name: 'Vitamin D',
        defaultUnit: DoseUnit.internationalUnit,
        defaultRoute: DoseRoute.oral,
        strength: CompoundStrength.parse('1000 IU/capsule'),
      ),
      OtcCompoundSeedRow(
        id: '019200ff-0000-7000-8000-000000000003',
        name: 'Caffeine',
        defaultUnit: DoseUnit.milligram,
        defaultRoute: DoseRoute.oral,
      ),
      OtcCompoundSeedRow(
        id: '019200ff-0000-7000-8000-000000000004',
        name: 'Magnesium',
        defaultUnit: DoseUnit.milligram,
        defaultRoute: DoseRoute.oral,
      ),
      OtcCompoundSeedRow(
        id: '019200ff-0000-7000-8000-000000000005',
        name: 'Melatonin',
        defaultUnit: DoseUnit.milligram,
        defaultRoute: DoseRoute.sublingual,
      ),
      OtcCompoundSeedRow(
        id: '019200ff-0000-7000-8000-000000000006',
        name: 'Fish oil',
        defaultUnit: DoseUnit.capsule,
        defaultRoute: DoseRoute.oral,
      ),
    ];
  }
}
