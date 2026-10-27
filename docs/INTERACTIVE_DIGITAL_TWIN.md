# Interactive AI-Enabled Digital Twin — Cooling Predictive Maintenance

This document covers the interactive layer built on top of the existing,
validated Cooling Predictive Maintenance project (Phases 1–17,
`docs/architecture.md`). It adds no new physics, AI, health, RUL, thermal, or
maintenance-decision logic — every number the dashboard displays comes from
the project's existing functions, called through one new orchestration
function.

## 1. Architecture

```
                 INTERACTIVE DASHBOARD (app/CoolingDigitalTwinApp.m)
                                   |
                                   v
                  run_single_operating_point.m   (src/interactive/)
                                   |
   pump_model / fan_model -> motor_model -> apply_*_fault -> bearing_fault_frequencies
                                   |
              generate_vibration_signal / generate_current_signal
                                   |
             condition_vibration_signal / condition_current_signal
                                   |
              extract_vibration_features / extract_mcsa_features
                                   |
                    predict_model (trained classifier)
                                   |
              compute_health_index -> estimate_rul (history trend)
                                   |
       cooling_effectiveness_from_degradation -> thermal_digital_twin
                                   |
                    maintenance_decision_engine
                                   |
                          result struct -> dashboard
```

Every arrow above is an existing, unmodified function call (Phase 0 inspection
confirmed the exact signatures in `docs/architecture.md`'s companion
inspection report). `run_single_operating_point.m` is the only new
composition layer, and it performs no computation of its own beyond
assembling inputs/outputs between these calls and maintaining a running
`history` buffer (needed because `estimate_rul` requires a trend and
`thermal_digital_twin` integrates a time series — neither works from a single
instant).

## 2. Existing model components reused

Every item in this list is a pre-existing file, called unchanged:
`project_config.m`, `sensor_config.m`, `model_parameters.m`, `pump_model.m`,
`fan_model.m`, `motor_model.m`, `apply_pump_fault.m`, `apply_fan_fault.m`,
`bearing_fault_frequencies.m`, `generate_vibration_signal.m`,
`generate_current_signal.m`, `condition_vibration_signal.m`,
`condition_current_signal.m`, `segment_signal.m`,
`extract_vibration_features.m`, `extract_mcsa_features.m`,
`extract_operating_state_features.m`, `train_random_forest.m`,
`predict_model.m`, `compute_health_index.m`, `estimate_rul.m`,
`cooling_effectiveness_from_degradation.m`, `thermal_digital_twin.m`,
`get_maintenance_thresholds.m`, `maintenance_decision_engine.m`. Experiment 9
(`experiments/experiment_09/run_experiment_09.m`) is reused verbatim for
Demonstration Scenario C.

## 3. New interactive-layer files

| File | Phase | Role |
|---|---|---|
| `src/interactive/run_single_operating_point.m` | A | Live one-step pipeline (see §1) |
| `tests/test_run_single_operating_point.m` | B | 5-scenario integration test |
| `src/interactive/train_and_save_model.m` | C | One-time training + persistence |
| `src/interactive/load_or_train_model.m` | D | Load-if-present, else train once |
| `app/CoolingDigitalTwinApp.m` | E | The dashboard (hand-authored classdef, not a binary `.mlapp` — see its docstring for why) |
| `app/launch_cooling_digital_twin.m` | E | Launcher |
| `demo/demo_healthy.m`, `demo_bearing_degradation.m`, `demo_severe_degradation.m`, `run_fault_progression.m` | F | Command-line demonstration scenarios |

The existing `.slx` model (`models/Simulink/CoolingPredictiveMaintenance.slx`,
built by `build_simulink_model.m`) is **preserved untouched**. Per the
approved Phase-0 architecture decision, it is not the interactive engine —
its internal MATLAB Function blocks are not wired into its signal path (see
the Phase-0 inspection findings), so live interactivity is built in MATLAB/
App Designer instead, composing the functions above directly. Rewiring the
`.slx` for true block-level interactivity remains future work (§9 below).

## 4. Interactive controls

| Control | Range / source |
|---|---|
| IT Load (kW) | 10–100 (centered on `P.Thermal.IT_load_kW_nominal`) |
| Ambient (°C) | `cfg.operating.ambient_C_range` |
| Speed (rpm) | `cfg.operating.speed_rpm_range` |
| Load (%) | `cfg.operating.load_pct_range` |
| Equipment | `cfg.equipment` (`Pump`, `Fan`) |
| Fault Type | `cfg.faults.(equipment)` — repopulated when Equipment changes |
| Severity D | 0–100%, mapped to `[0,1]` |
| Vibration / current noise multiplier | 0–5×, scales `sensor_config()`'s base noise values (the base values themselves are never replaced) |
| Sweep steps | number of steps for Fault Sweep (default 30) |
| RUN / FAULT SWEEP / HEALTHY / RESET / STOP | see §7 |

Every range above is read from the project's own config, not invented.

## 5. Outputs displayed

System status (NORMAL/MONITOR/WARNING/MAINTENANCE_REQUIRED/CRITICAL,
color-coded from `maintenance_decision_engine.m`'s actual `decision.level`);
injected equipment/fault/severity; **AI-predicted fault type**, shown
separately from the injected ground truth (no leakage — the classifier only
ever sees extracted features); Health Index; RUL (or "N/A (no trend)" when
`estimate_rul.m` correctly returns `NaN`, never a fabricated number); server
inlet temperature; thermal margin; cooling effectiveness; maintenance
decision. No confidence score is displayed, because `predict_model.m` does
not currently expose one — inventing one was explicitly disallowed.

## 6. Signal flow
See §1. Vibration and current signals are generated fresh for the CURRENT
operating point on every step (a live sensor only reports "now" — regenerating
raw signals for the whole history every step would be both wasteful and
physically meaningless); Health Index, RUL, and the thermal trajectory are
computed over the ACCUMULATED history buffer, exactly mirroring how
`simulate_degradation_trajectory.m` already does it over a pre-built
trajectory.

## 7. Simulation controls
- **RUN** — one step at the current control values.
- **FAULT SWEEP** — ramps Severity from 0% to 100% over the configured number
  of steps, at the current Equipment/Fault Type, one step per simulated hour,
  calling `run_single_operating_point.m` each step (the same function RUN
  uses) — this is `demo/run_fault_progression.m`'s pattern, run interactively.
- **HEALTHY** — clears the history buffer and runs one step at D=0, Fault =
  Healthy, returning to the baseline state.
- **RESET** — currently identical to HEALTHY (clears history and returns to
  baseline); kept as a separate button per the requested control set.
- **STOP** — sets a flag checked between steps of an in-progress FAULT SWEEP;
  it stops the sweep at the next step boundary, not mid-step.

No true real-time (continuously running, unpaused) simulation is implemented
— per §Phase 13's own guidance, "Run Scenario → Update Dashboard" was
prioritized over real-time animation for reliability, since parameter changes
would otherwise clash with a live-updating history/thermal state.

## 8. AI pipeline
`load_or_train_model.m` is called exactly once, at dashboard startup. If
`models/ML/trained_classifier.mat` exists and matches the requested feature
set, it is loaded; otherwise `train_and_save_model.m` trains once (via the
existing `generate_scenarios → generate_dataset → train_random_forest`
pipeline) and saves it. The dashboard never calls either function again
during a session — changing Fault/Severity/IT Load/Ambient/RPM only calls
`run_single_operating_point.m`, which only calls `predict_model.m` on the
already-loaded model.

## 9. Thermal model
Reused unchanged, including the exact-exponential-integration numerical-
stability fix and the calibrated `cooling_time_constant_s` / fault-coefficient
values already validated in Phases 1–17. The interactive layer does not
modify any thermal parameter. A fault with only a small thermal consequence
under the existing model (e.g. `BearingDegradation`) will continue to show
only a small thermal consequence here — the dashboard does not compensate for
that to make a more dramatic demo.

## 10. Maintenance decision logic
`get_maintenance_thresholds.m`'s values are used exactly as validated:
`HI_warning=70, HI_maintenance=40, HI_critical=15, RUL_warning_hours=24,
RUL_maintenance_hours=8, thermal_margin_warning_C=5,
thermal_margin_critical_C=1`. The dashboard does not currently expose these as
adjustable controls (no "advanced" panel was added in this pass) — they are
displayed as read-only context; adding an advanced-threshold panel, clearly
separated from these defaults, is listed as a natural next step in §12.

## 11. Demonstration scenarios (§Phase 8)
- **Scenario A — Healthy**: `demo/demo_healthy.m`.
- **Scenario B — Progressive fan bearing degradation**: `demo/demo_bearing_degradation.m`
  (also reachable interactively via Equipment=Fan, Fault=BearingDegradation,
  FAULT SWEEP).
- **Scenario C — Severe cooling degradation, reactive vs predictive**:
  `demo/demo_severe_degradation.m`, a thin wrapper around the existing,
  unmodified `experiments/experiment_09/run_experiment_09.m`.

## 12. Validation status — READ THIS BEFORE PRESENTING
- Phase A (backend) and Phase B (tests) were built and statically reviewed
  against the actual function signatures in this repository, but **as of
  this document's writing, Phase B's tests have not yet been confirmed to
  pass by an actual MATLAB execution.** Run `test_run_single_operating_point()`
  and resolve anything it reports before relying on this dashboard for a
  real demonstration.
- Phases C–G (model persistence, the dashboard app, demo scripts, this
  documentation) were built on top of that unconfirmed Phase B, at the
  requester's explicit instruction to proceed through all phases together
  rather than gate on B's execution. This is a known, accepted risk for this
  build — re-validate before a real audience.
- The original 17-phase pipeline's own validation
  (`validate_project.m`, "all 6 checks passed") and the original 10
  experiments remain unaffected — nothing in this interactive layer changes
  any file `validate_project.m` or the experiments depend on.

## 13. Known limitations
- The `.slx` Simulink model is not wired for live interactivity (§3); the
  interactive engine is MATLAB/App Designer-based.
- No confidence score is displayed (not available from `predict_model.m`).
- Maintenance thresholds are read-only in this pass, not yet exposed as
  adjustable "advanced" controls.
- `RESET` and `HEALTHY` currently do the same thing.
- The dashboard's own FFT-for-display and RUL-trend-for-plotting are
  presentation-layer conveniences (documented in
  `app/CoolingDigitalTwinApp.m`'s docstring) — they call `fft` and the
  existing `estimate_rul.m` respectively, purely for plotting, and are not a
  second implementation of any diagnostic or health computation.
- No performance/timing measurements have been taken yet (Phase 16 of the
  original interactive-twin brief was not part of this build pass).

## 14. Future hardware integration
`run_single_operating_point.m`'s vibration/current generation step
(`generate_vibration_signal.m` / `generate_current_signal.m`) is the single,
well-defined seam where a real sensor feed would replace the simulator: a
future `get_vibration_input()` / `get_current_input()` pair returning a raw
signal in the same units and sample rate as the current generators would let
everything downstream (conditioning, feature extraction, AI inference,
health/RUL, thermal twin, maintenance decision) run unchanged. This was
scoped as a future step, not implemented in this pass, since the repository
does not yet have any hardware communication code to build on.
