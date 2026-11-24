// GENERATED FILE — do not edit by hand.
// Regenerate with: node tools/generate-lab-test-catalogue.mjs
//
// Source: packages/lab-catalogue/lab-tests.json, the Lab Test catalogue
// (docs/designs/lab-results.md). The server carries the same entries in
// apps/server/src/data/lab-test-catalogue.generated.ts; the contract-drift
// gate re-runs the generator and fails when either file is stale.

import 'lab_test.dart';

const _source0 = DefaultRangeSource(
  title: 'Harmonising Adult and Paediatric Reference Intervals in Australia '
      'and New Zealand: An Evidence-Based Approach for Establishing a First '
      'Panel of Chemistry Analytes',
  url: 'https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061',
  version: '2014',
);

/// Every Lab Test, in display order.
const List<LabTest> labTestCatalogue = [
  LabTest(
    key: 'testosterone_total',
    name: 'Testosterone',
    panel: 'Sex hormones',
    variants: [
      'total testosterone',
      'testosterone total',
      'testosterone, total',
      'serum testosterone',
    ],
    unit: 'nmol/L',
    unitAliases: [
      'nmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'testosterone_free_calc',
    name: 'Free testosterone (calculated)',
    panel: 'Sex hormones',
    variants: [
      'free testosterone',
      'calculated free testosterone',
      'free testosterone calculated',
      'free testosterone (calc)',
      'cft',
    ],
    unit: 'pmol/L',
    unitAliases: [
      'pmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'shbg',
    name: 'SHBG',
    panel: 'Sex hormones',
    variants: [
      'sex hormone binding globulin',
      'sex hormone-binding globulin',
    ],
    unit: 'nmol/L',
    unitAliases: [
      'nmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'oestradiol',
    name: 'Oestradiol',
    panel: 'Sex hormones',
    variants: [
      'estradiol',
      'e2',
      'oestradiol (e2)',
      'estradiol (e2)',
    ],
    unit: 'pmol/L',
    unitAliases: [
      'pmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'lh',
    name: 'LH',
    panel: 'Sex hormones',
    variants: [
      'luteinising hormone',
      'luteinizing hormone',
    ],
    unit: 'IU/L',
    unitAliases: [
      'IU/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'fsh',
    name: 'FSH',
    panel: 'Sex hormones',
    variants: [
      'follicle stimulating hormone',
      'follicle-stimulating hormone',
    ],
    unit: 'IU/L',
    unitAliases: [
      'IU/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'progesterone',
    name: 'Progesterone',
    panel: 'Sex hormones',
    variants: [
      'serum progesterone',
      'p4',
    ],
    unit: 'nmol/L',
    unitAliases: [
      'nmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'prolactin',
    name: 'Prolactin',
    panel: 'Pituitary and adrenal',
    variants: [
      'prl',
      'serum prolactin',
    ],
    unit: 'mIU/L',
    unitAliases: [
      'mIU/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'cortisol',
    name: 'Cortisol',
    panel: 'Pituitary and adrenal',
    variants: [
      'serum cortisol',
      'cortisol (am)',
      'morning cortisol',
    ],
    unit: 'nmol/L',
    unitAliases: [
      'nmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'growth_hormone',
    name: 'Growth hormone',
    panel: 'Pituitary and adrenal',
    variants: [
      'gh',
      'hgh',
      'human growth hormone',
      'somatotropin',
    ],
    unit: 'ug/L',
    unitAliases: [
      'ug/l',
      'µg/L',
      'µg/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'igf_1',
    name: 'IGF-1',
    panel: 'Pituitary and adrenal',
    variants: [
      'igf-1',
      'igf1',
      'igf 1',
      'insulin-like growth factor 1',
      'insulin like growth factor 1',
      'somatomedin c',
    ],
    unit: 'nmol/L',
    unitAliases: [
      'nmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'dhea_s',
    name: 'DHEA-S',
    panel: 'Pituitary and adrenal',
    variants: [
      'dhea-s',
      'dheas',
      'dhea sulphate',
      'dhea sulfate',
      'dehydroepiandrosterone sulphate',
      'dehydroepiandrosterone sulfate',
    ],
    unit: 'umol/L',
    unitAliases: [
      'umol/l',
      'µmol/L',
      'µmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'cholesterol_total',
    name: 'Total cholesterol',
    panel: 'Lipids',
    variants: [
      'cholesterol',
      'cholesterol total',
      'cholesterol, total',
      'tc',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.riskTarget,
    defaultRanges: [],
  ),
  LabTest(
    key: 'triglycerides',
    name: 'Triglycerides',
    panel: 'Lipids',
    variants: [
      'triglyceride',
      'trig',
      'trigs',
      'tg',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.riskTarget,
    defaultRanges: [],
  ),
  LabTest(
    key: 'hdl_cholesterol',
    name: 'HDL cholesterol',
    panel: 'Lipids',
    variants: [
      'hdl',
      'hdl-c',
      'hdl-cholesterol',
      'hdl chol',
      'high density lipoprotein cholesterol',
      'high-density lipoprotein cholesterol',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.riskTarget,
    defaultRanges: [],
  ),
  LabTest(
    key: 'ldl_cholesterol',
    name: 'LDL cholesterol',
    panel: 'Lipids',
    variants: [
      'ldl',
      'ldl-c',
      'ldl-cholesterol',
      'ldl chol',
      'ldl (calculated)',
      'low density lipoprotein cholesterol',
      'low-density lipoprotein cholesterol',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.riskTarget,
    defaultRanges: [],
  ),
  LabTest(
    key: 'non_hdl_cholesterol',
    name: 'Non-HDL cholesterol',
    panel: 'Lipids',
    variants: [
      'non-hdl',
      'non hdl',
      'non-hdl-c',
      'non hdl cholesterol',
      'non-hdl-cholesterol',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.riskTarget,
    defaultRanges: [],
  ),
  LabTest(
    key: 'cholesterol_hdl_ratio',
    name: 'Cholesterol/HDL ratio',
    panel: 'Lipids',
    variants: [
      'total/hdl ratio',
      'chol/hdl ratio',
      'tc/hdl ratio',
      'total cholesterol/hdl ratio',
      'cholesterol/hdl',
      'chol/hdl',
    ],
    unit: 'ratio',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 100,
    ),
    printedRangeKind: PrintedRangeKind.riskTarget,
    defaultRanges: [],
  ),
  LabTest(
    key: 'hs_crp',
    name: 'hs-CRP',
    panel: 'Inflammation',
    variants: [
      'hs-crp',
      'hscrp',
      'hs crp',
      'high sensitivity crp',
      'high-sensitivity crp',
      'high sensitivity c-reactive protein',
      'high-sensitivity c-reactive protein',
      'crp (high sensitivity)',
    ],
    unit: 'mg/L',
    unitAliases: [
      'mg/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'sodium',
    name: 'Sodium',
    panel: 'Electrolytes',
    variants: [
      'na',
      'na+',
      'serum sodium',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 27,
      max: 725,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 135,
        high: 145,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'potassium',
    name: 'Potassium',
    panel: 'Electrolytes',
    variants: [
      'k',
      'k+',
      'serum potassium',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 0.7,
      max: 26,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 3.5,
        high: 5.2,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'chloride',
    name: 'Chloride',
    panel: 'Electrolytes',
    variants: [
      'cl',
      'cl-',
      'serum chloride',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 19,
      max: 550,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 95,
        high: 110,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'bicarbonate',
    name: 'Bicarbonate',
    panel: 'Electrolytes',
    variants: [
      'hco3',
      'hco3-',
      'total co2',
      'co2',
      'bicarb',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 4.4,
      max: 160,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 22,
        high: 32,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'anion_gap',
    name: 'Anion gap',
    panel: 'Electrolytes',
    variants: [
      'ag',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'urea',
    name: 'Urea',
    panel: 'Kidney',
    variants: [
      'serum urea',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'creatinine',
    name: 'Creatinine',
    panel: 'Kidney',
    variants: [
      'creat',
      'serum creatinine',
    ],
    unit: 'umol/L',
    unitAliases: [
      'umol/l',
      'µmol/L',
      'µmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    plausibleBounds: Bounds(
      min: 9,
      max: 550,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.female,
        ageMin: 18,
        ageMax: 59,
        low: 45,
        high: 90,
        source: _source0,
      ),
      DefaultRange(
        sex: DefaultRangeSex.male,
        ageMin: 18,
        ageMax: 59,
        low: 60,
        high: 110,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'egfr',
    name: 'eGFR',
    panel: 'Kidney',
    variants: [
      'egfr',
      'estimated gfr',
      'estimated glomerular filtration rate',
      'egfr (ckd-epi)',
    ],
    unit: 'mL/min/1.73m²',
    unitAliases: [
      'mL/min/1.73m2',
      'ml/min/1.73m²',
      'ml/min/1.73m2',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'urate',
    name: 'Urate',
    panel: 'Kidney',
    variants: [
      'uric acid',
      'serum urate',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'bilirubin_total',
    name: 'Total bilirubin',
    panel: 'Liver',
    variants: [
      'bilirubin',
      'bilirubin total',
      'bilirubin, total',
      't bili',
      'tbil',
    ],
    unit: 'umol/L',
    unitAliases: [
      'umol/l',
      'µmol/L',
      'µmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'alp',
    name: 'ALP',
    panel: 'Liver',
    variants: [
      'alk phos',
      'alkaline phosphatase',
      'alk phosphatase',
    ],
    unit: 'U/L',
    unitAliases: [
      'U/l',
      'IU/L',
      'IU/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    plausibleBounds: Bounds(
      min: 6,
      max: 550,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 22,
        low: 30,
        high: 110,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'ggt',
    name: 'GGT',
    panel: 'Liver',
    variants: [
      'gamma gt',
      'gamma-gt',
      'gamma glutamyl transferase',
      'gamma-glutamyl transferase',
      'ggtp',
    ],
    unit: 'U/L',
    unitAliases: [
      'U/l',
      'IU/L',
      'IU/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'alt',
    name: 'ALT',
    panel: 'Liver',
    variants: [
      'alanine aminotransferase',
      'alanine transaminase',
      'sgpt',
    ],
    unit: 'U/L',
    unitAliases: [
      'U/l',
      'IU/L',
      'IU/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'ast',
    name: 'AST',
    panel: 'Liver',
    variants: [
      'aspartate aminotransferase',
      'aspartate transaminase',
      'sgot',
    ],
    unit: 'U/L',
    unitAliases: [
      'U/l',
      'IU/L',
      'IU/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'ld',
    name: 'LD',
    panel: 'Liver',
    variants: [
      'ldh',
      'lactate dehydrogenase',
    ],
    unit: 'U/L',
    unitAliases: [
      'U/l',
      'IU/L',
      'IU/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 10000,
    ),
    plausibleBounds: Bounds(
      min: 24,
      max: 1250,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 120,
        high: 250,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'total_protein',
    name: 'Total protein',
    panel: 'Liver',
    variants: [
      'protein',
      'protein total',
      'protein, total',
      'serum protein',
    ],
    unit: 'g/L',
    unitAliases: [
      'g/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 12,
      max: 400,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 60,
        high: 80,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'albumin',
    name: 'Albumin',
    panel: 'Liver',
    variants: [
      'alb',
      'serum albumin',
    ],
    unit: 'g/L',
    unitAliases: [
      'g/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'globulin',
    name: 'Globulin',
    panel: 'Liver',
    variants: [
      'globulins',
      'serum globulin',
    ],
    unit: 'g/L',
    unitAliases: [
      'g/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'calcium',
    name: 'Calcium',
    panel: 'Bone and minerals',
    variants: [
      'ca',
      'total calcium',
      'serum calcium',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 0.42,
      max: 13,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 2.1,
        high: 2.6,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'calcium_adjusted',
    name: 'Adjusted calcium',
    panel: 'Bone and minerals',
    variants: [
      'corrected calcium',
      'calcium (adjusted for albumin)',
      'calcium adjusted',
      'calcium (albumin adjusted)',
      'albumin adjusted calcium',
      'albumin-adjusted calcium',
      'calcium corrected',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 0.42,
      max: 13,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 2.1,
        high: 2.6,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'phosphate',
    name: 'Phosphate',
    panel: 'Bone and minerals',
    variants: [
      'phosphorus',
      'inorganic phosphate',
      'po4',
      'serum phosphate',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 0.15,
      max: 7.5,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 20,
        low: 0.75,
        high: 1.5,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'magnesium',
    name: 'Magnesium',
    panel: 'Bone and minerals',
    variants: [
      'mg2+',
      'serum magnesium',
    ],
    unit: 'mmol/L',
    unitAliases: [
      'mmol/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    plausibleBounds: Bounds(
      min: 0.14,
      max: 5.5,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [
      DefaultRange(
        sex: DefaultRangeSex.any,
        ageMin: 18,
        low: 0.7,
        high: 1.1,
        source: _source0,
      ),
    ],
  ),
  LabTest(
    key: 'haemoglobin',
    name: 'Haemoglobin',
    panel: 'Full blood count',
    variants: [
      'hemoglobin',
      'hb',
      'hgb',
    ],
    unit: 'g/L',
    unitAliases: [
      'g/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'haematocrit',
    name: 'Haematocrit',
    panel: 'Full blood count',
    variants: [
      'hematocrit',
      'hct',
      'pcv',
      'packed cell volume',
    ],
    unit: 'L/L',
    unitAliases: [
      'L/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'rcc',
    name: 'Red cell count',
    panel: 'Full blood count',
    variants: [
      'rcc',
      'rbc',
      'red blood cell count',
      'red blood cells',
      'red cells',
      'erythrocytes',
    ],
    unit: 'x10^12/L',
    unitAliases: [
      'x10^12/l',
      '10^12/L',
      '10^12/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 100,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'mcv',
    name: 'MCV',
    panel: 'Full blood count',
    variants: [
      'mean cell volume',
      'mean corpuscular volume',
    ],
    unit: 'fL',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'mch',
    name: 'MCH',
    panel: 'Full blood count',
    variants: [
      'mean cell haemoglobin',
      'mean cell hemoglobin',
      'mean corpuscular haemoglobin',
      'mean corpuscular hemoglobin',
    ],
    unit: 'pg',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'mchc',
    name: 'MCHC',
    panel: 'Full blood count',
    variants: [
      'mean cell haemoglobin concentration',
      'mean cell hemoglobin concentration',
      'mean corpuscular haemoglobin concentration',
      'mean corpuscular hemoglobin concentration',
    ],
    unit: 'g/L',
    unitAliases: [
      'g/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'rdw',
    name: 'RDW',
    panel: 'Full blood count',
    variants: [
      'red cell distribution width',
      'rdw-cv',
      'rdw cv',
    ],
    unit: '%',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 100,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'wcc',
    name: 'White cell count',
    panel: 'Full blood count',
    variants: [
      'wcc',
      'wbc',
      'white blood cell count',
      'white blood cells',
      'white cells',
      'leucocytes',
      'leukocytes',
    ],
    unit: 'x10^9/L',
    unitAliases: [
      'x10^9/l',
      '10^9/L',
      '10^9/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'platelets',
    name: 'Platelets',
    panel: 'Full blood count',
    variants: [
      'plt',
      'platelet count',
      'plts',
    ],
    unit: 'x10^9/L',
    unitAliases: [
      'x10^9/l',
      '10^9/L',
      '10^9/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'neutrophils_percent',
    name: 'Neutrophils %',
    panel: 'Full blood count',
    variants: [
      'neutrophils %',
      'neutrophils (%)',
      'neutrophil %',
      '% neutrophils',
      'neut %',
    ],
    unit: '%',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 100,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'neutrophils_count',
    name: 'Neutrophils',
    panel: 'Full blood count',
    variants: [
      'neutrophil count',
      'neutrophils count',
      'absolute neutrophil count',
      'neutrophils (absolute)',
      'neut #',
      'anc',
    ],
    unit: 'x10^9/L',
    unitAliases: [
      'x10^9/l',
      '10^9/L',
      '10^9/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'lymphocytes_percent',
    name: 'Lymphocytes %',
    panel: 'Full blood count',
    variants: [
      'lymphocytes %',
      'lymphocytes (%)',
      'lymphocyte %',
      '% lymphocytes',
      'lymph %',
    ],
    unit: '%',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 100,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'lymphocytes_count',
    name: 'Lymphocytes',
    panel: 'Full blood count',
    variants: [
      'lymphocyte count',
      'lymphocytes count',
      'absolute lymphocyte count',
      'lymphocytes (absolute)',
      'lymph #',
    ],
    unit: 'x10^9/L',
    unitAliases: [
      'x10^9/l',
      '10^9/L',
      '10^9/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'monocytes_percent',
    name: 'Monocytes %',
    panel: 'Full blood count',
    variants: [
      'monocytes %',
      'monocytes (%)',
      'monocyte %',
      '% monocytes',
      'mono %',
    ],
    unit: '%',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 100,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'monocytes_count',
    name: 'Monocytes',
    panel: 'Full blood count',
    variants: [
      'monocyte count',
      'monocytes count',
      'absolute monocyte count',
      'monocytes (absolute)',
      'mono #',
    ],
    unit: 'x10^9/L',
    unitAliases: [
      'x10^9/l',
      '10^9/L',
      '10^9/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'eosinophils_percent',
    name: 'Eosinophils %',
    panel: 'Full blood count',
    variants: [
      'eosinophils %',
      'eosinophils (%)',
      'eosinophil %',
      '% eosinophils',
      'eos %',
    ],
    unit: '%',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 100,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'eosinophils_count',
    name: 'Eosinophils',
    panel: 'Full blood count',
    variants: [
      'eosinophil count',
      'eosinophils count',
      'absolute eosinophil count',
      'eosinophils (absolute)',
      'eos #',
    ],
    unit: 'x10^9/L',
    unitAliases: [
      'x10^9/l',
      '10^9/L',
      '10^9/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'basophils_percent',
    name: 'Basophils %',
    panel: 'Full blood count',
    variants: [
      'basophils %',
      'basophils (%)',
      'basophil %',
      '% basophils',
      'baso %',
    ],
    unit: '%',
    unitAliases: [],
    hardBounds: Bounds(
      min: 0,
      max: 100,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
  LabTest(
    key: 'basophils_count',
    name: 'Basophils',
    panel: 'Full blood count',
    variants: [
      'basophil count',
      'basophils count',
      'absolute basophil count',
      'basophils (absolute)',
      'baso #',
    ],
    unit: 'x10^9/L',
    unitAliases: [
      'x10^9/l',
      '10^9/L',
      '10^9/l',
    ],
    hardBounds: Bounds(
      min: 0,
      max: 1000,
    ),
    printedRangeKind: PrintedRangeKind.reference,
    defaultRanges: [],
  ),
];

/// Per Lab Test key, each folded spelling of its unit (see [foldUnit])
/// mapped to its canonical unit.
const Map<String, Map<String, String>> labTestFoldedUnits = {
  'testosterone_total': {
    'nmol/L': 'nmol/L',
    'nmol/l': 'nmol/L',
  },
  'testosterone_free_calc': {
    'pmol/L': 'pmol/L',
    'pmol/l': 'pmol/L',
  },
  'shbg': {
    'nmol/L': 'nmol/L',
    'nmol/l': 'nmol/L',
  },
  'oestradiol': {
    'pmol/L': 'pmol/L',
    'pmol/l': 'pmol/L',
  },
  'lh': {
    'IU/L': 'IU/L',
    'IU/l': 'IU/L',
  },
  'fsh': {
    'IU/L': 'IU/L',
    'IU/l': 'IU/L',
  },
  'progesterone': {
    'nmol/L': 'nmol/L',
    'nmol/l': 'nmol/L',
  },
  'prolactin': {
    'mIU/L': 'mIU/L',
    'mIU/l': 'mIU/L',
  },
  'cortisol': {
    'nmol/L': 'nmol/L',
    'nmol/l': 'nmol/L',
  },
  'growth_hormone': {
    'ug/L': 'ug/L',
    'ug/l': 'ug/L',
    'µg/L': 'ug/L',
    'µg/l': 'ug/L',
  },
  'igf_1': {
    'nmol/L': 'nmol/L',
    'nmol/l': 'nmol/L',
  },
  'dhea_s': {
    'umol/L': 'umol/L',
    'umol/l': 'umol/L',
    'µmol/L': 'umol/L',
    'µmol/l': 'umol/L',
  },
  'cholesterol_total': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'triglycerides': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'hdl_cholesterol': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'ldl_cholesterol': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'non_hdl_cholesterol': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'cholesterol_hdl_ratio': {
    'ratio': 'ratio',
  },
  'hs_crp': {
    'mg/L': 'mg/L',
    'mg/l': 'mg/L',
  },
  'sodium': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'potassium': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'chloride': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'bicarbonate': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'anion_gap': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'urea': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'creatinine': {
    'umol/L': 'umol/L',
    'umol/l': 'umol/L',
    'µmol/L': 'umol/L',
    'µmol/l': 'umol/L',
  },
  'egfr': {
    'mL/min/1.73m²': 'mL/min/1.73m²',
    'mL/min/1.73m2': 'mL/min/1.73m²',
    'ml/min/1.73m²': 'mL/min/1.73m²',
    'ml/min/1.73m2': 'mL/min/1.73m²',
  },
  'urate': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'bilirubin_total': {
    'umol/L': 'umol/L',
    'umol/l': 'umol/L',
    'µmol/L': 'umol/L',
    'µmol/l': 'umol/L',
  },
  'alp': {
    'U/L': 'U/L',
    'U/l': 'U/L',
    'IU/L': 'U/L',
    'IU/l': 'U/L',
  },
  'ggt': {
    'U/L': 'U/L',
    'U/l': 'U/L',
    'IU/L': 'U/L',
    'IU/l': 'U/L',
  },
  'alt': {
    'U/L': 'U/L',
    'U/l': 'U/L',
    'IU/L': 'U/L',
    'IU/l': 'U/L',
  },
  'ast': {
    'U/L': 'U/L',
    'U/l': 'U/L',
    'IU/L': 'U/L',
    'IU/l': 'U/L',
  },
  'ld': {
    'U/L': 'U/L',
    'U/l': 'U/L',
    'IU/L': 'U/L',
    'IU/l': 'U/L',
  },
  'total_protein': {
    'g/L': 'g/L',
    'g/l': 'g/L',
  },
  'albumin': {
    'g/L': 'g/L',
    'g/l': 'g/L',
  },
  'globulin': {
    'g/L': 'g/L',
    'g/l': 'g/L',
  },
  'calcium': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'calcium_adjusted': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'phosphate': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'magnesium': {
    'mmol/L': 'mmol/L',
    'mmol/l': 'mmol/L',
  },
  'haemoglobin': {
    'g/L': 'g/L',
    'g/l': 'g/L',
  },
  'haematocrit': {
    'L/L': 'L/L',
    'L/l': 'L/L',
  },
  'rcc': {
    'x10^12/L': 'x10^12/L',
    'x10^12/l': 'x10^12/L',
    '10^12/L': 'x10^12/L',
    '10^12/l': 'x10^12/L',
  },
  'mcv': {
    'fL': 'fL',
  },
  'mch': {
    'pg': 'pg',
  },
  'mchc': {
    'g/L': 'g/L',
    'g/l': 'g/L',
  },
  'rdw': {
    '%': '%',
  },
  'wcc': {
    'x10^9/L': 'x10^9/L',
    'x10^9/l': 'x10^9/L',
    '10^9/L': 'x10^9/L',
    '10^9/l': 'x10^9/L',
  },
  'platelets': {
    'x10^9/L': 'x10^9/L',
    'x10^9/l': 'x10^9/L',
    '10^9/L': 'x10^9/L',
    '10^9/l': 'x10^9/L',
  },
  'neutrophils_percent': {
    '%': '%',
  },
  'neutrophils_count': {
    'x10^9/L': 'x10^9/L',
    'x10^9/l': 'x10^9/L',
    '10^9/L': 'x10^9/L',
    '10^9/l': 'x10^9/L',
  },
  'lymphocytes_percent': {
    '%': '%',
  },
  'lymphocytes_count': {
    'x10^9/L': 'x10^9/L',
    'x10^9/l': 'x10^9/L',
    '10^9/L': 'x10^9/L',
    '10^9/l': 'x10^9/L',
  },
  'monocytes_percent': {
    '%': '%',
  },
  'monocytes_count': {
    'x10^9/L': 'x10^9/L',
    'x10^9/l': 'x10^9/L',
    '10^9/L': 'x10^9/L',
    '10^9/l': 'x10^9/L',
  },
  'eosinophils_percent': {
    '%': '%',
  },
  'eosinophils_count': {
    'x10^9/L': 'x10^9/L',
    'x10^9/l': 'x10^9/L',
    '10^9/L': 'x10^9/L',
    '10^9/l': 'x10^9/L',
  },
  'basophils_percent': {
    '%': '%',
  },
  'basophils_count': {
    'x10^9/L': 'x10^9/L',
    'x10^9/l': 'x10^9/L',
    '10^9/L': 'x10^9/L',
    '10^9/l': 'x10^9/L',
  },
};

final Map<String, LabTest> _labTestsByKey = {
  for (final labTest in labTestCatalogue) labTest.key: labTest,
};

/// The Lab Test with [key], or null when the catalogue has none.
LabTest? labTestByKey(String key) => _labTestsByKey[key];
