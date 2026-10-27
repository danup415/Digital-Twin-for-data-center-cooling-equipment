# Physics-Informed Multimodal Predictive Maintenance and Digital Twin
## of Data-Center Cooling Equipment — Final-Year Project Report

## Abstract
Data-center cooling equipment failures — pump cavitation, bearing degradation,
unbalance, misalignment, and fan efficiency loss — can silently raise server
inlet temperature before any threshold-based alarm fires. This project builds
a fully-simulated (no physical hardware), physics-informed predictive-
maintenance framework in MATLAB/Simulink for a chilled-water pump and CRAC
fan. A reduced-order physics model generates synthetic vibration and
motor-current signals under severity-parameterized faults; multimodal
features are fused and classified; a Health Index and RUL estimator track
degradation; a lumped-parameter thermal digital twin translates equipment
degradation into predicted server-inlet-temperature consequences; and a
predictive-maintenance decision engine is compared against a reactive
baseline. All results reported here are computed by the code in this
repository, not asserted.

## Objectives
See docs/architecture.md §3 for the full 15-point objective list. In summary:
simulate both assets under normal/faulty conditions; generate physically
meaningful multimodal sensor data; fuse vibration+MCSA for diagnosis and
severity estimation; produce a continuous Health Index and RUL; predict the
thermal consequence of degradation; and demonstrate predictive maintenance's
advantage over reactive maintenance with a measured early-warning lead time.

## Methodology
Chapters 4-10 below summarize the methodology; the authoritative detail lives
in `docs/architecture.md` (design) and `docs/equations.md` (every equation,
tied to its implementing file). The pipeline: physics model → fault
injection (single severity variable `D` per fault) → virtual sensors →
signal conditioning → feature extraction → multimodal fusion → classification
+ severity regression → Health Index/RUL → thermal digital twin →
maintenance decision engine → reactive-vs-predictive comparison. Every stage
is implemented and runnable (Phases 1-15 of the roadmap in
`docs/architecture.md` §L are complete).

## Novelty / Contribution Statement
This is an **integrated, physics-informed, multimodal predictive-maintenance
architecture**, not a claim of novelty for any single component: (1) a
reduced-order physics+fault digital twin, (2) vibration+MCSA multimodal
sensing with operating-condition awareness, (3) fault classification with
explicit severity estimation, (4) a Health-Index/RUL layer, (5) an explicit
fault→thermal-consequence model, (6) a physics-informed-residual ablation
(§36), and (7) a predictive-vs-reactive maintenance comparison with a
measured early-warning lead time (not an assumed one).

---

## Chapter 1 — Introduction
Motivation, scope (chiller pump + CRAC fan, fully simulated), and the central
engineering story (fault → sensor signature → diagnosis → severity → health →
consequence → maintenance decision) reproduced from §57 of the original
project brief and §A of `docs/architecture.md`.

## Chapter 2 — Literature Review
Standard references for the techniques used: vibration-based bearing
diagnostics (BPFO/BPFI/BSF theory), motor current signature analysis (MCSA)
for mechanical-fault detection via current sidebands, pump/fan affinity laws,
lumped-parameter (RC) thermal modeling for data-center thermal zones, and
Health-Index/RUL formulations in predictive maintenance. (Populate with the
specific papers/textbooks your department expects cited — this project
implements the standard forms of these techniques but does not itself
constitute a literature survey.)

## Chapter 3 — Problem Definition
As stated in `docs/architecture.md` §2 ("Core Problem"): undetected
mechanical/hydraulic degradation in cooling equipment can progressively erode
cooling capacity until server-inlet temperature safety margins are violated,
and today's threshold-based monitoring only reacts after that happens.

## Chapter 4 — System Architecture
Reproduced in full in `docs/architecture.md` §A-B (block diagram + 16-
subsystem hierarchy) and implemented in Phase 12 (`models/Simulink/build_simulink_model.m`).

## Chapter 5 — Mathematical Modeling
Pump/fan affinity laws and the simplified induction-motor model — see
`docs/equations.md` §"Pump/Fan affinity laws" and §"Induction motor",
implemented in `src/physics/`.

## Chapter 6 — Fault Modeling
Severity-parameterized fault taxonomy (§D of `docs/architecture.md`),
bearing-frequency equations, and the fault→hydraulic-degradation coupling —
implemented in `src/faults/`, documented equation-by-equation in
`docs/equations.md`.

## Chapter 7 — Sensor and Signal Processing
Virtual sensor model (§E), vibration/MCSA signal synthesis (Phase 4),
conditioning and windowing (Phase 5), and the full feature set (Phase 6) —
implemented in `src/sensors/`, `src/signal_processing/`, `src/features/`.

## Chapter 8 — Machine Learning
Baseline tree, Random-Forest/bagged-tree (with a documented k-NN fallback if
Statistics and Machine Learning Toolbox is unavailable), and a 1D-CNN tier
(skipped honestly, not fabricated, if Deep Learning Toolbox is unavailable).
The 5-rung ablation ladder (Vibration-only / MCSA-only / Fusion /
Fusion+state / Fusion+state+physics-residual) is Experiments 7 and 8. All
splits are scenario-level to prevent leakage (§23), audited in
`validate_project.m`.

## Chapter 9 — Digital Twin
Reduced-order, physically-transparent lumped-RC thermal model (§H,
`src/thermal/thermal_digital_twin.m`), explicitly linked to equipment
degradation via `cooling_effectiveness_from_degradation.m` (§28's
fault→thermal-consequence chain).

## Chapter 10 — Predictive Maintenance
Health Index (analytic baseline, §24), RUL (trend-extrapolation baseline,
§25), and the maintenance decision engine (§29,
`src/maintenance/maintenance_decision_engine.m`) with configurable,
documented thresholds (`get_maintenance_thresholds.m`).

## Chapter 11 — Results
Populate this chapter by running `main.m` and pulling the actual numbers
from `results/tables/*.csv` and `results/figures/*.png` — Experiments 1-10
(§35) each write their own results table; this report intentionally does
not hard-code numbers here, since those numbers depend on the random
scenario draw (seeded, but still specific to a run) and should be quoted
from an actual `main.m` execution, not typed in ahead of time (§51: never
assert a result the code didn't produce).

## Chapter 12 — Validation
`validate_project.m` (Phase 13) runs parameter sanity, signal sanity, fault-
injection monotonicity, data-leakage audit, reproducibility, and (if
Simulink is licensed) a model-compile check. Its pass/fail table is saved to
`results/tables/validation_report.csv` — quote directly from that file.

## Chapter 13 — Limitations
Stated plainly, not hidden: (1) the physics models are explicitly reduced-
order surrogates, not CFD/FEA-validated models; (2) cavitation and thermal
models are documented simplifications; (3) the Health Index and RUL use
transparent analytic/trend-extrapolation baselines — an ML-based Health Index
and an LSTM/TCN RUL model (both mentioned in the original brief) are NOT yet
built, and this report does not claim they are; (4) the physics-residual
features (Experiment 8) are a compact 4-feature set, not a full residual
architecture; (5) all reported metrics come from synthetic data — no claim of
real-world/experimental validation is made anywhere in this project.

## Chapter 14 — Future Scope
ML-based Health Index estimator compared against the analytic baseline;
LSTM/TCN RUL model compared against the trend-extrapolation baseline; a
richer physics-residual feature set; MATLAB-Coder-based edge-deployment
codegen (§37, not yet built); Simulink Dashboard-block panel if the Dashboard
add-on is available (Scope-block fallback is what's built); extending beyond
two equipment assets.

## Chapter 15 — Conclusion
Phases 1-15 of the roadmap are complete and runnable end-to-end via
`main.m`: physics → faults → sensors → signal processing → features →
dataset → ML+ablation → Health Index/RUL → thermal twin → decision engine →
Simulink model → validation → 10 experiments → figures/tables. The project
demonstrates, on synthetic data, the full engineering chain from a physical
fault to a predictive maintenance decision, with an explicit, measured
comparison against reactive maintenance (Experiment 9).

---

## List of Figures
See `docs/architecture.md` §45 for the required list; all 20 are generated by
`generate_figures.m` (Phase 15) into `results/figures/`, each named
`figNN_description.png`.

## List of Tables
See `docs/architecture.md` §46 for the required list; all 10 are generated by
`generate_tables.m` (Phase 15) into `results/tables/`, each named
`tableNN_description.csv`.

## List of Equations
See `docs/equations.md` for the complete, file-linked equation reference.

## Flowchart / Block Diagrams
The master signal-flow block diagram is in `docs/architecture.md` §A; the
16-subsystem Simulink hierarchy is in §B and §I, and is generated
programmatically as `fig01_system_architecture.png` by `generate_figures.m`.
