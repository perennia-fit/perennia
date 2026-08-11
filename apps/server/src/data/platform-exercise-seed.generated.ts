// GENERATED FILE — do not edit by hand.
// Regenerate with: node tools/generate-server-platform-exercise-seed.mjs
//
// Source: apps/mobile/assets/seeds/platform_exercises.json (wger).
// Only the fields the agent Exercise catalog needs are retained; the Platform
// Library is derived identically to the app (loadMode "added", recordProfile via
// defaultRecordProfileFor). Keep this in sync with the mobile seed — the
// server contract-drift gate re-runs the generator and diffs the result.

import type { DimensionId } from "../analytics/exercise-analytics.js";

export type PlatformSeedCategory = {
  id: string;
  name: string;
};

export type PlatformSeedExercise = {
  id: string;
  name: string;
  dimensionIds: DimensionId[];
  categoryId: string | null;
  equipmentIds: string[];
};

export type PlatformSeedExerciseRedirect = {
  fromExerciseId: string;
  toExerciseId: string;
};

export const PLATFORM_EXERCISE_SEED_CATEGORIES: readonly PlatformSeedCategory[] =
[
  {
    "id": "01910000-0000-7000-8000-000000000007",
    "name": "Chest"
  },
  {
    "id": "01910000-0000-7000-8000-000000000008",
    "name": "Back"
  },
  {
    "id": "01910000-0000-7000-8000-000000000009",
    "name": "Legs"
  },
  {
    "id": "01910000-0000-7000-8000-000000000010",
    "name": "Shoulders"
  },
  {
    "id": "01910000-0000-7000-8000-000000000011",
    "name": "Arms"
  },
  {
    "id": "01910000-0000-7000-8000-000000000012",
    "name": "Core"
  },
  {
    "id": "01910000-0000-7000-8000-000000000013",
    "name": "Calves"
  },
  {
    "id": "01910000-0000-7000-8000-000000000002",
    "name": "Cardio"
  },
  {
    "id": "01910000-0000-7000-8000-000000000004",
    "name": "Running"
  },
  {
    "id": "01910000-0000-7000-8000-000000000005",
    "name": "Cycling"
  },
  {
    "id": "01910000-0000-7000-8000-000000000006",
    "name": "Swimming"
  },
  {
    "id": "01910000-0000-7000-8000-000000000003",
    "name": "Mobility"
  },
  {
    "id": "01910000-0000-7000-8000-000000000001",
    "name": "Strength"
  }
];

export const PLATFORM_EXERCISE_SEED_EXERCISES: readonly PlatformSeedExercise[] =
[
  {
    "id": "01910000-0000-7000-8000-000000200997",
    "name": "4-count burpees",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802107631689",
    "name": "Alternating Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803524639420",
    "name": "Alternating Incline Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800352562855",
    "name": "Assisted Push-Ups with Band (Male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801933113738",
    "name": "Assisted Seated Pectoralis Major Stretch With Stability Ball",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801030197850",
    "name": "Backward Medicine Ball Throw",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803446735132",
    "name": "Banded Push-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802655591484",
    "name": "Barbell Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801704469948",
    "name": "Barbell Decline Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801804954639",
    "name": "Barbell Floor Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200057",
    "name": "Bear Walk 2",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801697903440",
    "name": "Behind Head Chest Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000000102",
    "name": "Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200075",
    "name": "Benchpress Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800440373503",
    "name": "Bent Arm Chest Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201469",
    "name": "Bent over Cable Flye",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801104866502",
    "name": "Board Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200132",
    "name": "Burpees",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200135",
    "name": "Butterfly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200137",
    "name": "Butterfly Narrow Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802217328205",
    "name": "Cable Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201656",
    "name": "Cable Chest Press - Decline",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201660",
    "name": "Cable Chest Press - Incline",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200323",
    "name": "Cable Cross-over",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200924",
    "name": "Cable Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201691",
    "name": "Cable Fly Lower Chest",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201689",
    "name": "Cable Fly Middle Chest",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201690",
    "name": "Cable Fly Upper Chest",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800459493488",
    "name": "Cable Incline Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802412382896",
    "name": "Cable Incline Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801249183465",
    "name": "Cable Incline Fly (on stability ball)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801928194228",
    "name": "Cable Iron Cross",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802576748529",
    "name": "Cable Low Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802085751967",
    "name": "Cable One Arm Incline Fly on Exercise Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803193185369",
    "name": "Cable One Arm Lateral Bent Over",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201457",
    "name": "Cable Press Around",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800238949120",
    "name": "Chest Dip on Straight Bar",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800473385424",
    "name": "Chest Dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200129",
    "name": "Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201554",
    "name": "Clap Push-UP",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800989117358",
    "name": "Clock Push-Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201897",
    "name": "Close-Grip Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201086",
    "name": "Close-grip Press-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200161",
    "name": "Cross-Bench Dumbbell Pullovers",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802205297711",
    "name": "Crucifix Push-Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200186",
    "name": "Decline Bench Press Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803702373418",
    "name": "Decline Dumbbell Bench Press with Neutral Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801025743126",
    "name": "Decline Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200188",
    "name": "Decline Pushups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802505862372",
    "name": "Deep Push-up on Parallel Bars (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201777",
    "name": "Deficit Push ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800609712479",
    "name": "Diamond Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200194",
    "name": "Dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803721719311",
    "name": "Doorway Chest Stretch (male)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201713",
    "name": "Doorway Pectoral Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201676",
    "name": "Dumbbell Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802847579285",
    "name": "Dumbbell Bicep Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201278",
    "name": "Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802668403571",
    "name": "Dumbbell Chest Pull Over",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802877447666",
    "name": "Dumbbell Decline Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804183502470",
    "name": "Dumbbell Decline Twist Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201674",
    "name": "Dumbbell Floor Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800816013790",
    "name": "Dumbbell Flyes on Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201353",
    "name": "Dumbbell Hex Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800839406844",
    "name": "Dumbbell Incline Breeding Chest",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800581293310",
    "name": "Dumbbell Incline Hammer Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801064515418",
    "name": "Dumbbell Incline Palm-in Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800011939536",
    "name": "Dumbbell Lying Hammer Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801847042646",
    "name": "Dumbbell Press on Exercise Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "swissBall",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200801",
    "name": "Dumbbell Push-Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201500",
    "name": "Dumbbell UCV",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201497",
    "name": "Dumbbell Underhand bench press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201496",
    "name": "Dumbbell Upper Chest Variation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803457905262",
    "name": "Dynaband Chest Press",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800683248514",
    "name": "Dynaband Flyes",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201919",
    "name": "Extreme Pec Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802054880692",
    "name": "Flat Cable Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804007379059",
    "name": "Flat Cable Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800617240141",
    "name": "Flat Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800653219678",
    "name": "Flat Dumbbell Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201694",
    "name": "Flat Machine Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201746",
    "name": "Floor dumbbell bench press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200237",
    "name": "Fly With Cable",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200238",
    "name": "Fly With Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200239",
    "name": "Fly With Dumbbells, Decline Bench",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201831",
    "name": "Hammerstrength Decline Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801964722079",
    "name": "High Cable Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201001",
    "name": "High plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201508",
    "name": "High-Incline Smith Machine Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800649842449",
    "name": "Incline Barbell Guillotine Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200538",
    "name": "Incline Bench Press - Barbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200539",
    "name": "Incline Bench Press - MP",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201444",
    "name": "Incline Chest Press Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201276",
    "name": "Incline Dumbbell Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803925904138",
    "name": "Incline Dumbbell Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803111082662",
    "name": "Incline Dumbbell Flyes With A Twist",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201277",
    "name": "Incline Dumbbell Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802066956828",
    "name": "Incline Knee Push-Ups on Box",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200313",
    "name": "Incline Push up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803282717646",
    "name": "Incline Scapula Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201716",
    "name": "Incline Shoulder Press Up",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201692",
    "name": "Incline Smith Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201693",
    "name": "Incline Static Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201198",
    "name": "Inverted Rows",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight",
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200314",
    "name": "Isometric Wipers",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802901460265",
    "name": "Kneeling Knuckle Push-Up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800959548294",
    "name": "Kneeling Modified Hindu Push-up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800082603107",
    "name": "Kneeling One Side Archer Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800344317125",
    "name": "Kneeling Scapular Push-Up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802860914874",
    "name": "Kneeling Side Push-Ups (Semi-Archer)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800225166173",
    "name": "Knuckle Push Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800292927786",
    "name": "Landmine Double Arm Jammer",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201546",
    "name": "Larsen Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803358282232",
    "name": "Laying Svend Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201918",
    "name": "Legend Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201773",
    "name": "Legend Incline Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800926575231",
    "name": "Lever Push-up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803141782441",
    "name": "Leverage Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801379607280",
    "name": "Leverage Decline Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803070962414",
    "name": "Leverage Incline Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200379",
    "name": "Leverage Machine Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201271",
    "name": "Low Pulley Cable fFly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201270",
    "name": "Low Pulley Cable Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201296",
    "name": "Low-Cable Cross-Over - NB",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200926",
    "name": "Machine chest fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201883",
    "name": "Machine Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201655",
    "name": "Machine Chest Press Exercise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "gymMat"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803080750191",
    "name": "Medicine Ball Chest Pass",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802067257043",
    "name": "Medicine Ball Chest Pass against Wall",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803471892704",
    "name": "Medicine Ball Half Kneeling Chest Push (male)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801811063111",
    "name": "Medicine Ball Plyo Push Up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803446317846",
    "name": "Medicine Ball Supine Chest Throw",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801371659462",
    "name": "Modified Hindu Push-up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801508601320",
    "name": "Modified Push Up to Forearms",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200996",
    "name": "Mountain climbers",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804118975114",
    "name": "Narrow Flat Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801905970469",
    "name": "Narrow Grip Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803060514548",
    "name": "Narrow Grip Incline Barbell Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804234692730",
    "name": "Narrow Grip Incline Press Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803547345050",
    "name": "Narrow Grip Press Ups From The Knees",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803537691864",
    "name": "Narrow Incline Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802734055512",
    "name": "Narrow Push Up on Exercise Ball",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201461",
    "name": "No Leg Drive Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200998",
    "name": "No push-up burpees",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201484",
    "name": "Omni Cable Cross-over",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801459934776",
    "name": "One Arm Side Chest Press (male)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802722456307",
    "name": "One-Arm Flat Bench Dumbbell Flye",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802052648986",
    "name": "One-Arm Kettlebell Floor Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200687",
    "name": "Overhead Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200445",
    "name": "Pause Bench",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201904",
    "name": "Pec Deck",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801593167530",
    "name": "Pec Deck Fly Machine Seated",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802737014559",
    "name": "Pike to Cobra Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201436",
    "name": "Pin Bench Press Barbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803785945052",
    "name": "Pin Presses",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800021038563",
    "name": "Planche Dip on Parallel Bars (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803856128360",
    "name": "Plyometric Press Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801286296178",
    "name": "Pompes inclines",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200683",
    "name": "Power Clean",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800267362688",
    "name": "Press Ups From The Knees",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800690584332",
    "name": "Push Up (on stability ball)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801577444339",
    "name": "Push Up Medicine Ball",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801836654735",
    "name": "Push Up to Side Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201675",
    "name": "Push-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201113",
    "name": "Push-Ups | Parallettes",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200498",
    "name": "Reverse Grip Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803764134223",
    "name": "Reverse Grip Incline Press Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800312446477",
    "name": "Reverse Triceps Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800079023772",
    "name": "Ring Archer Push-up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801478997646",
    "name": "Ring Russian Push-Up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201832",
    "name": "Ring Support Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802711975564",
    "name": "Seal Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201094",
    "name": "Seated Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201922",
    "name": "Seated Cable chest fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803018634815",
    "name": "Seated Cable Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800433390983",
    "name": "Seated Cable Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200583",
    "name": "Side to Side Push Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803193500540",
    "name": "Single Arm Cable Crossover",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800019613502",
    "name": "Single Arm Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802368577285",
    "name": "single arm dumbbell floor press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802665984119",
    "name": "Single Arm Incline Dumbbell Chest Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800010923391",
    "name": "Single Arm Scapula Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800529951815",
    "name": "Single-Arm Push-Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802819167803",
    "name": "Smith Machine Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802800222007",
    "name": "Smith Machine Decline Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bench",
      "barbell",
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803765752972",
    "name": "Smith Machine Incline Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "smithMachine",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200925",
    "name": "Smith Machine Slight Incline Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800601545697",
    "name": "Svend Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201451",
    "name": "Torso rotation stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801645821419",
    "name": "TRX Chest Flyes",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801534906993",
    "name": "TRX Chest Press",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802095789032",
    "name": "TRX Press Ups Feet Suspended",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200688",
    "name": "Upper External Oblique",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201902",
    "name": "Weighted push-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804104587513",
    "name": "Wide-Grip Barbell Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800872694132",
    "name": "Wrist Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000007",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201470",
    "name": "1-Arm Half-Kneeling Lat Pulldown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802426121162",
    "name": "Adduction of Arm in Back Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801848204064",
    "name": "Alternating Bent Over Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201486",
    "name": "Alternating High Cable Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800934481004",
    "name": "Alternating Kettlebell Bent Over Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201501",
    "name": "Alternative Dumbbell Gorilla rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800413374575",
    "name": "Archer Pull-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802891502593",
    "name": "Around the World Superman Hold Hips",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201737",
    "name": "Assisted chin-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803349716193",
    "name": "Assisted Pull-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201263",
    "name": "Back bridge",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201143",
    "name": "Back extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803130400090",
    "name": "Back Extension on Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201742",
    "name": "Back Lever",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar",
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201010",
    "name": "Back neck stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201005",
    "name": "Backward shoulder rotation",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800186974526",
    "name": "Band Assisted Chin Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803740612039",
    "name": "Band Assisted Pull Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201380",
    "name": "Band pull-aparts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801745223983",
    "name": "Band Shrug Back",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800379377169",
    "name": "Banded Good Mornings",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201877",
    "name": "Banded Scapular Retraction",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801858184204",
    "name": "Banded Straight Arm Pulldowns",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802673964354",
    "name": "Barbell Back Wide Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803974948080",
    "name": "Barbell Bent Over Wide Row Plus Back",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800438954127",
    "name": "Barbell Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802192772198",
    "name": "Barbell Decline Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803903703727",
    "name": "Barbell Good Morning",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801653692891",
    "name": "Barbell Overhead Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201700",
    "name": "Barbell Romanian Deadlift (RDL)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201698",
    "name": "Barbell Row (Overhand)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201699",
    "name": "Barbell Row (Underhand)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803008643100",
    "name": "Barbell Seated Good Morning",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804024926770",
    "name": "Barbell Seated Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802528988475",
    "name": "Barbell Shrugs",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800794830767",
    "name": "Barbell Shrugs Behind The Back",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801003070331",
    "name": "Barbell Stiff Leg Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801562526096",
    "name": "Barbell Wide Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801796046782",
    "name": "Behind Neck Lat Pull Down Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800234552495",
    "name": "Bench Grab Lean Back Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801119948769",
    "name": "Bent Arm Barbell Pullover",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804147853905",
    "name": "Bent Over Barbell Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201082",
    "name": "Bent over row to external rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200083",
    "name": "Bent Over Rowing",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200084",
    "name": "Bent Over Rowing Reverse",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802105539433",
    "name": "Bent Over Rows Neutral Grip with Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201363",
    "name": "Blackroll",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-804124885565",
    "name": "Bodyweight Lying Prone Ys",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803134962081",
    "name": "Bodyweight Shrug",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802501247680",
    "name": "Bodyweight Standing Scapula Row (male)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201577",
    "name": "Bretzel stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201908",
    "name": "Butterfly Superman",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803226099402",
    "name": "Cable Cross-over Lateral Pulldown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800586349288",
    "name": "Cable High Row kneeling rope attachment",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802423903523",
    "name": "Cable Reverse Grip Straight Back Seated High Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803498948355",
    "name": "Cable Seated Horizontal Shrug (male)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803530389641",
    "name": "Cable Shrugs",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable",
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804034767657",
    "name": "Cambered Bar Lying Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bench",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801096356635",
    "name": "Chest Supported Cable Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201002",
    "name": "Child's pose",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201006",
    "name": "Chin tuck",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200154",
    "name": "Chin-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201015",
    "name": "Clockwise neck circles",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200158",
    "name": "Close-grip Lat Pull Down",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201450",
    "name": "Cobra Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201016",
    "name": "Counterclockwise neck circles",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201458",
    "name": "Cross-Body Cable Y-Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801239171365",
    "name": "Crossfit Pull-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000000103",
    "name": "Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800881721918",
    "name": "Deadlifts from Blocks",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800569939268",
    "name": "Decline Narrow Grip EZ Bar Pullovers",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200189",
    "name": "Deficit Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803076321248",
    "name": "Dumbbell Around Pullover",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201639",
    "name": "Dumbbell Bent Over Face Pull",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800653636218",
    "name": "Dumbbell Bent Over Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800232187676",
    "name": "Dumbbell Decline Shrug Back FIX",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802628099564",
    "name": "Dumbbell Hammer Grip Incline Bench Two Arm Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201087",
    "name": "Dumbbell Hang Power Cleans",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803206430344",
    "name": "Dumbbell Plank to Alternating Row",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201488",
    "name": "Dumbbell Pullover",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803855069807",
    "name": "Dumbbell Pullover on Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "swissBall",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803949356789",
    "name": "Dumbbell Seated Gittleson Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801714571933",
    "name": "Dumbbell Shrugs",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803999677266",
    "name": "Dumbbell Single Arm Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801852231243",
    "name": "Dynaband Deadlifts",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804154087675",
    "name": "Dynaband Rows",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802102237172",
    "name": "Elbow Lift Reverse Push Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201027",
    "name": "Elevated prayer stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201921",
    "name": "Extreme Lat Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201732",
    "name": "Face pulls with yellow/green band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802587258334",
    "name": "Floor Hyperextensions with Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803565786219",
    "name": "Foam Roll Upper Back",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801644885484",
    "name": "Foam Roller on Latissimus Dorsi",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804223198624",
    "name": "Forearm Wall Slide",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201004",
    "name": "Forward shoulder rotation",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201214",
    "name": "Front lever tuck",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201011",
    "name": "Front neck stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200259",
    "name": "Front Pull narrow",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200258",
    "name": "Front pull wide",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200516",
    "name": "Front Wood Chop",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201018",
    "name": "Head tilts",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201303",
    "name": "Helms Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803774644848",
    "name": "High Machine Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201187",
    "name": "High Pull",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201492",
    "name": "High Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803381350752",
    "name": "Hip Crossovers",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200292",
    "name": "Hip Raise, Lying",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801526273720",
    "name": "Hug Knees To Chest Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201487",
    "name": "Hyper Y W Combo",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200301",
    "name": "Hyperextensions",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200828",
    "name": "Incline Bench Reverse Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201283",
    "name": "Incline Chest-Supported Dumbbell Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200310",
    "name": "Incline Dumbbell Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell",
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201927",
    "name": "Inverted Lat Pull Down",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802694023498",
    "name": "Inverted Shrug (on parallel bars)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800079399828",
    "name": "Jumping Pull-up with Back Fix",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800198576359",
    "name": "Kettlebell Bent Over Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201003",
    "name": "Kettlebell deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800107459957",
    "name": "Kettlebell Decline Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800058387636",
    "name": "Kettlebell Good Morning",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800282332212",
    "name": "Kneeling Back-Slump Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804284626848",
    "name": "Kneeling Elastic Front Pull",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802705350838",
    "name": "Kneeling Single Arm High Cable Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201910",
    "name": "Kneeling Superman",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201471",
    "name": "Kroc Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801998060628",
    "name": "Landmine Bent Over Two Arm Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804231041980",
    "name": "Landmine Single Arm Jammer",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803812451792",
    "name": "Landmine T Bar Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201806",
    "name": "Lat Pull Down",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200354",
    "name": "Lat Pull Down (Leaning Back)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200355",
    "name": "Lat Pull Down (Straight Back)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201434",
    "name": "Lat Pull Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201659",
    "name": "Lat Pulldown - Cross Body Single Arm",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801460906669",
    "name": "Lat Stretch Against Wall",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201514",
    "name": "Lateral Walk",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201013",
    "name": "Left levator scapulae stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800937955296",
    "name": "Lever Gripless Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800383610832",
    "name": "Lever Pronated Grip Seated Scapular Retraction Shr",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801713185889",
    "name": "Leverage Iso Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803417418177",
    "name": "Leverage Lat Pulldowns Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200380",
    "name": "Leverage Machine Iso Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801297469389",
    "name": "Leverage Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200394",
    "name": "Long-Pulley (low Row)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200395",
    "name": "Long-Pulley, Narrow",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201348",
    "name": "Lower Back Extensions",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200923",
    "name": "Lying Dumbbell Row Ss Seated Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801095744742",
    "name": "Lying Knee Roll-Over Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800690476020",
    "name": "Lying Prone T Back",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800899238818",
    "name": "Lying Prone W to Y Transition",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802474270945",
    "name": "Lying Reverse Push-up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201304",
    "name": "Meadows Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201635",
    "name": "Modified pulldown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200423",
    "name": "Muscle up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201017",
    "name": "Neck half circles",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803030440794",
    "name": "Negative Pull-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201510",
    "name": "Neutral Grip Lat Pulldown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201186",
    "name": "One Arm Bent Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201701",
    "name": "One-Arm Heavy Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201822",
    "name": "Open Book",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801225548658",
    "name": "Pause Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200448",
    "name": "Pendelay Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800149721193",
    "name": "Pronated Grip Lat Pulldown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800754352064",
    "name": "Prone Bench Row Barbell Supinated Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bench",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200468",
    "name": "Prone Scapular Retraction - Arms at Side",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801806174286",
    "name": "Prone Single Arm Trap Raise",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802053454361",
    "name": "Prone Y Raise (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200477",
    "name": "Pull Ups on Machine",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000104",
    "name": "Pull-Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight",
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201537",
    "name": "Pull-up Isometric Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201696",
    "name": "Pull-Ups (Neutral Grip)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803700671916",
    "name": "Pull-Ups Pronated Grip",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201905",
    "name": "Pullback",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201273",
    "name": "Pullover",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201384",
    "name": "Pullover Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200957",
    "name": "Quadriped Arm and Leg Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201028",
    "name": "Quadruped thoracic rotation left",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201029",
    "name": "Quadruped thoracic rotation right",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200484",
    "name": "Rack Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802507625775",
    "name": "Rack Pulls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "rack"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200490",
    "name": "Renegade Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800355217136",
    "name": "Resistance Band Spider Crawls",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201473",
    "name": "Reverse Cable Flye",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-804224938321",
    "name": "Reverse Grip Bent Over Barbell Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800551953307",
    "name": "Reverse Plank on Elbows",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201215",
    "name": "Reverse Snow Angel",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201433",
    "name": "Reverse Wood Chops",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803546477891",
    "name": "Rickshaw (Trap bar) Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201014",
    "name": "Right levator scapulae stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800263020735",
    "name": "Ring Pull-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801664445050",
    "name": "Rocky Vertical Pulls",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201399",
    "name": "Roll Down",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201634",
    "name": "Rope Pullover/row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200508",
    "name": "Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "dumbbell",
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200512",
    "name": "Rowing seated, narrow grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200674",
    "name": "Rowing with TRX band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200510",
    "name": "Rowing, Lying on Bench",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200513",
    "name": "Rowing, T-bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801239526266",
    "name": "Sandbag Bent Over Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "sandbag"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800535213400",
    "name": "Scapula Dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201435",
    "name": "Scapula Pulls",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801535086143",
    "name": "Scapular Pull Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800662866363",
    "name": "Scapular Slide Back to Wall",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight",
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201207",
    "name": "Scorpion Kick",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803362695420",
    "name": "Seal Row with Barbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803725339606",
    "name": "Seated Band Rows",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200922",
    "name": "Seated Cable Mid Trap Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803496163133",
    "name": "Seated Cable Rope Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200921",
    "name": "Seated Cable Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803075297166",
    "name": "Seated Pulse Back Squeeze",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201098",
    "name": "Seated rear delt rise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802275649255",
    "name": "Seated Rhomboid Stretch (male)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201725",
    "name": "Seated Row (Machine)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802671751632",
    "name": "Seated Row Machine (Neutral Grip)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803785919300",
    "name": "Seated Scapular Retraction with Pronated Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802262396020",
    "name": "Seated Single Arm Cable Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201928",
    "name": "Seated V-Grip Row",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802223700715",
    "name": "Semi-Australian Pull-Ups (Bent Legs)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar",
      "rack"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200562",
    "name": "Shotgun Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803862963675",
    "name": "Shrug on Parallel Bars",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201730",
    "name": "Side Lateral Raise (Cable)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201727",
    "name": "Side Straight-Arm Pulldown (Cable)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201861",
    "name": "Side stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801020974543",
    "name": "Single Arm Kettlebell Hang Cleans",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell",
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800244455966",
    "name": "Single Arm Kettlebell Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803476378179",
    "name": "Single Arm Landmine Bent Over Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801341127401",
    "name": "Single Arm Leverage Iso Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201022",
    "name": "Single Arm Plank to Row",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800055981016",
    "name": "Single Arm Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801673447780",
    "name": "Single-Arm Band Pullover",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201394",
    "name": "Sit & Reach",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "gymMat"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801429252405",
    "name": "Sitting Cross-Legged Reach Forward Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800945516282",
    "name": "Sky Divers",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201210",
    "name": "Skydiver with arms in T-position",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800470260213",
    "name": "Sled Reverse Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "sled"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801082545307",
    "name": "Smith Back Wide Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800169041634",
    "name": "Smith Bent Knee Good Morning Hips",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804059552385",
    "name": "Smith Machine Bent Over Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803494544993",
    "name": "Smith Machine Shrugs Behind The Back",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801086420786",
    "name": "Smith Shrug Back",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201447",
    "name": "Snatch OL",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802584994743",
    "name": "Stiff Leg Dumbbell Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803806203058",
    "name": "Straight Arm Pulldowns Rope - Pullover",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable",
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200628",
    "name": "Straight-arm Pull Down (bar Attachment)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200629",
    "name": "Straight-arm Pull Down (rope Attachment)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201726",
    "name": "Straight-Arm Pulldown (Cable)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200636",
    "name": "Superman",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "gymMat",
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201583",
    "name": "Supine press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802688172824",
    "name": "Swiss Ball Pec Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801934486511",
    "name": "Swiss Ball Spinal Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200919",
    "name": "T-Bar row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201455",
    "name": "Towel Superman",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801166907459",
    "name": "Trap Bar Shrugs",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201834",
    "name": "Trap-3 Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802527662382",
    "name": "TRX External Shoulder Rotation",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802111055352",
    "name": "TRX Pull-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802147364487",
    "name": "TRX Y Rows",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201607",
    "name": "Typewriter Pull-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200684",
    "name": "Underhand Lat Pull Down",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201636",
    "name": "Unilateral Cable row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800433700700",
    "name": "Unilateral High Pulley Row with Chest Support",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201381",
    "name": "Upper Back",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801990369080",
    "name": "V Bar Pulldowns",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200716",
    "name": "Wall Slides",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801988610000",
    "name": "Weighted Hyperextension (on Stability Ball)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800142410595",
    "name": "Wide Grip Lat Pulldown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804150749654",
    "name": "Wide Grip Pull Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201542",
    "name": "Wide Pull Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200723",
    "name": "Wide-grip Pulldown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201244",
    "name": "Yoga exercise: Cow-cat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": [
      "gymMat"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201083",
    "name": "YWTs",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000008",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800604013831",
    "name": "45-Degree Back Extension with Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201096",
    "name": "Abduction while standing",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801051278734",
    "name": "Abductor Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802273467126",
    "name": "Adductor Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801869732825",
    "name": "Adductor stretch side standing",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803656339571",
    "name": "All Fours Quad Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201102",
    "name": "Alternate back lunges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803722525054",
    "name": "Alternating Barbell Curtsy Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801151052724",
    "name": "Alternating Barbell Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803215646117",
    "name": "Alternating Barbell Side Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801641911827",
    "name": "Alternating Bench Glute Kickbacks",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "cable",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803836538906",
    "name": "Alternating Bodyweight Lunges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800506186183",
    "name": "Alternating Dumbbell Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802683732353",
    "name": "Alternating Kettlebell Lunge Pass Through",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800572129637",
    "name": "Alternating Lateral Bodyweight Lunges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804243341065",
    "name": "Alternating Reverse Dumbbell Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804110575043",
    "name": "Alternating Reverse Dumbbell Lunges Off Of A Step",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "step",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201804",
    "name": "ankle dorsiflexion rocks",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201864",
    "name": "Ankle Roll",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801686924894",
    "name": "Assault Treadmill Running",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803750503605",
    "name": "Back and Forward Leg Swings",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801091366296",
    "name": "Backward Run (Plyometrics)",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201865",
    "name": "Banded Ankle Mobility",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201842",
    "name": "Banded Clamshell",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803907845547",
    "name": "Banded Hip Abductions",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803071482269",
    "name": "Banded Hip Thrust",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800882059621",
    "name": "Barbell Front Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801046921272",
    "name": "Barbell Front Squats To A Bench Clean Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bench",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201801",
    "name": "Barbell Full Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200043",
    "name": "Barbell Hack Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200901",
    "name": "Barbell Hip Thrust",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801723927158",
    "name": "Barbell Jefferson Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801641888139",
    "name": "Barbell Lunges (same foot)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200046",
    "name": "Barbell Lunges Standing",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200802",
    "name": "Barbell Lunges Walking",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800971138900",
    "name": "Barbell Overhead Alternating Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801128167297",
    "name": "Barbell Reverse Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803680129222",
    "name": "Barbell Single Leg Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000000101",
    "name": "Barbell Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803323399668",
    "name": "Barbell Squat with Pause",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201830",
    "name": "Barbell Step Back Lunge",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803124302191",
    "name": "Belt Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201840",
    "name": "Bent-Leg Hamstring Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801317919615",
    "name": "Bodyweight Bridges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801412783622",
    "name": "Bodyweight Depth Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803222166234",
    "name": "Bodyweight Glute Kickbacks",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201324",
    "name": "Bodyweight lunge",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801975117882",
    "name": "Bodyweight Pulse Forward Lunge",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802460449852",
    "name": "Bodyweight Pulse Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800694822790",
    "name": "Bodyweight Squat Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801984195389",
    "name": "Bodyweight Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800564470452",
    "name": "Bodyweight Walking Lunges",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800705430868",
    "name": "BOSU - Single Leg Glute Bridges (Foot On Dome)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bosu"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803663899609",
    "name": "BOSU - Squats (On Dome)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bosu"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800708952281",
    "name": "Box Jump",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802173362762",
    "name": "Box Squat with Barbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200124",
    "name": "Braced Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801396134006",
    "name": "Bulgarian Split Squat with Elevated Foot on Box",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell",
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200988",
    "name": "Bulgarian split squats left",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200989",
    "name": "Bulgarian split squats right",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201706",
    "name": "Bulgarian Squat with Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201843",
    "name": "Butterfly Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201769",
    "name": "cabel",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803416199274",
    "name": "Cable Front Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800579774251",
    "name": "Cable Hip Abduction",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803763536454",
    "name": "Cable Kickbacks",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201751",
    "name": "Cable pull through",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201466",
    "name": "Calf Raise using Hack Squat Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201365",
    "name": "Calf Raise with machine (seated)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201854",
    "name": "Calves foam roller",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201911",
    "name": "Cat Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803331925142",
    "name": "Chained Sumo Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201438",
    "name": "Clean",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201605",
    "name": "Copenhagen Adduction Exercise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201407",
    "name": "Cossack squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201400",
    "name": "Crossbody Hamstring Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201395",
    "name": "Crossbody Leg Swings",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803884166272",
    "name": "Curtsy Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802613124361",
    "name": "Degree Leg Press Narrow Stance",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "plate",
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201361",
    "name": "Double Kettlebell Front Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802486115435",
    "name": "Double Leg Butt Kick",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201243",
    "name": "Double Leg Calf Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803850053925",
    "name": "Double Pulse Squat Kickback Plyometrics",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201201",
    "name": "Dragon squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201370",
    "name": "Dumbbell Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201116",
    "name": "Dumbbell farmer's carry",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201503",
    "name": "Dumbbell Frog Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201640",
    "name": "Dumbbell Front Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800425456889",
    "name": "Dumbbell Goblet Box Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801616733243",
    "name": "Dumbbell Goblet Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201614",
    "name": "Dumbbell Hip Thrust",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801055421431",
    "name": "Dumbbell Jump Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200205",
    "name": "Dumbbell Lunges Standing",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201651",
    "name": "Dumbbell Rear Lunge",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801042677228",
    "name": "Dumbbell Romanian Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802260145745",
    "name": "Dumbbell Side Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201653",
    "name": "Dumbbell Side Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201234",
    "name": "Dumbbell Single-leg Hip Thrust",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201366",
    "name": "Dumbbell Split Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802848780575",
    "name": "Dumbbell Squat (back on stability ball wall)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell",
      "wall",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802345910571",
    "name": "Dumbbell Step Ups",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell",
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201088",
    "name": "Dumbbell sumo deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803412252992",
    "name": "Dumbbell Sumo Squat (back on stability ball wall)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802513213238",
    "name": "Dumbbell Sumo Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201684",
    "name": "Dumbbell Thruster",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800131475101",
    "name": "Dumbbell Walking Lunges",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804130949686",
    "name": "Elastic Leg Curl",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201391",
    "name": "Elephant Walks",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801968934050",
    "name": "Exercise Ball Hip Bridge",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802427753214",
    "name": "Exercise Ball Wall Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201241",
    "name": "Exercise Band Dorsiflexion",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201242",
    "name": "Exercise Band Plantarflexion",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800280647145",
    "name": "Foam Roll Adductors",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802685864753",
    "name": "Foam Roll Hamstrings",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800959357545",
    "name": "Foam Roll Iliotibial Band",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201860",
    "name": "Foam Roller Adductors",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201856",
    "name": "Foam Roller Anterior tibialis",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201859",
    "name": "Foam Roller Gluteus",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201857",
    "name": "Foam Roller Iliotibial band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801568122031",
    "name": "Foam Roller on Piriformis",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201858",
    "name": "Foam Roller quadriceps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight",
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201844",
    "name": "Frog Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802021658469",
    "name": "Front Barbell Pause Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200257",
    "name": "Front Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200265",
    "name": "Glute Bridge",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201528",
    "name": "Glute Drive",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201723",
    "name": "Glute Kickback (Machine)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800208935487",
    "name": "Glute Press Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803239375254",
    "name": "Glute Stretch - One Knee To Chest",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801299370820",
    "name": "Glute-Ham Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201392",
    "name": "Good Morning",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804242849007",
    "name": "Good Morning on the Hack Squat Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804149962255",
    "name": "Good Morning Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800410126996",
    "name": "Hack Squat Narrow Stance",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803546366291",
    "name": "Hack Squat Wide Stance",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201414",
    "name": "Hack Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201398",
    "name": "Hamstring Chokes",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201855",
    "name": "Hamstring Foam roller",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201387",
    "name": "Hamstring Kicks",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804027993257",
    "name": "High Grip Dumbbell Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200291",
    "name": "Hindu Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201906",
    "name": "Hip Bridge",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201862",
    "name": "Hip Circles",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802940023187",
    "name": "Hip Circles (Warm-up)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201867",
    "name": "Hip Flexor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201578",
    "name": "Hip hinge",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200294",
    "name": "Hip Thrust",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800248564640",
    "name": "Horizontal Leg Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201846",
    "name": "Horse Stance (Side Splits)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201733",
    "name": "Isometric Squat to Failure",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803847059811",
    "name": "Jerk Dip Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200320",
    "name": "Jumping Jacks",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804003293298",
    "name": "Kettlebell Box Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell",
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803021872701",
    "name": "Kettlebell Front Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802918510679",
    "name": "Kettlebell Goblet Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800402926996",
    "name": "Kettlebell Jump Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201641",
    "name": "Kettlebell One Legged Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell",
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800164773923",
    "name": "Kettlebell Pistol Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201612",
    "name": "kettlebell sumo deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802804736768",
    "name": "Kettlebell Sumo Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201688",
    "name": "Kickstand RDL",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801578341695",
    "name": "Knee Circles",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201452",
    "name": "Knee to Chest Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800454472793",
    "name": "Kneeling Adductor Backward Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803910929252",
    "name": "Kneeling Forward Hip Circles",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803085423969",
    "name": "Kneeling Hip Flexor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802662689419",
    "name": "Kneeling Hip Thrusts",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200990",
    "name": "Kneeling kickbacks",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800980906564",
    "name": "Kneeling Quad Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802635869003",
    "name": "Kneeling Reach Forward Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800437938137",
    "name": "Kneeling Resistance Band Kickback",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801547567891",
    "name": "Kneeling Squat Jump",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802357198133",
    "name": "Kneeling Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201829",
    "name": "Landmine Squat to Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803242720739",
    "name": "Lateral Band Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801028383142",
    "name": "Lateral Band Squat Steps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801501714506",
    "name": "Lateral Band Walk",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801721922351",
    "name": "Lateral Bounds",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800351594505",
    "name": "Lateral Cone Hops",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803900495296",
    "name": "Lateral Elastic Kickback (Kneeling)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201325",
    "name": "Lateral Push Off",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802378772503",
    "name": "Laying Hamstring Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200364",
    "name": "Leg Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200365",
    "name": "Leg Curls (laying)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200366",
    "name": "Leg Curls (sitting)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200367",
    "name": "Leg Curls (standing)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200369",
    "name": "Leg Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200371",
    "name": "Leg Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801539998806",
    "name": "Leg Press (Single Leg)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801700810672",
    "name": "Leg Press Machine - Normal Stance",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200375",
    "name": "Leg Press on Hack Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201515",
    "name": "Leg Press Toe Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200373",
    "name": "Leg Presses (narrow)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200374",
    "name": "Leg Presses (wide)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200376",
    "name": "Leg Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201670",
    "name": "Leg Swings (Front-Back)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200397",
    "name": "Low Box Squat - Wide Stance",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201868",
    "name": "Lunge with Twist Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200984",
    "name": "Lunges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802849544495",
    "name": "Lying Alternate Toe Touch Floor",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201869",
    "name": "Lying Figure Four Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800700740073",
    "name": "Lying Hamstring Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201870",
    "name": "Lying Hamstring Stretch with Band",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800719503485",
    "name": "Lying Hip Abduction with Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201871",
    "name": "Lying Knee to Chest Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802703228633",
    "name": "Lying Leg Resting Glute Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802450915034",
    "name": "Lying Prone Quadriceps Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803512623920",
    "name": "Lying Side Leg Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201748",
    "name": "Machine Hip Abduction",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-804111850421",
    "name": "Marching in Place",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800259399158",
    "name": "Medicine Ball Single Leg Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801980796859",
    "name": "Medicine Ball Single Leg Wood Chop",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802779139960",
    "name": "Mountain Climber Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801906652361",
    "name": "Narrow Stance Bodyweight Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800550633178",
    "name": "Narrow Stance Leg Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200910",
    "name": "Nordic Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801902038802",
    "name": "Nordic Leg Curl with Resistance Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800924100537",
    "name": "One Leg Quarter Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200441",
    "name": "Overhead Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201464",
    "name": "Pause Hack Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201521",
    "name": "Pendular hack",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201527",
    "name": "Pendulum Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201872",
    "name": "Pigeon Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201437",
    "name": "Pin Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200456",
    "name": "Pistol Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201020",
    "name": "Pistol squats right",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201410",
    "name": "Plank with Alternating Leg Lift",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201275",
    "name": "Plantarflexion Stretch with Band",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800728862725",
    "name": "Plyo Side Lunge Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802832112694",
    "name": "Plyo/Cardio Lunges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803898675378",
    "name": "Power Snatch",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801766240025",
    "name": "Prisoner Squat Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800465159831",
    "name": "Prisoner Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201873",
    "name": "Quad Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801596386203",
    "name": "Resistance Band Reverse Hyper with Stability Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201809",
    "name": "Reverse Hyperextension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200999",
    "name": "Reverse lunges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800325828453",
    "name": "Reverse Lunges with Front Foot Elevated",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell",
      "step"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200909",
    "name": "Reverse Nordic Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201750",
    "name": "Romanian Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201211",
    "name": "Romanian deadlift, single leg",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell",
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201613",
    "name": "rubber band glute kickback",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201874",
    "name": "Runners Lunge Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800349425515",
    "name": "Running in Place",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803688180271",
    "name": "Sandbag - Alternating Static Side Lunges (Front)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "sandbag"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801595312410",
    "name": "Sandbag Squat Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801715930945",
    "name": "Seated Band Hip Abduction",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801633070032",
    "name": "Seated cross leg glute stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201680",
    "name": "seated figure four",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201672",
    "name": "Seated Hip Abduction",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200012",
    "name": "Seated Hip Adduction",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802821067928",
    "name": "Seated Leg Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201845",
    "name": "Seated Pancake Good Morning",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804005679258",
    "name": "Seated Single Leg Hamstring Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800871512438",
    "name": "Seated Wide Legged Adductor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201884",
    "name": "Shinbox IR Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201739",
    "name": "Shrimp Squad",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201202",
    "name": "Side Lying Hip Abduction",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801531678669",
    "name": "Side Lying Outward Knee Kick",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201195",
    "name": "Side Slides + Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200986",
    "name": "Side split squats left",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200987",
    "name": "Side split squats right",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804134221884",
    "name": "Side to Side Box Shuffle",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800334467866",
    "name": "Side-Lying Quad Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804209658792",
    "name": "Single Arm Kettlebell Overhead Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801528016828",
    "name": "Single Leg Bodyweight Bridges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803419947860",
    "name": "Single Leg Box Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800112716646",
    "name": "Single Leg Dumbbell Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200071",
    "name": "Single Leg Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803324704931",
    "name": "Single Leg Extension (on stability ball)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201740",
    "name": "Single Leg Glute Bridge",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801950100776",
    "name": "Single Leg Good Morning with Bosu",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bosu"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201393",
    "name": "Single Leg Hamstring Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800339623224",
    "name": "Single Leg Leg Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803949031834",
    "name": "Single Leg Push-off",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "step"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201388",
    "name": "Single Leg RDL",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201736",
    "name": "Single-Leg Deadlift with Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803643072906",
    "name": "Single-Leg Extension with Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804068387685",
    "name": "Single-leg Football Kick with Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800138880786",
    "name": "Single-Leg High Box Squat (Bulgarian style)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201734",
    "name": "Single-Leg Lunge with Kettlebell:",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800710383815",
    "name": "Single-Leg Lying Hamstring Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201735",
    "name": "Single-leg side glute press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804205962802",
    "name": "Single-Leg Squat with Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801587587030",
    "name": "Sissy Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201494",
    "name": "Sitting Calf Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201274",
    "name": "Sitting Calf Stretch (Dorsiflexion)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800441363294",
    "name": "Skater Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803526232048",
    "name": "Sled One Leg Press (Hips)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201604",
    "name": "Sliding Lateral Lunge",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801375627681",
    "name": "Sliding Leg Curl on Floor with Towel",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802490182244",
    "name": "Slingshot Glute Bridges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802527710077",
    "name": "Smith Machine Alternating Reverse Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "step",
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802616504692",
    "name": "Smith Machine Bulgarian Split Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "box",
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801292002974",
    "name": "Smith Machine Hip Thrust",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bench",
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802200153372",
    "name": "Smith Machine Leg Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801469077402",
    "name": "Smith Machine Pistol Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201593",
    "name": "Smith Machine Split Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201747",
    "name": "Smith machine squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803897178806",
    "name": "Smith Machine Static Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800543611005",
    "name": "Smith Machine Stiff Leg Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201576",
    "name": "Snap Down",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800878500396",
    "name": "Snatch Balance",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201839",
    "name": "Solo Hip Flexor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200604",
    "name": "Speed Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200991",
    "name": "Split squats left",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200992",
    "name": "Split squats right",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200614",
    "name": "Squat Jumps",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803584566703",
    "name": "Squat Jumps (Barbell)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801763309745",
    "name": "Squat Jumps on a Box",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200616",
    "name": "Squat Thrust",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200615",
    "name": "Squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200341",
    "name": "Squats on Multipress",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800228797395",
    "name": "Stability Ball Reverse Hyperextension (off a bench)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801219464208",
    "name": "Stability Ball Single Leg Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201724",
    "name": "Standing Adduction (Cable)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201239",
    "name": "Standing Calf Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800860838992",
    "name": "Standing Cross-Legged Hamstring Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800690321044",
    "name": "Standing Hamstring Curl Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802877985067",
    "name": "Standing High-Leg Bent Knee Hamstring Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201875",
    "name": "Standing IT Band Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803519162132",
    "name": "Standing Knee To Chest Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802375772607",
    "name": "Standing Leg Resting Buttocks Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201396",
    "name": "Standing Pancake",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201397",
    "name": "Standing Pancake Good Morning",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803496280997",
    "name": "Standing Reach Down Hamstring",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201240",
    "name": "Standing Soleus Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802096590347",
    "name": "Standing Wide-Legged Adductor Stretch (Toes Pointed Forward)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800507957669",
    "name": "Static Bodyweight Lunges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801328497287",
    "name": "Static Dumbbell Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800132285993",
    "name": "Step Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "step",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800588064119",
    "name": "Step Up With Knee Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "step",
      "box",
      "dumbbell",
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800320928290",
    "name": "Stiff Leg Dead from a Deficit",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200627",
    "name": "Stiff-legged Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800831525890",
    "name": "Straight Leg Bodyweight Glute Kickbacks",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200630",
    "name": "Sumo Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200632",
    "name": "Sumo Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201886",
    "name": "Supine Hip Abduction",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800066492661",
    "name": "Swiss Ball Hip Thrust",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200650",
    "name": "Thruster",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201390",
    "name": "Toe Touch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201803",
    "name": "Trap Bar Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-804258285349",
    "name": "TRX Bulgarian Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802644539736",
    "name": "TRX Curtsy Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802941951789",
    "name": "TRX Glute Bridges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803710484723",
    "name": "TRX Hamstring Curls",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803341814049",
    "name": "TRX Pistol Squat Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802198769617",
    "name": "TRX Single Leg Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800006831089",
    "name": "TRX Squats",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801413544220",
    "name": "Unilateral Band Kickback",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800955331713",
    "name": "Unilateral Barbell Hip Thrust",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bench",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201913",
    "name": "Unilateral Hip Thrust",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201907",
    "name": "Unilateral Lunges",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802899497374",
    "name": "Walking - Treadmill",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802403273007",
    "name": "Walking Incline on Treadmill",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201903",
    "name": "Walking Lunges",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201100",
    "name": "Wall balls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201196",
    "name": "Wall Drills",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200718",
    "name": "Wall Squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201408",
    "name": "Wall-sit",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803662178945",
    "name": "Warming up in Lunge (five)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802216678151",
    "name": "Warming up in Lunge (four)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802975821079",
    "name": "Warming up in Lunge (one)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803901984078",
    "name": "Warming up in Lunge (six)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802452508766",
    "name": "Warming up in Lunge (three)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801526838004",
    "name": "Warrior III Pose",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803549318475",
    "name": "Warrior Pose II (Virabhadrasana II)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200722",
    "name": "Weighted Step-ups",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-804221596873",
    "name": "Wide Legged Side Fold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802985656478",
    "name": "Zercher Squat",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000009",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803004670418",
    "name": "Alternating Arm Circles (Warm-up)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800060384538",
    "name": "Alternating Front Incline Dumbbell Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802030762258",
    "name": "Alternating Front Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804223762365",
    "name": "Alternating Seated Dumbbell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801705732767",
    "name": "Arm Circles",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802388609650",
    "name": "Arm-Up Rotator Cuff Stretch (With Stick)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200020",
    "name": "Arnold Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201826",
    "name": "Band pull-apart with external rotation",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801717662110",
    "name": "Band Shoulder Adduction",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800535232523",
    "name": "Banded Front Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800753065011",
    "name": "Banded Lat Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201838",
    "name": "Banded Shoulder Drills",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803695092143",
    "name": "Banded Upright Rows",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802028726968",
    "name": "Barbell Front Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801941152988",
    "name": "Barbell Rear Delt Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800880214366",
    "name": "Barbell Shoulder Press (Behind The Head)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201925",
    "name": "Barbell Silverback Shrug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201807",
    "name": "Behind the Back Cable Lateral Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802670003629",
    "name": "Bent Arm Circles (Warm-up)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200079",
    "name": "Bent High Pulls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803731017476",
    "name": "Bent Over Rear Delt Fly Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803032390451",
    "name": "Bent Over Single Arm Low Cable Rear Delt Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200082",
    "name": "Bent-over Lateral Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200915",
    "name": "Bus Drivers",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201710",
    "name": "Butchers Block Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200139",
    "name": "Butterfly Reverse",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200142",
    "name": "Cable External Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802047968984",
    "name": "Cable Front Delt Raise Lying On A Bench",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable",
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201745",
    "name": "Cable Front Raise with a small bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803227065885",
    "name": "Cable Front Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800411249227",
    "name": "Cable Internal Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803066935450",
    "name": "Cable Lateral Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201378",
    "name": "Cable Lateral Raises (Single Arm)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200822",
    "name": "Cable Rear Delt Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801845420103",
    "name": "Cable Rear Delt Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201936",
    "name": "Cable Rear-Delt Fly (single arm)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800092468685",
    "name": "Cable Seated Neck Extension (with head harness)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803471482785",
    "name": "Cable Seated Neck Flexion (with head harness)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201472",
    "name": "Cable Shrug-In",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801549952869",
    "name": "Cable Upright Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201774",
    "name": "Chair dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800266299322",
    "name": "Chest Supported Cable Face Pulls Handles",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "cable",
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802467650121",
    "name": "Chest Supported Dumbbell Front Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800085683804",
    "name": "Chest Supported Dumbbell Rear Delt Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803410903036",
    "name": "Chest Supported Dumbbell Rear Delt Flyes Overhand Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803656665689",
    "name": "Chest Supported EZ Bar Front Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201825",
    "name": "Chest-Supported Rear Delt Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803845119543",
    "name": "Chin To Chest Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201446",
    "name": "Clean and Jerk OL",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201901",
    "name": "Clean and Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802168733643",
    "name": "Criss Cross Upper Chest Raise (male)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803124236484",
    "name": "Cuban Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802560075570",
    "name": "Decline Diamond Pike Push Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201754",
    "name": "Degree lateral raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201536",
    "name": "Delt Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201556",
    "name": "Devil's Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200193",
    "name": "Diagonal Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801840009757",
    "name": "Double Kettlebell Cleans",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801157873318",
    "name": "Double Kettlebell Hang Cleans",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801918435657",
    "name": "Double Kettlebell Push Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801815629451",
    "name": "Double Kettlebell Split Jerk",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201504",
    "name": "Dumbbell Bradford press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800597688161",
    "name": "Dumbbell Clean & Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802642997122",
    "name": "Dumbbell External Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802587433996",
    "name": "Dumbbell Internal & External Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802811506887",
    "name": "Dumbbell Iron Cross",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800892680922",
    "name": "Dumbbell Lying One Arm Rear Lateral Raise on bench",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201227",
    "name": "Dumbbell rear delt row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201602",
    "name": "Dumbbell Scaption",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802644234196",
    "name": "Dumbbell Seated Alternate Front Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201429",
    "name": "Dumbbell Shoulder Rotations",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800642779103",
    "name": "Dumbbell Upright Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802245794519",
    "name": "Dumbbell W Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803959259772",
    "name": "Dynaband External Rotations",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802274189997",
    "name": "Dynaband Rear Delt Flyes",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802661395807",
    "name": "Dynaband Shoulder Press",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802060928928",
    "name": "Elbow Circles (Warm-Up)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201835",
    "name": "External Rotation Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201920",
    "name": "Extreme Shoulder Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801815901643",
    "name": "EZ Bar Upright Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "ezBar",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800293367129",
    "name": "Facepulls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable",
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201833",
    "name": "Floor Glider Hamstring Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803024082751",
    "name": "Front Incline Dumbbell Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200827",
    "name": "Front Plate Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200256",
    "name": "Front Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200254",
    "name": "Front Raises with Plates",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801631603825",
    "name": "Frontal Horizontal Pull with Elastic Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801078991168",
    "name": "Full Lateral Raises with Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201516",
    "name": "Handstand",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800827812954",
    "name": "Handstand Push Up (female) Upper Arms",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800798645447",
    "name": "Handstand Push-up against the Wall (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804038341039",
    "name": "Handstand Push-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800908061418",
    "name": "Handstand Walk",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201007",
    "name": "Head turns",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802876450774",
    "name": "High Dumbbell Internal & External Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201882",
    "name": "High-Cable Lateral Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201080",
    "name": "Hindu Pushups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201712",
    "name": "Horizontal Shoulder Flexion Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201879",
    "name": "Incline Dumbbell Y-Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201441",
    "name": "Incline OHP Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201445",
    "name": "Jerk OL",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803746491795",
    "name": "Kettlebell Upright Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801995066679",
    "name": "Kipping Handstand Push Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804203130942",
    "name": "Kneeling Pike Push-up (on Bench)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201442",
    "name": "Kreis Press Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200346",
    "name": "Landmine press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801122035296",
    "name": "Lateral Raise Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200348",
    "name": "Lateral Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200349",
    "name": "Lateral Rows on Cable, One Armed",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200351",
    "name": "Lateral-to-Front Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201008",
    "name": "Left neck stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800604139476",
    "name": "Left Side Neck Flexion (plate-loaded)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803098871444",
    "name": "Leverage Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804040435563",
    "name": "Lying Face Up Plate Neck Resistance",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200406",
    "name": "Lying Rotator Cuff Exercise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800077940285",
    "name": "Lying Scalene Muscles Activation (female)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201654",
    "name": "Machine lateral wise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "gymMat"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201744",
    "name": "Machine Side Lateral Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801106941261",
    "name": "Medicine Ball Around Head Rotation (Shoulders)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803653571406",
    "name": "Medicine Ball Rotational Throw",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200418",
    "name": "Military Press mit SZ-Bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802359659636",
    "name": "Neck Bridge Prone",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803988041776",
    "name": "Neck Circles (Warm-up)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802826037592",
    "name": "Neck Extension Lying with Weights",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803427080053",
    "name": "Neck Side Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201893",
    "name": "Overhead Barbell Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201775",
    "name": "Pec deck rear delt fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201580",
    "name": "Perpendicular Unilateral Landmine Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804087219200",
    "name": "Pike Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800155431893",
    "name": "Pike Push-up (on Bench)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802293255772",
    "name": "Pike Push-up from Deficit (Male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201439",
    "name": "Pin OHP",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802762428034",
    "name": "Plate Bus Driver",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802455781203",
    "name": "Plate-Loaded Neck Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801075530902",
    "name": "Prone Cervical Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201284",
    "name": "Pseudo Planche Push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201440",
    "name": "Push OHP",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200478",
    "name": "Push Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801143477932",
    "name": "Rear Delt Pull-Aparts with Resistance Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200487",
    "name": "Rear Delt Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803912767208",
    "name": "Reverse Fly",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201709",
    "name": "Reverse Fly Standing",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201009",
    "name": "Right neck stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801623885286",
    "name": "Ring Handstand (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803054658882",
    "name": "Roll Neck Decompress Lying on Floor",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800225672048",
    "name": "Roll Neck Rotation Lying on Floor (female)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800879440017",
    "name": "Rotating Neck Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801796944468",
    "name": "Sandbag - Overhead Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "sandbag"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201338",
    "name": "Schoulder Raise (Dumbbell)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803365479649",
    "name": "Seated Arnold Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800060126510",
    "name": "Seated Barbell Shoulder Press (Behind the Neck)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803667855449",
    "name": "Seated Dumbbell Front Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803549774856",
    "name": "Seated Dumbbell Lat Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801010055428",
    "name": "Seated Dumbbell Lateral Raises on Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800012263714",
    "name": "Seated Dumbbell Military Press on Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "swissBall",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804113441413",
    "name": "Seated Dumbbell One Arm Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800171589598",
    "name": "Seated Dumbbell Rear Delt Flyes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801845867378",
    "name": "Seated Dumbbell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200918",
    "name": "Seated Dumbbell Side Lateral",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800707746869",
    "name": "Seated Kettlebell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201841",
    "name": "Seated Shoulder Extension Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800452300880",
    "name": "Seated Shoulder Press (Barbell)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801677648626",
    "name": "Seated Single Arm Dumbbell Lat Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802254831038",
    "name": "Seated Single Arm Kettlebell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201081",
    "name": "Shoulder dislocates",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201714",
    "name": "Shoulder Dumbbell Pendular Exercise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201729",
    "name": "Shoulder External Rotation (Cable)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201715",
    "name": "Shoulder External Rotation with Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201728",
    "name": "Shoulder Internal Rotation (Cable)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200566",
    "name": "Shoulder Press, Barbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200543",
    "name": "Shoulder Press, on Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200569",
    "name": "Shoulder Press, on Multi Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201443",
    "name": "Shoulder Raise Side and Front Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200570",
    "name": "Shoulder Shrug",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803099161817",
    "name": "Shoulder Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800213851384",
    "name": "Shoulder Stretch with Band Behind the Back",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801982581270",
    "name": "Shoulder Tap at Waist",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201755",
    "name": "Shoulder Y-pull cable",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200575",
    "name": "Shrugs on Multipress",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201753",
    "name": "Side lateral raise - Back (Cable)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201752",
    "name": "Side lateral raise - Front (Cable)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800007088405",
    "name": "Side Laterals to Front Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201582",
    "name": "Side-laying interior rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell",
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200578",
    "name": "Side-lying External Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803458124239",
    "name": "Simultaneous Arm Circles (Warm-Up)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802028003935",
    "name": "Single Arm Cable Lat Raises Behind The Back",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803941550450",
    "name": "Single Arm Kettlebell Push Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803387506248",
    "name": "Single Arm Kettlebell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803742017094",
    "name": "Single Arm Lateral Raise Against Bench",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800045321996",
    "name": "Single Arm Seated Dumbbell Shoulder Press Neutral Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800760456335",
    "name": "Single Arm Standing Dumbbell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802106796897",
    "name": "Sitting Neck Stretch (female)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201711",
    "name": "Sleeper Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801508607518",
    "name": "Smith Machine Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bench",
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802372546146",
    "name": "Smith Machine Shoulder Press Behind The Head",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "smithMachine",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801016010938",
    "name": "Smith Machine Upright Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200916",
    "name": "Smith Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803327516575",
    "name": "Standing Alternating Cable Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803021398919",
    "name": "Standing Barbell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201575",
    "name": "Standing Dowel Shoulder press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804151557938",
    "name": "Standing Dumbbell Arnold Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804097861690",
    "name": "Standing Dumbbell Lat Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800686520677",
    "name": "Standing Dumbbell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803283375764",
    "name": "Standing Dumbbell Straight-Arm Front Delt Raise Above Head",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800163276298",
    "name": "Standing Front Raise Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801545918256",
    "name": "Standing Neutral Grip Dumbbell Shoulder Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802072925853",
    "name": "Standing Rear Delt Flyes Head Against Bench Overhand Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800603570718",
    "name": "Standing Rear Delt Rows Head Against Bench",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800846854919",
    "name": "Standing Side Neck Stretch (female)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200917",
    "name": "Straight Bar Cable Front Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802039797826",
    "name": "Strongman Crucifix Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802826502426",
    "name": "Strongman Front Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803190153343",
    "name": "Strongman Iron Block Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201581",
    "name": "Trap press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell",
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201916",
    "name": "Tuck planche",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201795",
    "name": "unilateral cross body cable pull down",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801543039701",
    "name": "Upright Barbell Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200694",
    "name": "Upright Row with Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200691",
    "name": "Upright Row, on Multi Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200693",
    "name": "Upright Row, SZ-bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201679",
    "name": "Wall Angels",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200711",
    "name": "Wall Handstand",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800138153024",
    "name": "Weighted Lying Neck Extension (with head harness)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801313902045",
    "name": "Weighted Lying Side Neck Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802024849177",
    "name": "Weighted Seated Neck Extension (with head harness)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803529962627",
    "name": "Wide Grip Upright Barbell Rows",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804098465071",
    "name": "Y Press with Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201885",
    "name": "YTWL Exercise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000010",
    "equipmentIds": [
      "dumbbell",
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802557093341",
    "name": "Alternate Incline Bicep Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201012",
    "name": "Alternating bicep curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201192",
    "name": "Alternating Biceps Curls With Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201567",
    "name": "Alternating dumbbell hammer curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801289556877",
    "name": "Alternating Zottman Preacher Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201606",
    "name": "Arm Raises (T/Y/I)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201219",
    "name": "Australian pull-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200031",
    "name": "Axe Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200995",
    "name": "Backward arm circles",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803354077161",
    "name": "Band Reverse Wrist Curl",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804108055262",
    "name": "Band Wrist Curl",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803801529542",
    "name": "Banded Skull Crushers",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800283127409",
    "name": "Banded Tricep Extensions",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801924561099",
    "name": "Barbell Behind Back Finger Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803619362867",
    "name": "Barbell Biceps Curl (with arm blaster)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803864255952",
    "name": "Barbell Drag Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803154224196",
    "name": "Barbell Incline Reverse Grip Spider Curl with Chest Support",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800716911912",
    "name": "Barbell Lying Triceps Skull Crushers",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800451978957",
    "name": "Barbell Preacher Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803772542688",
    "name": "Barbell Reverse Preacher Curl Forearms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802136574913",
    "name": "Barbell Reverse Spider Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200048",
    "name": "Barbell Reverse Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801874867554",
    "name": "Barbell Reverse Wrist Curl II (Forearms)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804155893368",
    "name": "Barbell Standing Back Wrist Curl Forearms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800378482010",
    "name": "Barbell Standing Concentration Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802566377365",
    "name": "Barbell Standing Wide Grip Biceps Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802213394220",
    "name": "Barbell Standing Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802363148879",
    "name": "Barbell Standing Wrist Reverse Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200050",
    "name": "Barbell Triceps Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200051",
    "name": "Barbell Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201493",
    "name": "Bayesian Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801786103132",
    "name": "Bench Dip (knees bent)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201320",
    "name": "Bench Dips On Floor",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800522692286",
    "name": "Bent Over Tricep Kickbacks",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201768",
    "name": "bicep",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802378381798",
    "name": "Bicep Foam Roller",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802446045022",
    "name": "Bicep Stretch Against A Wall",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201280",
    "name": "Biceps Close Grip Pull Down",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801987361112",
    "name": "Biceps Curl Cable with Bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "cable",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201424",
    "name": "Biceps Curl Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200095",
    "name": "Biceps Curl With Cable",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200091",
    "name": "Biceps Curls With Barbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200092",
    "name": "Biceps Curls With Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200094",
    "name": "Biceps Curls With SZ-bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201483",
    "name": "Bizeps Curls Trifecta",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200112",
    "name": "Body-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201608",
    "name": "Bodyweight Biceps Curl",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800393961253",
    "name": "Bodyweight Triceps Extension",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803890416286",
    "name": "Brachialis Pull Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201109",
    "name": "Cable Concentration Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201531",
    "name": "Cable Curls",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800819148740",
    "name": "Cable Hammer Curls Rope",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800955456327",
    "name": "Cable Incline Pushdown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804178375628",
    "name": "Cable One Arm Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802846244724",
    "name": "Cable Preacher Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803219578235",
    "name": "Cable Reverse Preacher Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "ezBar",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803512613409",
    "name": "Cable Reverse Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800767746077",
    "name": "Cable Skull Crushers",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801318045571",
    "name": "Cable Standing Back Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801207261163",
    "name": "Cable Standing Pulldown Forearms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802875856810",
    "name": "Cable Standing Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802348478088",
    "name": "Cable Standing Wrist Reverse Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201665",
    "name": "Cable Tri Extension - External Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201662",
    "name": "Cable Tri Extension - Internal Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201509",
    "name": "Cable Tricep Kickback",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803886778203",
    "name": "Cable Tricep Push Down V Bar Attachment",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201661",
    "name": "Cable Triceps Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803148727100",
    "name": "Cable Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801048098544",
    "name": "Cable Wrist Curl (Forearm)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801722523067",
    "name": "Chest Supported Cable Tricep Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "bench",
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201223",
    "name": "Claps over the head",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802328870100",
    "name": "Close-Grip Standing Barbell Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201649",
    "name": "Concentration Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800768855771",
    "name": "Concentration Curls with Dumbbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800124055537",
    "name": "Cross Body Hammer Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201666",
    "name": "Curl - With Shoulder Elevated",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200974",
    "name": "Curl with kettlebell two hands",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801830807322",
    "name": "Dead Hang Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200182",
    "name": "Deadhang",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800334835389",
    "name": "Decline Bar Skullcrushers",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800914053413",
    "name": "Decline Narrow Grip EZ Bar Tricep Extensions Behind The Head",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200197",
    "name": "Dips Between Two Benches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201360",
    "name": "Double Kettlebell Clean and Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201481",
    "name": "Drag Pushdown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201512",
    "name": "Drop Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803024308009",
    "name": "Dumbbell Ball Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800337709597",
    "name": "Dumbbell Behind Back Finger Curl (female)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802037391407",
    "name": "Dumbbell Bent Over Curl (male)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201226",
    "name": "Dumbbell bicep curl to press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201482",
    "name": "Dumbbell Cheat Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201228",
    "name": "Dumbbell close grip bench press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200202",
    "name": "Dumbbell Concentration Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800426044957",
    "name": "Dumbbell Concentration Curls Hammer",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201502",
    "name": "Dumbbell Cross Body Hammer Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201931",
    "name": "Dumbbell Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802711977390",
    "name": "Dumbbell Drag Curl (VERSION 2)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201224",
    "name": "Dumbbell drag curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802723682929",
    "name": "Dumbbell Finger Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800753830214",
    "name": "Dumbbell Finger Curls Behind the Back",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802410525185",
    "name": "Dumbbell Hammer Curls (with arm blaster)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802205244079",
    "name": "Dumbbell Hammer Spider Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803582938815",
    "name": "Dumbbell High Curl for Upper Arms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200204",
    "name": "Dumbbell Incline Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801022667934",
    "name": "Dumbbell Lunge with Bicep Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800101508184",
    "name": "Dumbbell Lying Pronation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800324555074",
    "name": "Dumbbell Lying Supine Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800686598150",
    "name": "Dumbbell One Arm Concentration Curl on Stability Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803661337939",
    "name": "Dumbbell One Arm Seated Neutral Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801629050758",
    "name": "Dumbbell Over Bench One Arm Neutral Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801285413734",
    "name": "Dumbbell Over Bench Reverse Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801869809333",
    "name": "Dumbbell Overhead Extension Seated",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802685885564",
    "name": "Dumbbell Reverse Spider Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802164629257",
    "name": "Dumbbell Reverse Spider Curl Upper Arms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800360010217",
    "name": "Dumbbell Seated Drag Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800740985515",
    "name": "Dumbbell Seated Preacher Curl Upper Arms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802226033446",
    "name": "Dumbbell Seated Reverse Grip Concentration Curl (Forearms)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804051664667",
    "name": "Dumbbell Single Spider Curl with Chest Support",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800092115548",
    "name": "Dumbbell Skull Crusher",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801577202453",
    "name": "Dumbbell Standing Back Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802838584582",
    "name": "Dumbbell Standing Drag Curl (VERSION 2)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801929510161",
    "name": "Dumbbell Standing Hands Torsion (male) Forearms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803361920311",
    "name": "Dumbbell Standing One Arm Concentration Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800978274095",
    "name": "Dumbbell Standing Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801734991833",
    "name": "Dumbbell Standing Wrist Reverse Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200211",
    "name": "Dumbbell Triceps Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802737325411",
    "name": "Dumbbell Two Arm Seated Hammer Curl on Exercise Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201463",
    "name": "Dumbbell Underhand Dead Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801605457023",
    "name": "Dumbbell Waiter Biceps Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201225",
    "name": "Dumbbell wide bicep curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201881",
    "name": "Dumbbell Wrist Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200208",
    "name": "Dumbbells on Scott Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201824",
    "name": "Dumbell Tate Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802583536798",
    "name": "Dynaband Overhead Tricep Extensions",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201498",
    "name": "Elbows Tucked Dumbbell Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803076545834",
    "name": "Exercise Ball Supine Triceps Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "swissBall",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804267254562",
    "name": "EZ Bar Biceps Curl (with Arm Blaster)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801697900898",
    "name": "EZ Bar Deadlift with Bicep Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802394517512",
    "name": "EZ Bar Preacher Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801732953903",
    "name": "EZ Bar Seated Wrist Reverse Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803993888807",
    "name": "EZ Barbell Reverse grip Preacher Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801151583520",
    "name": "EZ Barbell Spider Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802015381099",
    "name": "EZ Barbell Standing Back Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801755639246",
    "name": "EZ Barbell Standing Preacher Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800947095868",
    "name": "EZ Barbell Standing Single Arm Neutral Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802223888743",
    "name": "EZ Barbell Standing Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803116816234",
    "name": "EZ Barbell Standing Wrist Reverse Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201297",
    "name": "EZ-Bar Skullcrusher - NB",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803824836381",
    "name": "Feet Elevated Bench Dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802579021891",
    "name": "Finger Flexor Stretch (Forearms)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201217",
    "name": "Finger Pushup",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200820",
    "name": "Fingerboard 20 mm edge",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800639763673",
    "name": "Fingers Down Forearm Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201000",
    "name": "Floor dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201468",
    "name": "Floor Skull Crusher",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201333",
    "name": "Forearm Curls (underhand grip)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801782630087",
    "name": "Forearm Pronator Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200994",
    "name": "Forward arm circles",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201686",
    "name": "Glute Bridge Single-Arm Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200272",
    "name": "Hammer Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200275",
    "name": "Hammercurls on Cable",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200279",
    "name": "Hand Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800688134835",
    "name": "Hand Spring Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201298",
    "name": "High-Cable Cross Tricep Extention - NB",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803543969390",
    "name": "Incline Alternating Hammer Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800854189841",
    "name": "Incline Barbell Skull Crushers",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801267348761",
    "name": "Incline Bench Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800085094982",
    "name": "Incline Cable Skull Crushers with Bar Attachment",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201467",
    "name": "Incline Close Grip Barbell Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801204899570",
    "name": "Incline Dumbbell Curl on Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801390402235",
    "name": "Incline Dumbbell Tricep Extensions",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801656856603",
    "name": "Incline Finger Press",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200911",
    "name": "Incline Skull Crush",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800947739938",
    "name": "Incline Wide Grip EZ Bar Tricep Extensions Behind The Head",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar",
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800548345714",
    "name": "Inversed dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201302",
    "name": "JM Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802985841536",
    "name": "Kettlebell Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201218",
    "name": "knee push-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801714903567",
    "name": "Kneeling Cable Tricep Extensions Over the Head",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "ezBar",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800459949152",
    "name": "Kneeling Finger Press (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800666964053",
    "name": "Kneeling Fist Roll (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804179218183",
    "name": "Kneeling Forearm Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802751484438",
    "name": "Kneeling Tricep Kickbacks",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803349884144",
    "name": "Kneeling Wrist Flexor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801434819277",
    "name": "Kneeling Wrist Sinkers",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201511",
    "name": "Kong Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201741",
    "name": "L-Sit Pull-ups",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight",
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800153477285",
    "name": "Lever Gripper Hands (plate loaded)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802980476946",
    "name": "Low Pulley EZ Bar Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "ezBar",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201535",
    "name": "lying bicep curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201530",
    "name": "Lying Dumbbell Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804209096718",
    "name": "Lying Dumbbell Tricep Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804068289709",
    "name": "Lying High Bench Barbell Curls (Spider curl)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201480",
    "name": "Lying Triceps Extensions",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201490",
    "name": "Lying Triceps Kickback",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800220022708",
    "name": "Narrow Grip Barbell Tricep Press To Chin",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803255922572",
    "name": "Narrow Grip EZ Bar Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201717",
    "name": "Neck extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800162199686",
    "name": "Negative Biceps Leg Concentration Curl Upper Arms",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201738",
    "name": "Neutral-grip pull-ups or TRX rows",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201668",
    "name": "One Arm Overhead Cable Tricep Extension",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802025103516",
    "name": "One Arm Supinated Dumbbell Triceps Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200803",
    "name": "One Arm Triceps Extensions on Cable",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803459347416",
    "name": "One-Arm Chin",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200975",
    "name": "one-handed kettlebell curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201513",
    "name": "Overhead Cable Tricep Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201519",
    "name": "Overhead Triceps Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803026314742",
    "name": "Palms Up Barbell Wrist Curls Over A Bench",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802786221362",
    "name": "Palms-Out Forearm Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201808",
    "name": "Parallel Bar Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802148595192",
    "name": "Plate Pinch",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201430",
    "name": "Plate Pinch Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201658",
    "name": "Preacher Curl - Externally Rotated",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201657",
    "name": "Preacher Curl - Internally Rotated",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200465",
    "name": "Preacher Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200821",
    "name": "Pullup on fingerboard",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201462",
    "name": "punches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200985",
    "name": "Push-up rotations",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201216",
    "name": "Recruitment Pulls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201114",
    "name": "Rest (for timed workouts)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200493",
    "name": "Reverse Bar Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200495",
    "name": "Reverse Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200914",
    "name": "Reverse EZ Bar Cable Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201290",
    "name": "Reverse Grip Barbell Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802569756512",
    "name": "Reverse Grip Cable Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802674431864",
    "name": "Reverse Grip Dumbbell Preacher Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803980601464",
    "name": "Reverse Grip EZ Bar Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803661437794",
    "name": "Reverse Grip Tricep Pushdowns",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200913",
    "name": "Reverse Preacher Curl (Close Grip)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801855437253",
    "name": "Reverse Wrist Curl at Low Pulley",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200501",
    "name": "Ring Dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201485",
    "name": "Rocking Triceps Pushdown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800433626263",
    "name": "Roll Forearms Standing Against Wall (female)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803454690556",
    "name": "Seated Alternate Rotating Bicep Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803855536220",
    "name": "Seated Alternating Hammer Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800644182772",
    "name": "Seated Concentration Curl with EZ-Bar, Close Grip",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800376751348",
    "name": "Seated Concentration Curl with Narrow Grip Barbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201289",
    "name": "Seated Dumbbell Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801818648952",
    "name": "Seated Dumbbell Inner Biceps Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800015380618",
    "name": "Seated Hammer Curl with Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801593621341",
    "name": "Seated Hammer Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802175238599",
    "name": "Seated Single Arm Dumbbell Overhead Tricep Extensions",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802682869601",
    "name": "Seated Single Arm Tricep Kickbacks",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801350822745",
    "name": "Seated Single Arm Wrist Curls Palm Up",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201749",
    "name": "Seated Triceps Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201448",
    "name": "Seated W Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803966219175",
    "name": "Seated Wrist Curl with Straight Bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201337",
    "name": "Shoulder Press (Dumbbell)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201209",
    "name": "Shoulder width three-point push-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802088617407",
    "name": "Side Lying Single Arm Triceps Push-up (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802698600538",
    "name": "Simultaneous Zotman Curls with Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803734001598",
    "name": "Single Arm Cable Curls Handle",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804059890397",
    "name": "Single Arm Cable Tricep Extensions",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802460741167",
    "name": "Single Arm Dumbbell Preacher Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803037259898",
    "name": "Single Arm Preacher Curl Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802505910660",
    "name": "Single Arm Wrist Curls Over A Bench Palm Down",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803801748923",
    "name": "Single Arm Wrist Curls Over A Bench Palm Up",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200584",
    "name": "Single-arm Preacher Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200245",
    "name": "Skullcrusher Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200246",
    "name": "Skullcrusher SZ-bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bench",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801867844641",
    "name": "Sled Overhead Tricep Extensions",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "sled"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200804",
    "name": "Sloper hanging",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200598",
    "name": "Smith Machine Close-grip Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802756248321",
    "name": "Smith Seated Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802085286903",
    "name": "Smith Standing Back Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201465",
    "name": "Spider Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802973075160",
    "name": "Spider Curl with Pronated Grip and Straight Bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801735189064",
    "name": "Standing Alternate Hammer Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804098096798",
    "name": "Standing Alternate Rotating Bicep Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801465741991",
    "name": "Standing Barbell Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200621",
    "name": "Standing Bicep Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201232",
    "name": "Standing biceps stretch left",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201233",
    "name": "Standing biceps stretch right",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802713200026",
    "name": "Standing Dumbbell Inner Bicep Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801237340147",
    "name": "Standing Dumbbell Reverse Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802533608222",
    "name": "Standing Hammer Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800950208766",
    "name": "Standing Narrow Grip EZ Bar Overhead Tricep Extensions",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "ezBar",
      "barbell",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200623",
    "name": "Standing Rope Forearm",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802058858035",
    "name": "Standing Tricep Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804094450074",
    "name": "Standing Wrist Rotation",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200912",
    "name": "Straight Bar Cable Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800684822795",
    "name": "Tate Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200655",
    "name": "Tricep Dumbbell Kickback",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800011399761",
    "name": "Tricep Extension (Rope)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "cable",
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801407995167",
    "name": "Tricep Press Down Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200805",
    "name": "Tricep Pushdown on Cable",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201900",
    "name": "Tricep Rope Pushdowns",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801742658394",
    "name": "Tricep Stretch - Against A Wall",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201372",
    "name": "Triceps Dips (Assisted)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200659",
    "name": "Triceps Extensions on Cable",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200660",
    "name": "Triceps Extensions on Cable With Bar",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200661",
    "name": "Triceps on Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201336",
    "name": "Triceps Overhead (Dumbbell)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800184718934",
    "name": "Triceps Press",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201185",
    "name": "Triceps Pushdown",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201230",
    "name": "Triceps stretch left",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201231",
    "name": "Triceps stretch right",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803989590051",
    "name": "TRX Bicep Curl",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201269",
    "name": "TRX dips",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201261",
    "name": "TRX gorilla biceps curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201260",
    "name": "TRX hammer curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201262",
    "name": "Trx Single Arm Bicep Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201266",
    "name": "TRX Tricep Extension",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802352587904",
    "name": "Unilateral Tricep Press Down Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803637412309",
    "name": "Wall Flexors Stretch (Forearms)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200713",
    "name": "Wall Pushup",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802380305184",
    "name": "Weighted Seated One Arm Reverse Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802292865106",
    "name": "Weighted Seated One Arm Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800739063572",
    "name": "Weighted Seated Reverse Wrist Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802120790111",
    "name": "Weighted Seated Supination for Forearms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800129209549",
    "name": "Weighted Standing Curl for Forearms",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801160514721",
    "name": "Wide Grip EZ Bar Curls",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803835820987",
    "name": "Wrist Circles",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801921399465",
    "name": "Wrist Circles (Warm-up)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201205",
    "name": "Wrist curl, dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802502845463",
    "name": "Wrist Curls with Neutral Grip Plate",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803079663162",
    "name": "Wrist Extensor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800981041847",
    "name": "Wrist Flexor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801556665539",
    "name": "Wrist Radial Deviator And Extensor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803342595654",
    "name": "Wrist Radial Deviator And Flexor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-804264741451",
    "name": "Wrist Roller (Andrieu)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803783049872",
    "name": "Wrist Ulnar Deviator And Flexor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201683",
    "name": "Zottman curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000011",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802208171065",
    "name": "3:4 Sit Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201573",
    "name": "Ab wheel",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201933",
    "name": "Abdominal Crunch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "gymMat"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801682119223",
    "name": "Abdominal Crunches Machine",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201828",
    "name": "Abdominal Draw-In",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200056",
    "name": "Abdominal Stabilization",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "gymMat"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802797714815",
    "name": "Air Bike Crunches",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803011302914",
    "name": "Alternating Heel Touches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803567677421",
    "name": "Alternating V-Up with Medicine Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802926206172",
    "name": "Back Supported Hanging Leg Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200165",
    "name": "Ball crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803905591937",
    "name": "Band Airbike",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200041",
    "name": "Barbell Ab Rollout",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801553349156",
    "name": "Barbell Press Sit-Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "barbell",
      "ezBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800140834243",
    "name": "Barbell Roll-Out",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801918580211",
    "name": "Barbell Seated Twist (on stability ball)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall",
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201687",
    "name": "Bear crawl pull through",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800378424150",
    "name": "Bench Tuck Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801177775955",
    "name": "Bent Knee Hip Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200958",
    "name": "Biceps with TRX",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201412",
    "name": "bicycle crunches",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803821539553",
    "name": "Bicycle Twisting Crunch",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201572",
    "name": "Bird Dog",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201475",
    "name": "Black Widow Knee Slides",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800390977274",
    "name": "BOSU - Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bosu"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800750648148",
    "name": "BOSU - Side Plank (Feet On Dome)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bosu"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800854234647",
    "name": "Bottoms Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200977",
    "name": "Box squat",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201476",
    "name": "Butterfly Sit Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800771888341",
    "name": "Cable Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803355480662",
    "name": "Cable Reverse Crunch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800345425435",
    "name": "Cable Russian Twists (on stability ball)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200145",
    "name": "Cable Woodchoppers",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802173871388",
    "name": "Cable Woodchops",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201823",
    "name": "Clamshell",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801665962001",
    "name": "Cocoons",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200980",
    "name": "commando pull-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201912",
    "name": "Core Rotation",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802273653763",
    "name": "Cross Body Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801731549124",
    "name": "Crunch (Legs on Exercise Ball - Swiss Ball)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800898150297",
    "name": "Crunch (on Swiss Ball)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804071924137",
    "name": "Crunch with Medicine Ball",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201319",
    "name": "Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200172",
    "name": "Crunches on Machine",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200173",
    "name": "Crunches With Cable",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200174",
    "name": "Crunches With Legs Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200178",
    "name": "Deadbug",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201889",
    "name": "Decline Bench Leg Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802839878137",
    "name": "Decline Oblique Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804174879861",
    "name": "Declined Crunch lower cable",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201827",
    "name": "Double-Leg Abdominal Press",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "gymMat",
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201409",
    "name": "Dragon-flag",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800663886043",
    "name": "Dragonfly Bent Knees",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201415",
    "name": "Dumbbell Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800569942380",
    "name": "Dumbbell Seated Tuck Twisting Crunch on Floor",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803879678608",
    "name": "Dumbbell Side Bends",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201286",
    "name": "Dynamic Planche",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201099",
    "name": "Dynamic side hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802978387040",
    "name": "Exercise Ball Ab Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803684054841",
    "name": "Exercise Ball Torso Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800457048127",
    "name": "Flat Bench Lying Leg Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200235",
    "name": "Flutter Kicks",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804024615044",
    "name": "Frog Sit Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201238",
    "name": "Frog stand",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201245",
    "name": "Front Lever",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight",
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201252",
    "name": "Front lever pull-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802254225719",
    "name": "Front Lever Reps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201307",
    "name": "Front Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803702150094",
    "name": "Full Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200260",
    "name": "Full Sit Outs",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200009",
    "name": "Handed Kettlebell Swing",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800703004640",
    "name": "Hanging Knee Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200283",
    "name": "Hanging Leg Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803168793311",
    "name": "Hanging Oblique Knee Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201411",
    "name": "Heel Touches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200297",
    "name": "Hollow Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "gymMat",
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201101",
    "name": "Horizontal traction isometry",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201248",
    "name": "Ice Scream maker",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200171",
    "name": "Incline Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "inclineBench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800269727957",
    "name": "Incline Leg Hip Raise (leg straight)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200312",
    "name": "Incline Plank With Alternate Floor Touch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800058413297",
    "name": "Janda Sit-Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200960",
    "name": "Kettlebell Swing",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200978",
    "name": "Knee Raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200382",
    "name": "L Hold",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201852",
    "name": "L-sit",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201853",
    "name": "L-Sit (Foot Supported)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801406691097",
    "name": "Landmine 180",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201779",
    "name": "Landmine Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200979",
    "name": "Leg raises pull up bar",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200378",
    "name": "Leg Raises, Standing",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201909",
    "name": "Leg Wheel",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201478",
    "name": "Levitation Crunch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803477529463",
    "name": "Lying Crossover",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800626910352",
    "name": "Lying Leg Lift",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201313",
    "name": "Lying Leg Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200976",
    "name": "Medicine ball booklet crunch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802752583043",
    "name": "Medicine Ball Full Twist",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800515075445",
    "name": "Medicine Ball Lying Leg Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803621822400",
    "name": "Medicine Ball Sit-up (wall)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "medicineBall",
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201089",
    "name": "Medicine ball twist",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803541116275",
    "name": "Mountain Climber Cross Cardio",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200427",
    "name": "Negative Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802089522975",
    "name": "Oblique Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201293",
    "name": "One armed push-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802942402385",
    "name": "Otis Ups",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200439",
    "name": "Overhand Cable Curl",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201194",
    "name": "Pallof Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000105",
    "name": "Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802800305350",
    "name": "Plank Feet On An Exercise Ball",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800900634995",
    "name": "Plank in push-up position with hands on an exercise ball",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201489",
    "name": "Plank Jacks",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201766",
    "name": "Plank Reach",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800491196623",
    "name": "Plank Shoulder Tap",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803648826694",
    "name": "Plank to Pike",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800280494816",
    "name": "Plank with Hip Lift",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800658585384",
    "name": "Plank With Rotation",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201406",
    "name": "Plank-to-Elbow Extension",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201079",
    "name": "Plate twist",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "gymMat"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803598183887",
    "name": "Pulse Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201287",
    "name": "Reach ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803237493683",
    "name": "Reaching Lateral Side Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800163955782",
    "name": "Reverse Cable Woodchop",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802942379039",
    "name": "Reverse Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802940117321",
    "name": "Reverse Crunches with Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200500",
    "name": "Reverse Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200505",
    "name": "Roman Chair",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201374",
    "name": "Rotary Torso Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201193",
    "name": "Russian Twist",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell",
      "gymMat",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801062597061",
    "name": "Russian Twist on Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802644653445",
    "name": "Scissor Kicks",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200545",
    "name": "Scissors",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201477",
    "name": "Seated Corkscrew",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801611220887",
    "name": "Seated In-Out Leg Raise on Floor",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201105",
    "name": "Seated Knee Tuck",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803153077937",
    "name": "Side Bend on Stability Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200556",
    "name": "Side Bends on Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200576",
    "name": "Side Crunch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "gymMat"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200577",
    "name": "Side Dumbbell Trunk Flexion",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802173279077",
    "name": "Side Jackknife",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201321",
    "name": "Side Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201019",
    "name": "Side plank right",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800002551710",
    "name": "Single Arm High Pulley Cable Side Bends",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201479",
    "name": "Sit Up Elbow Thrust",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200591",
    "name": "Sit-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201810",
    "name": "Sphinx",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801987832933",
    "name": "Spider Plank (female)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200607",
    "name": "Splinter Sit-ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803525521711",
    "name": "Stability Ball Rollout on Knees",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802352950783",
    "name": "Stability Ball Rounded Rollout (female)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803522705097",
    "name": "Standing Barbell Twist",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800568929357",
    "name": "Standing Cable Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803368623436",
    "name": "Standing Cable Russian Twists",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "cable"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201426",
    "name": "Standing Side Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801205281667",
    "name": "Stomach Vacuum",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201847",
    "name": "Straddle L-Sit",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201776",
    "name": "Suitcase Carry",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802115902107",
    "name": "Supine Twist with Bent Knees on Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800879368672",
    "name": "Supine Twist with Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800730798789",
    "name": "Swiss Ball Jackknife",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800781919146",
    "name": "Swiss Ball Side Bend",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801105633356",
    "name": "Swiss Ball Sit-up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201425",
    "name": "Toe Taps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803175951056",
    "name": "Toe Touches for abs",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201529",
    "name": "Toes to bar",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201377",
    "name": "Torso Twist",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200672",
    "name": "Trunk Rotation With Cable",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-804129167175",
    "name": "TRX Atomic Abs",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803501071341",
    "name": "TRX Fallouts",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804034538587",
    "name": "TRX Jackknife",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800706067167",
    "name": "TRX Mountain Climbers",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201259",
    "name": "TRX Obliques",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803588172571",
    "name": "TRX Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201246",
    "name": "TRX roll out",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200959",
    "name": "TRX Rows",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800801632825",
    "name": "TRX Side Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201704",
    "name": "Tuck L-sit",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200675",
    "name": "Turkish Get-Up",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803843576701",
    "name": "Twisting Crunch (Straight Arms)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804242893361",
    "name": "V Sit Rotation",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "kettlebell",
      "plate",
      "medicineBall",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802898803846",
    "name": "V Ups",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801283666619",
    "name": "V-Sit Twist (Medicine Ball)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803425957229",
    "name": "V-Up with Swiss Ball",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201090",
    "name": "Vpushup",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201474",
    "name": "W-Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201103",
    "name": "walking bridge",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803807041640",
    "name": "Weighted Crunches",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "dumbbell",
      "plate",
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802545613883",
    "name": "Weighted Decline Crunch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800808521049",
    "name": "Weighted Floor Twisting Crunch Feet on Bench",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803030636770",
    "name": "Weighted Front Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "plate",
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801008649019",
    "name": "Weighted Overhead Crunch (on Stability Ball)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801532262695",
    "name": "Weighted Seated Twist (on Stability Ball)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "swissBall",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800848190669",
    "name": "Weighted Twisting Crunch (on bench)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201743",
    "name": "Windshield Wipers",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000012",
    "equipmentIds": [
      "pullUpBar",
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800359892085",
    "name": "Ankle Circles",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802287135851",
    "name": "Anterior Tibialis Massage with Foam Roller",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803400088680",
    "name": "Arnold Calf Raises (Donkey Calf)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "step"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803091163332",
    "name": "Barbell Seated Calf Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "barbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802092358380",
    "name": "Calf Massage with Foam Roller",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200146",
    "name": "Calf Press Using Leg Press Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200148",
    "name": "Calf Raises on Hack Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800366182008",
    "name": "Calf Raises on Hack Squat Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803864477669",
    "name": "Calf Raises On Leg Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201203",
    "name": "Calf raises, left leg",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200702",
    "name": "Calf raises, one legged",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201021",
    "name": "Calf raises, right leg",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801368080261",
    "name": "Calf Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801804528440",
    "name": "Calf Stretch With Hands Against Wall",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "wall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802982340411",
    "name": "Dumbbell Calf Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801293221152",
    "name": "Exercise Ball on the Wall Calf Raise (tennis ball between knees)",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "wall",
      "swissBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803688556620",
    "name": "Foam Roll Peroneals",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802978108889",
    "name": "Horizontal Leg Press Calf Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804202597318",
    "name": "Jump Rope",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803341814971",
    "name": "Kneeling Ankle Stretch and Mobility",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201603",
    "name": "Leg curl with elastic",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800024818232",
    "name": "One-Leg Calf Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201915",
    "name": "Quadruped Hip Abduction",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "band",
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802133571846",
    "name": "Quick Mini Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800619094256",
    "name": "Rocking Standing Calf Raise",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803165716777",
    "name": "Seated Calf Raise Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "machine",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803989867955",
    "name": "Seated Calf Raises on Smith Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802773650144",
    "name": "Seated Calf Raises Toes Out",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803363948977",
    "name": "Seated Calf Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201620",
    "name": "Seated Dumbbell Calf Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802645991666",
    "name": "Seated Toe Pull Calf Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800070349431",
    "name": "Shin Roller Massage (Foam Roller)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "foamRoll"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802290958085",
    "name": "Single Leg Dumbbell Seated Calf Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "dumbbell",
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801880439908",
    "name": "Single-Leg Dumbbell Calf Raise",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802642822720",
    "name": "Smith Machine Calf Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "smithMachine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802207192665",
    "name": "Standing Calf Raise Machine",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200622",
    "name": "Standing Calf Raises",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802473902450",
    "name": "Stepper",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201876",
    "name": "Supported Calf Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201200",
    "name": "Tibialis raises",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000013",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201092",
    "name": "Bag training",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201525",
    "name": "Ball Slams",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201524",
    "name": "Battle Ropes",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-803706703744",
    "name": "Bench Hops",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bench"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201630",
    "name": "Blaze",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bench",
      "dumbbell",
      "kettlebell",
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803640906982",
    "name": "Boxing",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201579",
    "name": "Bronco",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803065585458",
    "name": "Burpee with push up and front jump",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201449",
    "name": "ClimbMill",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201204",
    "name": "Cycling cardio session",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200962",
    "name": "Elliptical",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801572298641",
    "name": "Elliptical Trainer",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801245237116",
    "name": "Hand Bike",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200285",
    "name": "High Knee Jumps",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201318",
    "name": "High Knee Skips",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200983",
    "name": "High knees",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803492493764",
    "name": "Jack Burpee (male)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200319",
    "name": "Jogging",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200993",
    "name": "Jump rope: basic jumps",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801623019817",
    "name": "Jumping Jack with Resistance Band",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201584",
    "name": "March or jog in place",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201376",
    "name": "Recumbent Bike",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201093",
    "name": "Rowing Machine",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000000106",
    "name": "Run",
    "dimensionIds": [
      "duration",
      "distance"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200529",
    "name": "Run - Interval Training",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200530",
    "name": "Run - Treadmill",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802949073473",
    "name": "Running on a Treadmill",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804198967387",
    "name": "Seated Battle Rope",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000201526",
    "name": "Ski Machine",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801036215431",
    "name": "SkiErg",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200595",
    "name": "Skipping - Standard",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201523",
    "name": "Sled Push",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201549",
    "name": "Stair Master",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight",
      "machine"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200624",
    "name": "Stationary Bike",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200927",
    "name": "Suspended crossess",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000200961",
    "name": "Swimming 50m sprints",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201615",
    "name": "Treadmill Cardio",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000000107",
    "name": "Walk",
    "dimensionIds": [
      "duration",
      "distance"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000201104",
    "name": "Walking",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802414084776",
    "name": "Wind Bike",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000200908",
    "name": "Zone 2 Running",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000002",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000110",
    "name": "Road Running",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000004",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000109",
    "name": "Running",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000004",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000000113",
    "name": "Track Running",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000004",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000111",
    "name": "Trail Running",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000004",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000112",
    "name": "Treadmill Running",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000004",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000114",
    "name": "Cycling",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000005",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000115",
    "name": "Indoor Cycling",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000005",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000116",
    "name": "Outdoor Cycling",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000005",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000119",
    "name": "Open-Water Swim",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000006",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000118",
    "name": "Pool Swim",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000006",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-000000000117",
    "name": "Swimming",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000006",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801782636388",
    "name": "Breaststroke Movement Simulation (Warm-up)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000003",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801374664145",
    "name": "Downward Facing Dog Pose",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000003",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000000108",
    "name": "Mobility Flow",
    "dimensionIds": [],
    "categoryId": "01910000-0000-7000-8000-000000000003",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800575027500",
    "name": "Side Lying Floor Stretch",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000003",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800064891758",
    "name": "Warrior Humble Pose (Baddha Virabhadrasana)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000003",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800285569521",
    "name": "Warrior II to Downward Dog Pose",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000003",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800710325528",
    "name": "Warrior Pose I (Virabhadrasana I)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000003",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804130964551",
    "name": "Yin Yang Circles (warm-up)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000003",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802612541765",
    "name": "Active Circles (Warm-up)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804251431646",
    "name": "Alternating Step Groiners",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800170194516",
    "name": "Atlas Stones",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801290574565",
    "name": "Barbell Alternating Reverse Lunges",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801980907717",
    "name": "Barbell Clean & Jerk",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800561171207",
    "name": "Barbell Clean & Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802692990752",
    "name": "Barbell Clean Pull",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803626271775",
    "name": "Barbell Cleans",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800848800980",
    "name": "Barbell Overhead squats",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801844020842",
    "name": "Barbell Split Jerk",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803874158693",
    "name": "Battle Rope Alternating Waves (Single Arm)",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802858582527",
    "name": "Bear Extension",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802806476368",
    "name": "Bear Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803883445833",
    "name": "Bear Plank Kickback",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800471721772",
    "name": "Cable Deadlifts",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "cable",
      "step"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803482892329",
    "name": "Car Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801187687734",
    "name": "Cleans From Blocks",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell",
      "plate"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804156501454",
    "name": "Crab Twist Toe Touch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802621894088",
    "name": "Crossover Mountain Climbers",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800517996437",
    "name": "Double Kettlebell Snatch",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801213509225",
    "name": "Dumbbell Power Clean",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800001625172",
    "name": "Dumbbell Swings",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800137754495",
    "name": "Farmer's Walk",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "dumbbell",
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802935786913",
    "name": "Frog Plank",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803200964426",
    "name": "Hang Power Snatch",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802135696675",
    "name": "Hang Snatch - Below Knees",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801186454047",
    "name": "Heaving Snatch Balance",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804229558406",
    "name": "Inchworm Waist",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800732510073",
    "name": "Jack Plank on Medicine Ball (female)",
    "dimensionIds": [
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801182811095",
    "name": "Kettlebell Suitcase Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802196414109",
    "name": "Kettlebell Turkish Get Up",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800105074732",
    "name": "Kipping Muscle Up",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800934404560",
    "name": "Knee Tuck Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800298995177",
    "name": "Medicine Ball Chest Push Single Response",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801768841978",
    "name": "Medicine Ball Standing Overhead Throw",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803196302958",
    "name": "Muscle-up with bands",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802578411228",
    "name": "Narrow Grip Smith Machine Bench Press",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800762310688",
    "name": "One-Arm Kettlebell Split Snatch",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803113055671",
    "name": "One-Arm Medicine Ball Slam",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801458205470",
    "name": "Overhead Slam",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "medicineBall"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801043812323",
    "name": "Power Jerk",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801895095782",
    "name": "Press Up Burpees",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803540093721",
    "name": "Push Jerk",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802209604746",
    "name": "Rope Climb",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "rope"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801543751940",
    "name": "Single Arm Kettlebell Clean & Jerk",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803307443969",
    "name": "Single Arm Kettlebell Jerk",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-800345972508",
    "name": "Single Arm Kettlebell Snatch",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801785016208",
    "name": "Single Arm Kettlebell Swings",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "kettlebell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801403903806",
    "name": "Sled Lunge Push",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "sled"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-804095055588",
    "name": "Sled Row",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "sled"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802905649304",
    "name": "Snatch from Boxes",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell",
      "box"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803085936807",
    "name": "Snatch-Grip Deadlift",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802273244488",
    "name": "Spiderman Push Ups",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803022541245",
    "name": "Split Clean",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801301336765",
    "name": "Squat Jerk",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803502652418",
    "name": "Standing Toe Touch",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802360289425",
    "name": "Step-Up Bicep Curls with Dumbbells",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bench",
      "dumbbell"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-802980797315",
    "name": "Straddle Planche",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "bodyweight"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-000000000120",
    "name": "Strength Training",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-802037379609",
    "name": "Strongman Keg Toss",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-800624864269",
    "name": "Strongman Weight for Height",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-804117040364",
    "name": "Sumo Deadlift with Bands",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell",
      "band"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-803752466469",
    "name": "TRX Squat Jumps",
    "dimensionIds": [
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "trx"
    ]
  },
  {
    "id": "01910000-0000-7000-8000-801115117666",
    "name": "Yoke Walk",
    "dimensionIds": [
      "distance",
      "duration"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": []
  },
  {
    "id": "01910000-0000-7000-8000-801384238941",
    "name": "Zercher Squats Barbell",
    "dimensionIds": [
      "load",
      "reps"
    ],
    "categoryId": "01910000-0000-7000-8000-000000000001",
    "equipmentIds": [
      "barbell"
    ]
  }
];

export const PLATFORM_EXERCISE_SEED_REDIRECTS: readonly PlatformSeedExerciseRedirect[] =
[
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200076",
    "toExerciseId": "01910000-0000-7000-8000-801905970469"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200081",
    "toExerciseId": "01910000-0000-7000-8000-800653636218"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200152",
    "toExerciseId": "01910000-0000-7000-8000-000000200154"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200184",
    "toExerciseId": "01910000-0000-7000-8000-000000000103"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200185",
    "toExerciseId": "01910000-0000-7000-8000-801704469948"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200203",
    "toExerciseId": "01910000-0000-7000-8000-801616733243"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200206",
    "toExerciseId": "01910000-0000-7000-8000-800131475101"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200222",
    "toExerciseId": "01910000-0000-7000-8000-800293367129"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200268",
    "toExerciseId": "01910000-0000-7000-8000-000000201392"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200282",
    "toExerciseId": "01910000-0000-7000-8000-804038341039"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200308",
    "toExerciseId": "01910000-0000-7000-8000-803925904138"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200331",
    "toExerciseId": "01910000-0000-7000-8000-000000200960"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200377",
    "toExerciseId": "01910000-0000-7000-8000-000000201313"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200386",
    "toExerciseId": "01910000-0000-7000-8000-800609712479"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200454",
    "toExerciseId": "01910000-0000-7000-8000-804087219200"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200475",
    "toExerciseId": "01910000-0000-7000-8000-000000000104"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200537",
    "toExerciseId": "01910000-0000-7000-8000-000000201276"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200567",
    "toExerciseId": "01910000-0000-7000-8000-000000201337"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200571",
    "toExerciseId": "01910000-0000-7000-8000-802528988475"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200572",
    "toExerciseId": "01910000-0000-7000-8000-801714571933"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200695",
    "toExerciseId": "01910000-0000-7000-8000-801990369080"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200829",
    "toExerciseId": "01910000-0000-7000-8000-000000200487"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200907",
    "toExerciseId": "01910000-0000-7000-8000-804038341039"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000200981",
    "toExerciseId": "01910000-0000-7000-8000-800132285993"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201085",
    "toExerciseId": "01910000-0000-7000-8000-800653636218"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201091",
    "toExerciseId": "01910000-0000-7000-8000-800491196623"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201111",
    "toExerciseId": "01910000-0000-7000-8000-000000200313"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201112",
    "toExerciseId": "01910000-0000-7000-8000-000000200188"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201117",
    "toExerciseId": "01910000-0000-7000-8000-000000200921"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201208",
    "toExerciseId": "01910000-0000-7000-8000-800465159831"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201229",
    "toExerciseId": "01910000-0000-7000-8000-800642779103"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201295",
    "toExerciseId": "01910000-0000-7000-8000-802655591484"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201312",
    "toExerciseId": "01910000-0000-7000-8000-801984195389"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201316",
    "toExerciseId": "01910000-0000-7000-8000-000000200320"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201373",
    "toExerciseId": "01910000-0000-7000-8000-800708952281"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201499",
    "toExerciseId": "01910000-0000-7000-8000-800092115548"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201545",
    "toExerciseId": "01910000-0000-7000-8000-800413374575"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201551",
    "toExerciseId": "01910000-0000-7000-8000-000000201675"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201637",
    "toExerciseId": "01910000-0000-7000-8000-800055981016"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201638",
    "toExerciseId": "01910000-0000-7000-8000-800561171207"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201643",
    "toExerciseId": "01910000-0000-7000-8000-803925904138"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201645",
    "toExerciseId": "01910000-0000-7000-8000-801714571933"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201648",
    "toExerciseId": "01910000-0000-7000-8000-803807041640"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201650",
    "toExerciseId": "01910000-0000-7000-8000-803879678608"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201652",
    "toExerciseId": "01910000-0000-7000-8000-801042677228"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201695",
    "toExerciseId": "01910000-0000-7000-8000-804150749654"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201697",
    "toExerciseId": "01910000-0000-7000-8000-800142410595"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201731",
    "toExerciseId": "01910000-0000-7000-8000-803227065885"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201770",
    "toExerciseId": "01910000-0000-7000-8000-000000201725"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201771",
    "toExerciseId": "01910000-0000-7000-8000-803148727100"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201772",
    "toExerciseId": "01910000-0000-7000-8000-802942379039"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201863",
    "toExerciseId": "01910000-0000-7000-8000-803381350752"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201880",
    "toExerciseId": "01910000-0000-7000-8000-804150749654"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201929",
    "toExerciseId": "01910000-0000-7000-8000-803349716193"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201932",
    "toExerciseId": "01910000-0000-7000-8000-000000200272"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-000000201935",
    "toExerciseId": "01910000-0000-7000-8000-803124302191"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-800128255458",
    "toExerciseId": "01910000-0000-7000-8000-800138153024"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-801409184216",
    "toExerciseId": "01910000-0000-7000-8000-000000200132"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-802127430552",
    "toExerciseId": "01910000-0000-7000-8000-000000200632"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-802190812519",
    "toExerciseId": "01910000-0000-7000-8000-803427080053"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-803183843271",
    "toExerciseId": "01910000-0000-7000-8000-802274189997"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-803296908049",
    "toExerciseId": "01910000-0000-7000-8000-803886778203"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-803449665284",
    "toExerciseId": "01910000-0000-7000-8000-800171589598"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-803507873463",
    "toExerciseId": "01910000-0000-7000-8000-801082545307"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-803632285730",
    "toExerciseId": "01910000-0000-7000-8000-801587587030"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-803858505793",
    "toExerciseId": "01910000-0000-7000-8000-801128167297"
  },
  {
    "fromExerciseId": "01910000-0000-7000-8000-804155340373",
    "toExerciseId": "01910000-0000-7000-8000-802723682929"
  }
];
