// GENERATED FILE — do not edit by hand.
// Regenerate with: node tools/generate-lab-test-catalogue.mjs
//
// Source: packages/lab-catalogue/lab-tests.json, the Lab Test catalogue
// (docs/designs/lab-results.md). The app carries the same entries in
// apps/mobile/lib/domain/labs/lab_test_catalogue.generated.dart; the
// contract-drift gate re-runs the generator and fails when either file is
// stale.

export type LabTestBounds = {
  min: number;
  max: number;
};

export type DefaultRangeSex = "female" | "male" | "any";

export type DefaultRangeSource = {
  title: string;
  url: string;
  version: string;
};

/** Ages are inclusive whole years; a null side is unbounded. */
export type LabTestDefaultRange = {
  sex: DefaultRangeSex;
  ageMin: number | null;
  ageMax: number | null;
  low: number | null;
  high: number | null;
  source: DefaultRangeSource;
};

export type PrintedRangeKind = "reference" | "riskTarget";

export type LabTestEntry = {
  key: string;
  name: string;
  panel: string;
  variants: readonly string[];
  unit: string;
  unitAliases: readonly string[];
  hardBounds: LabTestBounds;
  plausibleBounds: LabTestBounds | null;
  printedRangeKind: PrintedRangeKind;
  defaultRanges: readonly LabTestDefaultRange[];
  /** Each folded spelling of the unit (whitespace removed, case kept) mapped
   * to the canonical unit. */
  foldedUnits: Readonly<Record<string, string>>;
};

/** Every Lab Test, in display order. */
export const LAB_TEST_CATALOGUE: readonly LabTestEntry[] = [
  {
    "key": "testosterone_total",
    "name": "Testosterone",
    "panel": "Sex hormones",
    "variants": [
      "total testosterone",
      "testosterone total",
      "testosterone, total",
      "serum testosterone"
    ],
    "unit": "nmol/L",
    "unitAliases": [
      "nmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "nmol/L": "nmol/L",
      "nmol/l": "nmol/L"
    }
  },
  {
    "key": "testosterone_free_calc",
    "name": "Free testosterone (calculated)",
    "panel": "Sex hormones",
    "variants": [
      "free testosterone",
      "calculated free testosterone",
      "free testosterone calculated",
      "free testosterone (calc)",
      "cft"
    ],
    "unit": "pmol/L",
    "unitAliases": [
      "pmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "pmol/L": "pmol/L",
      "pmol/l": "pmol/L"
    }
  },
  {
    "key": "shbg",
    "name": "SHBG",
    "panel": "Sex hormones",
    "variants": [
      "sex hormone binding globulin",
      "sex hormone-binding globulin"
    ],
    "unit": "nmol/L",
    "unitAliases": [
      "nmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "nmol/L": "nmol/L",
      "nmol/l": "nmol/L"
    }
  },
  {
    "key": "oestradiol",
    "name": "Oestradiol",
    "panel": "Sex hormones",
    "variants": [
      "estradiol",
      "e2",
      "oestradiol (e2)",
      "estradiol (e2)"
    ],
    "unit": "pmol/L",
    "unitAliases": [
      "pmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "pmol/L": "pmol/L",
      "pmol/l": "pmol/L"
    }
  },
  {
    "key": "lh",
    "name": "LH",
    "panel": "Sex hormones",
    "variants": [
      "luteinising hormone",
      "luteinizing hormone"
    ],
    "unit": "IU/L",
    "unitAliases": [
      "IU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "IU/L": "IU/L",
      "IU/l": "IU/L"
    }
  },
  {
    "key": "fsh",
    "name": "FSH",
    "panel": "Sex hormones",
    "variants": [
      "follicle stimulating hormone",
      "follicle-stimulating hormone"
    ],
    "unit": "IU/L",
    "unitAliases": [
      "IU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "IU/L": "IU/L",
      "IU/l": "IU/L"
    }
  },
  {
    "key": "progesterone",
    "name": "Progesterone",
    "panel": "Sex hormones",
    "variants": [
      "serum progesterone",
      "p4"
    ],
    "unit": "nmol/L",
    "unitAliases": [
      "nmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "nmol/L": "nmol/L",
      "nmol/l": "nmol/L"
    }
  },
  {
    "key": "prolactin",
    "name": "Prolactin",
    "panel": "Pituitary and adrenal",
    "variants": [
      "prl",
      "serum prolactin"
    ],
    "unit": "mIU/L",
    "unitAliases": [
      "mIU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "mIU/L": "mIU/L",
      "mIU/l": "mIU/L"
    }
  },
  {
    "key": "cortisol",
    "name": "Cortisol",
    "panel": "Pituitary and adrenal",
    "variants": [
      "serum cortisol",
      "cortisol (am)",
      "morning cortisol"
    ],
    "unit": "nmol/L",
    "unitAliases": [
      "nmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "nmol/L": "nmol/L",
      "nmol/l": "nmol/L"
    }
  },
  {
    "key": "growth_hormone",
    "name": "Growth hormone",
    "panel": "Pituitary and adrenal",
    "variants": [
      "gh",
      "hgh",
      "human growth hormone",
      "somatotropin"
    ],
    "unit": "ug/L",
    "unitAliases": [
      "ug/l",
      "µg/L",
      "µg/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "ug/L": "ug/L",
      "ug/l": "ug/L",
      "µg/L": "ug/L",
      "µg/l": "ug/L"
    }
  },
  {
    "key": "growth_hormone_miu",
    "name": "Growth hormone (mIU/L)",
    "panel": "Pituitary and adrenal",
    "variants": [],
    "unit": "mIU/L",
    "unitAliases": [
      "mIU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "mIU/L": "mIU/L",
      "mIU/l": "mIU/L"
    }
  },
  {
    "key": "igf_1",
    "name": "IGF-1",
    "panel": "Pituitary and adrenal",
    "variants": [
      "igf-1",
      "igf1",
      "igf 1",
      "insulin-like growth factor 1",
      "insulin like growth factor 1",
      "somatomedin c"
    ],
    "unit": "nmol/L",
    "unitAliases": [
      "nmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "nmol/L": "nmol/L",
      "nmol/l": "nmol/L"
    }
  },
  {
    "key": "dhea_s",
    "name": "DHEA-S",
    "panel": "Pituitary and adrenal",
    "variants": [
      "dhea-s",
      "dheas",
      "dhea sulphate",
      "dhea sulfate",
      "dehydroepiandrosterone sulphate",
      "dehydroepiandrosterone sulfate"
    ],
    "unit": "umol/L",
    "unitAliases": [
      "umol/l",
      "µmol/L",
      "µmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "umol/L": "umol/L",
      "umol/l": "umol/L",
      "µmol/L": "umol/L",
      "µmol/l": "umol/L"
    }
  },
  {
    "key": "cholesterol_total",
    "name": "Total cholesterol",
    "panel": "Lipids",
    "variants": [
      "cholesterol",
      "cholesterol total",
      "cholesterol, total",
      "tc"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "riskTarget",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "triglycerides",
    "name": "Triglycerides",
    "panel": "Lipids",
    "variants": [
      "triglyceride",
      "trig",
      "trigs",
      "tg"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "riskTarget",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "hdl_cholesterol",
    "name": "HDL cholesterol",
    "panel": "Lipids",
    "variants": [
      "hdl",
      "hdl-c",
      "hdl-cholesterol",
      "hdl chol",
      "high density lipoprotein cholesterol",
      "high-density lipoprotein cholesterol"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "riskTarget",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "ldl_cholesterol",
    "name": "LDL cholesterol",
    "panel": "Lipids",
    "variants": [
      "ldl",
      "ldl-c",
      "ldl-cholesterol",
      "ldl chol",
      "ldl (calculated)",
      "low density lipoprotein cholesterol",
      "low-density lipoprotein cholesterol"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "riskTarget",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "non_hdl_cholesterol",
    "name": "Non-HDL cholesterol",
    "panel": "Lipids",
    "variants": [
      "non-hdl",
      "non hdl",
      "non-hdl-c",
      "non hdl cholesterol",
      "non-hdl-cholesterol"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "riskTarget",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "cholesterol_hdl_ratio",
    "name": "Cholesterol/HDL ratio",
    "panel": "Lipids",
    "variants": [
      "total/hdl ratio",
      "chol/hdl ratio",
      "tc/hdl ratio",
      "total cholesterol/hdl ratio",
      "cholesterol/hdl",
      "chol/hdl"
    ],
    "unit": "ratio",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 100
    },
    "plausibleBounds": null,
    "printedRangeKind": "riskTarget",
    "defaultRanges": [],
    "foldedUnits": {
      "ratio": "ratio"
    }
  },
  {
    "key": "glucose",
    "name": "Glucose",
    "panel": "Glucose",
    "variants": [
      "blood glucose",
      "plasma glucose",
      "serum glucose",
      "fasting glucose",
      "random glucose",
      "blood sugar",
      "bsl",
      "fbg",
      "fpg"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "hs_crp",
    "name": "hs-CRP",
    "panel": "Inflammation",
    "variants": [
      "hs-crp",
      "hscrp",
      "hs crp",
      "high sensitivity crp",
      "high-sensitivity crp",
      "high sensitivity c-reactive protein",
      "high-sensitivity c-reactive protein",
      "crp (high sensitivity)"
    ],
    "unit": "mg/L",
    "unitAliases": [
      "mg/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "mg/L": "mg/L",
      "mg/l": "mg/L"
    }
  },
  {
    "key": "sodium",
    "name": "Sodium",
    "panel": "Electrolytes",
    "variants": [
      "na",
      "na+",
      "serum sodium"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 27,
      "max": 725
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 135,
        "high": 145,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "potassium",
    "name": "Potassium",
    "panel": "Electrolytes",
    "variants": [
      "k",
      "k+",
      "serum potassium"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 0.7,
      "max": 26
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 3.5,
        "high": 5.2,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "chloride",
    "name": "Chloride",
    "panel": "Electrolytes",
    "variants": [
      "cl",
      "cl-",
      "serum chloride"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 19,
      "max": 550
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 95,
        "high": 110,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "bicarbonate",
    "name": "Bicarbonate",
    "panel": "Electrolytes",
    "variants": [
      "hco3",
      "hco3-",
      "total co2",
      "co2",
      "bicarb"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 4.4,
      "max": 160
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 22,
        "high": 32,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "anion_gap",
    "name": "Anion gap",
    "panel": "Electrolytes",
    "variants": [
      "ag",
      "other anions"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "urea",
    "name": "Urea",
    "panel": "Kidney",
    "variants": [
      "serum urea"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "creatinine",
    "name": "Creatinine",
    "panel": "Kidney",
    "variants": [
      "creat",
      "serum creatinine"
    ],
    "unit": "umol/L",
    "unitAliases": [
      "umol/l",
      "µmol/L",
      "µmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": {
      "min": 9,
      "max": 550
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "female",
        "ageMin": 18,
        "ageMax": 59,
        "low": 45,
        "high": 90,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      },
      {
        "sex": "male",
        "ageMin": 18,
        "ageMax": 59,
        "low": 60,
        "high": 110,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "umol/L": "umol/L",
      "umol/l": "umol/L",
      "µmol/L": "umol/L",
      "µmol/l": "umol/L"
    }
  },
  {
    "key": "egfr",
    "name": "eGFR",
    "panel": "Kidney",
    "variants": [
      "egfr",
      "estimated gfr",
      "estimated glomerular filtration rate",
      "egfr (ckd-epi)"
    ],
    "unit": "mL/min/1.73m²",
    "unitAliases": [
      "mL/min/1.73m2",
      "ml/min/1.73m²",
      "ml/min/1.73m2"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "mL/min/1.73m²": "mL/min/1.73m²",
      "mL/min/1.73m2": "mL/min/1.73m²",
      "ml/min/1.73m²": "mL/min/1.73m²",
      "ml/min/1.73m2": "mL/min/1.73m²"
    }
  },
  {
    "key": "urate",
    "name": "Urate",
    "panel": "Kidney",
    "variants": [
      "uric acid",
      "serum urate"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "bilirubin_total",
    "name": "Total bilirubin",
    "panel": "Liver",
    "variants": [
      "bilirubin",
      "bilirubin total",
      "bilirubin, total",
      "t bili",
      "tbil"
    ],
    "unit": "umol/L",
    "unitAliases": [
      "umol/l",
      "µmol/L",
      "µmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "umol/L": "umol/L",
      "umol/l": "umol/L",
      "µmol/L": "umol/L",
      "µmol/l": "umol/L"
    }
  },
  {
    "key": "alp",
    "name": "ALP",
    "panel": "Liver",
    "variants": [
      "alk phos",
      "alkaline phosphatase",
      "alk phosphatase"
    ],
    "unit": "U/L",
    "unitAliases": [
      "U/l",
      "IU/L",
      "IU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": {
      "min": 6,
      "max": 550
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 22,
        "ageMax": null,
        "low": 30,
        "high": 110,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "U/L": "U/L",
      "U/l": "U/L",
      "IU/L": "U/L",
      "IU/l": "U/L"
    }
  },
  {
    "key": "ggt",
    "name": "GGT",
    "panel": "Liver",
    "variants": [
      "gamma gt",
      "gamma-gt",
      "gamma glutamyl transferase",
      "gamma-glutamyl transferase",
      "ggtp"
    ],
    "unit": "U/L",
    "unitAliases": [
      "U/l",
      "IU/L",
      "IU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "U/L": "U/L",
      "U/l": "U/L",
      "IU/L": "U/L",
      "IU/l": "U/L"
    }
  },
  {
    "key": "alt",
    "name": "ALT",
    "panel": "Liver",
    "variants": [
      "alanine aminotransferase",
      "alanine transaminase",
      "sgpt"
    ],
    "unit": "U/L",
    "unitAliases": [
      "U/l",
      "IU/L",
      "IU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "U/L": "U/L",
      "U/l": "U/L",
      "IU/L": "U/L",
      "IU/l": "U/L"
    }
  },
  {
    "key": "ast",
    "name": "AST",
    "panel": "Liver",
    "variants": [
      "aspartate aminotransferase",
      "aspartate transaminase",
      "sgot"
    ],
    "unit": "U/L",
    "unitAliases": [
      "U/l",
      "IU/L",
      "IU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "U/L": "U/L",
      "U/l": "U/L",
      "IU/L": "U/L",
      "IU/l": "U/L"
    }
  },
  {
    "key": "ld",
    "name": "LD",
    "panel": "Liver",
    "variants": [
      "ldh",
      "lactate dehydrogenase"
    ],
    "unit": "U/L",
    "unitAliases": [
      "U/l",
      "IU/L",
      "IU/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 10000
    },
    "plausibleBounds": {
      "min": 24,
      "max": 1250
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 120,
        "high": 250,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "U/L": "U/L",
      "U/l": "U/L",
      "IU/L": "U/L",
      "IU/l": "U/L"
    }
  },
  {
    "key": "total_protein",
    "name": "Total protein",
    "panel": "Liver",
    "variants": [
      "protein",
      "protein total",
      "protein, total",
      "serum protein"
    ],
    "unit": "g/L",
    "unitAliases": [
      "g/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 12,
      "max": 400
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 60,
        "high": 80,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "g/L": "g/L",
      "g/l": "g/L"
    }
  },
  {
    "key": "albumin",
    "name": "Albumin",
    "panel": "Liver",
    "variants": [
      "alb",
      "serum albumin"
    ],
    "unit": "g/L",
    "unitAliases": [
      "g/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "g/L": "g/L",
      "g/l": "g/L"
    }
  },
  {
    "key": "globulin",
    "name": "Globulin",
    "panel": "Liver",
    "variants": [
      "globulins",
      "serum globulin"
    ],
    "unit": "g/L",
    "unitAliases": [
      "g/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "g/L": "g/L",
      "g/l": "g/L"
    }
  },
  {
    "key": "calcium",
    "name": "Calcium",
    "panel": "Bone and minerals",
    "variants": [
      "ca",
      "total calcium",
      "serum calcium"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 0.42,
      "max": 13
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 2.1,
        "high": 2.6,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "calcium_adjusted",
    "name": "Adjusted calcium",
    "panel": "Bone and minerals",
    "variants": [
      "corrected calcium",
      "calcium (adjusted for albumin)",
      "calcium adjusted",
      "calcium (albumin adjusted)",
      "albumin adjusted calcium",
      "albumin-adjusted calcium",
      "calcium corrected"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 0.42,
      "max": 13
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 2.1,
        "high": 2.6,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "phosphate",
    "name": "Phosphate",
    "panel": "Bone and minerals",
    "variants": [
      "phosphorus",
      "inorganic phosphate",
      "po4",
      "serum phosphate"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 0.15,
      "max": 7.5
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 20,
        "ageMax": null,
        "low": 0.75,
        "high": 1.5,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "magnesium",
    "name": "Magnesium",
    "panel": "Bone and minerals",
    "variants": [
      "mg2+",
      "serum magnesium"
    ],
    "unit": "mmol/L",
    "unitAliases": [
      "mmol/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": {
      "min": 0.14,
      "max": 5.5
    },
    "printedRangeKind": "reference",
    "defaultRanges": [
      {
        "sex": "any",
        "ageMin": 18,
        "ageMax": null,
        "low": 0.7,
        "high": 1.1,
        "source": {
          "title": "Harmonising Adult and Paediatric Reference Intervals in Australia and New Zealand: An Evidence-Based Approach for Establishing a First Panel of Chemistry Analytes",
          "url": "https://pmc.ncbi.nlm.nih.gov/articles/PMC4310061",
          "version": "2014"
        }
      }
    ],
    "foldedUnits": {
      "mmol/L": "mmol/L",
      "mmol/l": "mmol/L"
    }
  },
  {
    "key": "haemoglobin",
    "name": "Haemoglobin",
    "panel": "Full blood count",
    "variants": [
      "hemoglobin",
      "hb",
      "hgb"
    ],
    "unit": "g/L",
    "unitAliases": [
      "g/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "g/L": "g/L",
      "g/l": "g/L"
    }
  },
  {
    "key": "haematocrit",
    "name": "Haematocrit",
    "panel": "Full blood count",
    "variants": [
      "hematocrit",
      "hct",
      "pcv",
      "packed cell volume"
    ],
    "unit": "L/L",
    "unitAliases": [
      "L/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "L/L": "L/L",
      "L/l": "L/L"
    }
  },
  {
    "key": "rcc",
    "name": "Red cell count",
    "panel": "Full blood count",
    "variants": [
      "rcc",
      "rbc",
      "red blood cell count",
      "red blood cells",
      "red cells",
      "erythrocytes"
    ],
    "unit": "x10^12/L",
    "unitAliases": [
      "x10^12/l",
      "10^12/L",
      "10^12/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 100
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "x10^12/L": "x10^12/L",
      "x10^12/l": "x10^12/L",
      "10^12/L": "x10^12/L",
      "10^12/l": "x10^12/L"
    }
  },
  {
    "key": "mcv",
    "name": "MCV",
    "panel": "Full blood count",
    "variants": [
      "mean cell volume",
      "mean corpuscular volume"
    ],
    "unit": "fL",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "fL": "fL"
    }
  },
  {
    "key": "mch",
    "name": "MCH",
    "panel": "Full blood count",
    "variants": [
      "mean cell haemoglobin",
      "mean cell hemoglobin",
      "mean corpuscular haemoglobin",
      "mean corpuscular hemoglobin"
    ],
    "unit": "pg",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "pg": "pg"
    }
  },
  {
    "key": "mchc",
    "name": "MCHC",
    "panel": "Full blood count",
    "variants": [
      "mean cell haemoglobin concentration",
      "mean cell hemoglobin concentration",
      "mean corpuscular haemoglobin concentration",
      "mean corpuscular hemoglobin concentration"
    ],
    "unit": "g/L",
    "unitAliases": [
      "g/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "g/L": "g/L",
      "g/l": "g/L"
    }
  },
  {
    "key": "rdw",
    "name": "RDW",
    "panel": "Full blood count",
    "variants": [
      "red cell distribution width",
      "rdw-cv",
      "rdw cv"
    ],
    "unit": "%",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 100
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "%": "%"
    }
  },
  {
    "key": "wcc",
    "name": "White cell count",
    "panel": "Full blood count",
    "variants": [
      "wcc",
      "wbc",
      "white blood cell count",
      "white blood cells",
      "white cells",
      "leucocytes",
      "leukocytes"
    ],
    "unit": "x10^9/L",
    "unitAliases": [
      "x10^9/l",
      "10^9/L",
      "10^9/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "x10^9/L": "x10^9/L",
      "x10^9/l": "x10^9/L",
      "10^9/L": "x10^9/L",
      "10^9/l": "x10^9/L"
    }
  },
  {
    "key": "platelets",
    "name": "Platelets",
    "panel": "Full blood count",
    "variants": [
      "plt",
      "platelet count",
      "plts"
    ],
    "unit": "x10^9/L",
    "unitAliases": [
      "x10^9/l",
      "10^9/L",
      "10^9/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "x10^9/L": "x10^9/L",
      "x10^9/l": "x10^9/L",
      "10^9/L": "x10^9/L",
      "10^9/l": "x10^9/L"
    }
  },
  {
    "key": "mpv",
    "name": "MPV",
    "panel": "Full blood count",
    "variants": [
      "mean platelet volume"
    ],
    "unit": "fL",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "fL": "fL"
    }
  },
  {
    "key": "neutrophils_percent",
    "name": "Neutrophils %",
    "panel": "Full blood count",
    "variants": [
      "neutrophils %",
      "neutrophils (%)",
      "neutrophil %",
      "% neutrophils",
      "neut %"
    ],
    "unit": "%",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 100
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "%": "%"
    }
  },
  {
    "key": "neutrophils_count",
    "name": "Neutrophils",
    "panel": "Full blood count",
    "variants": [
      "neutrophil count",
      "neutrophils count",
      "absolute neutrophil count",
      "neutrophils (absolute)",
      "neut #",
      "anc"
    ],
    "unit": "x10^9/L",
    "unitAliases": [
      "x10^9/l",
      "10^9/L",
      "10^9/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "x10^9/L": "x10^9/L",
      "x10^9/l": "x10^9/L",
      "10^9/L": "x10^9/L",
      "10^9/l": "x10^9/L"
    }
  },
  {
    "key": "lymphocytes_percent",
    "name": "Lymphocytes %",
    "panel": "Full blood count",
    "variants": [
      "lymphocytes %",
      "lymphocytes (%)",
      "lymphocyte %",
      "% lymphocytes",
      "lymph %"
    ],
    "unit": "%",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 100
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "%": "%"
    }
  },
  {
    "key": "lymphocytes_count",
    "name": "Lymphocytes",
    "panel": "Full blood count",
    "variants": [
      "lymphocyte count",
      "lymphocytes count",
      "absolute lymphocyte count",
      "lymphocytes (absolute)",
      "lymph #"
    ],
    "unit": "x10^9/L",
    "unitAliases": [
      "x10^9/l",
      "10^9/L",
      "10^9/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "x10^9/L": "x10^9/L",
      "x10^9/l": "x10^9/L",
      "10^9/L": "x10^9/L",
      "10^9/l": "x10^9/L"
    }
  },
  {
    "key": "monocytes_percent",
    "name": "Monocytes %",
    "panel": "Full blood count",
    "variants": [
      "monocytes %",
      "monocytes (%)",
      "monocyte %",
      "% monocytes",
      "mono %"
    ],
    "unit": "%",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 100
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "%": "%"
    }
  },
  {
    "key": "monocytes_count",
    "name": "Monocytes",
    "panel": "Full blood count",
    "variants": [
      "monocyte count",
      "monocytes count",
      "absolute monocyte count",
      "monocytes (absolute)",
      "mono #"
    ],
    "unit": "x10^9/L",
    "unitAliases": [
      "x10^9/l",
      "10^9/L",
      "10^9/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "x10^9/L": "x10^9/L",
      "x10^9/l": "x10^9/L",
      "10^9/L": "x10^9/L",
      "10^9/l": "x10^9/L"
    }
  },
  {
    "key": "eosinophils_percent",
    "name": "Eosinophils %",
    "panel": "Full blood count",
    "variants": [
      "eosinophils %",
      "eosinophils (%)",
      "eosinophil %",
      "% eosinophils",
      "eos %"
    ],
    "unit": "%",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 100
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "%": "%"
    }
  },
  {
    "key": "eosinophils_count",
    "name": "Eosinophils",
    "panel": "Full blood count",
    "variants": [
      "eosinophil count",
      "eosinophils count",
      "absolute eosinophil count",
      "eosinophils (absolute)",
      "eos #"
    ],
    "unit": "x10^9/L",
    "unitAliases": [
      "x10^9/l",
      "10^9/L",
      "10^9/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "x10^9/L": "x10^9/L",
      "x10^9/l": "x10^9/L",
      "10^9/L": "x10^9/L",
      "10^9/l": "x10^9/L"
    }
  },
  {
    "key": "basophils_percent",
    "name": "Basophils %",
    "panel": "Full blood count",
    "variants": [
      "basophils %",
      "basophils (%)",
      "basophil %",
      "% basophils",
      "baso %"
    ],
    "unit": "%",
    "unitAliases": [],
    "hardBounds": {
      "min": 0,
      "max": 100
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "%": "%"
    }
  },
  {
    "key": "basophils_count",
    "name": "Basophils",
    "panel": "Full blood count",
    "variants": [
      "basophil count",
      "basophils count",
      "absolute basophil count",
      "basophils (absolute)",
      "baso #"
    ],
    "unit": "x10^9/L",
    "unitAliases": [
      "x10^9/l",
      "10^9/L",
      "10^9/l"
    ],
    "hardBounds": {
      "min": 0,
      "max": 1000
    },
    "plausibleBounds": null,
    "printedRangeKind": "reference",
    "defaultRanges": [],
    "foldedUnits": {
      "x10^9/L": "x10^9/L",
      "x10^9/l": "x10^9/L",
      "10^9/L": "x10^9/L",
      "10^9/l": "x10^9/L"
    }
  }
];

const LAB_TESTS_BY_KEY: ReadonlyMap<string, LabTestEntry> = new Map(
  LAB_TEST_CATALOGUE.map((entry) => [entry.key, entry])
);

/** The Lab Test with `key`, or null when the catalogue has none. */
export function labTestByKey(key: string): LabTestEntry | null {
  return LAB_TESTS_BY_KEY.get(key) ?? null;
}
