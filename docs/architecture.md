# Physics-Informed Multimodal Predictive Maintenance and Digital Twin
## of Data-Center Cooling Equipment — Project Architecture (Phase 0)

**Short title:** MATLAB/Simulink-Based Predictive Maintenance of Chiller Pumps and CRAC Fans Using Vibration and MCSA

---

## A. Final Project Architecture

The project is a closed-loop, purely-simulated pipeline. Nothing here needs a physical rig — every signal is generated from a physics model whose state is corrupted by an explicit, parameterized fault-injection layer.

```
[Environment / IT load] → [Cooling-load model] → [Chiller / Pump] ⟶ [Motor]
                                                        │
                                              [Fault Injection Layer]
                                                        │
                          ┌─────────────────────────────┼─────────────────────────────┐
                          ▼                             ▼                             ▼
                 [Vibration virtual sensor]   [Current (MCSA) virtual sensor]   [Process sensors: T, P, Q, N, kW]
                          │                             │                             │
                          └─────────────┬───────────────┘                             │
                                        ▼                                             │
                          [Signal Conditioning: detrend, filter, window]              │
                                        │                                             │
                                        ▼                                             │
                          [Feature Extraction: time / freq / bearing]                 │
                                        │                                             │
                          [Operating-state features] ◄─────────────────────────────────┘
                                        │
                                        ▼
                          [Multimodal Fusion: F = [F_vib, F_mcsa, state]]
                                        │
                     ┌──────────────────┼───────────────────┐
                     ▼                  ▼                   ▼
           [Fault Classification] [Severity Regression] [Physics Residual Features]
                     │                  │
                     └────────┬─────────┘
                              ▼
                     [Health Index (0–100)]
                              │
                              ▼
                     [RUL / Time-to-Critical estimator]
                              │
                              ▼
                     [Thermal Digital Twin: equipment degradation → airflow/flow → T_server]
                              │
                              ▼
                     [Predictive-Maintenance Decision Engine]
                        NORMAL → MONITOR → WARNING → MAINTENANCE → CRITICAL
                              │
                     ┌────────┴────────┐
                     ▼                 ▼
           [Mode A: Reactive]   [Mode B: Predictive]  → compared on lead time, peak T, downtime, false alarms
```

Two parallel equipment strings (Pump, CRAC Fan) share this same architecture; only the physics block and fault set differ.

---

## B. Detailed Subsystem Hierarchy

```
CoolingPredictiveMaintenance
├── Environment            (ambient T, IT load profile, cooling demand)
├── ChilledWaterPump
│   ├── PumpPhysics         (affinity laws, ΔP–Q–N–η relations)
│   ├── PumpFaults          (cavitation, unbalance, bearing, misalignment)
│   └── PumpMotor           (induction-motor equivalent circuit)
├── CRACFan
│   ├── FanPhysics
│   ├── FanFaults           (bearing, unbalance, misalignment, efficiency loss)
│   └── FanMotor
├── VirtualSensors          (accel, current, T, P, Q, N, kW — each with noise/bias/Fs)
├── SignalConditioning      (detrend, bandpass/low-pass, window, normalize)
├── FeatureExtraction
│   ├── VibrationFeatures   (time / freq / bearing-specific / time-freq)
│   └── MCSAFeatures        (RMS, THD, sidebands, harmonics)
├── OperatingStateEstimator (speed/load/ambient bucketing, adaptive-threshold basis)
├── FusionAndDiagnosis
│   ├── ClassicalML         (LogReg/Tree, RandomForest, boosted trees)
│   └── DeepLearning        (1D-CNN or TCN)
├── HealthIndex
├── RUL
├── ThermalDigitalTwin      (RC thermal network, energy balance)
├── MaintenanceDecisionEngine
└── Visualization/Dashboard
```

Simulink subsystem numbering mirrors §38 of the brief (01_Environment … 16_Visualization) and is implemented 1:1 in `build_simulink_model.m` (Phase 13).

---

## C. Mathematical Model and Core Equations

**Pump/fan affinity laws** (reduced-order, speed-scaled from a nominal operating point):
`Q ∝ N`, `ΔP ∝ N²`, `P_shaft ∝ N³`, with efficiency `η(Q,N)` from a quadratic best-efficiency-point curve.

**Degradation coupling** (generic form used for every fault):
`η_fault = η_nominal · (1 − f_D(D))`, `Q_fault = Q_nominal · g_D(D)`, where `D ∈ [0,1]` is the fault-specific severity state and `f_D, g_D` are monotonic, fault-specific (documented per-fault in `docs/equations.md`, generated in Phase 3).

**Motor (steady-state induction-motor equivalent):** slip `s = (N_sync − N)/N_sync`, torque–slip curve, stator current `I_s(s, V, f)` with fundamental at line frequency `f_s` plus fault-dependent sidebands `f_s(1 ± 2ks)` for k=1,2,… (broken-rotor-bar-style modulation, reused here as a generic mechanical-fault modulation channel — documented as an analogy, not a rotor-bar-fault claim).

**Vibration signal (superposition model):**
`x(t) = A₁·sin(2π f_r t) + Σ harmonics + bearing_impulse_train(D_b) + cavitation_broadband(C) + unbalance(U)·sin(2π f_r t) + misalignment(1X,2X) + n(t)`, sampled at `Fs = 10 kHz` (configurable), amplitude-modulated by instantaneous speed/load.

**Bearing characteristic frequencies** (standard rolling-element-bearing equations, from `Nb`, `Bd`, `Pd`, contact angle `φ`, shaft speed `f_r`):
`BPFO = (Nb/2) f_r (1 − (Bd/Pd)cosφ)`, `BPFI = (Nb/2) f_r (1 + (Bd/Pd)cosφ)`, `BSF = (Pd/2Bd) f_r (1 − (Bd/Pd)²cos²φ)`, `FTF = (f_r/2)(1 − (Bd/Pd)cosφ)`.

**Unbalance force:** `F_u = m·e·ω²` (rotating-mass eccentricity), scaled by severity `U`.

**Cavitation:** NPSH margin `Δ = NPSH_available − NPSH_required`; when `Δ` shrinks, broadband high-frequency vibration energy and flow/pressure fluctuation amplitude increase monotonically with cavitation severity `C` — explicitly labeled a reduced-order surrogate, not CFD.

**Thermal digital twin (lumped energy balance / RC network):**
`Q_cooling = ṁ·Cp·ΔT` for the chilled-water side; server-inlet temperature from a first-order RC model driven by `Q_IT − Q_cooling_effective(degradation)`, with `Q_cooling_effective` scaled down by the same `D` state that drives the vibration/current features — this is the physical link between "fault" and "thermal consequence" (§28 of the brief).

Full symbol table and derivations are written out in `docs/equations.md` as each phase lands (per requirement, no equation ships without an explanation).

---

## D. Fault Taxonomy

| Asset | Fault | Severity states | Physical mechanism | Primary signature |
|---|---|---|---|---|
| Pump | Healthy | D=0 | — | baseline |
| Pump | Cavitation | C ∈ {0.05,0.15,0.30,0.50} | NPSH margin loss → vapor collapse | broadband HF vibration, ΔP/Q fluctuation, η drop |
| Pump | Unbalance | U ∈ {…} | rotating eccentric mass | 1X vibration amplitude, current sideband |
| Pump | Bearing degradation | D_b ∈ {…} | race/rolling-element spall | BPFO/BPFI/BSF energy, impulsiveness (kurtosis) |
| Pump | Misalignment | M ∈ {…} | shaft/coupling offset | 1X+2X vibration, axial component |
| Fan | Bearing degradation | D_b ∈ {…} | same as above | same as above |
| Fan | Unbalance | U ∈ {…} | blade/rotor imbalance | 1X vibration |
| Fan | Misalignment | M ∈ {…} | shaft offset | 1X+2X, axial/radial ratio |
| Fan | Efficiency degradation | E ∈ {…} | fouling/blade wear | airflow drop at constant power, no strong vibration signature (a "quiet" fault — deliberately included to stress-test vibration-only models) |

Each severity state maps to the labels: Healthy(0%) / Mild(5%) / Moderate(15%) / Severe(30%) / Critical(50%), per §6.

---

## E. Sensor Model

`SensorConfig` struct (Phase 2), one sub-struct per channel:

```
SensorConfig.Accelerometer : Fs=10000 Hz, range=±50 g, noise_rms, bias, (optional) quantization bits
SensorConfig.Current       : Fs=5000  Hz, range, noise, bias
SensorConfig.Temperature   : Fs=1     Hz, noise, bias, drift/hr
SensorConfig.Pressure      : Fs=10    Hz, noise, bias
SensorConfig.Flow          : Fs=10    Hz, noise, bias
SensorConfig.Speed         : Fs=100   Hz, noise
SensorConfig.Power         : Fs=10    Hz, noise
```

---

## F. Dataset Schema

One row per (scenario, time-window). Columns:

`timestamp, equipment_id {Pump,Fan}, scenario_id, operating_state {speed_bin, load_bin, ambient_bin}, fault_type, fault_severity, vib_features[…], mcsa_features[…], temperature, pressure, flow, speed, power, health_label, failure_critical_flag, RUL`

Saved as both `.mat` (canonical, typed) and `.csv` (for inspection/report tables), one manifest file mapping scenario_id → generation parameters for full traceability (mirrors the leakage-safe manifest pattern already used in the [[motor-fault]] pipeline).

---

## G. ML Methodology

- **Baseline:** logistic regression / decision tree on hand-crafted features — establishes the floor.
- **Classical:** Random Forest and a boosted-tree ensemble (MATLAB `fitcensemble`; XGBoost only if available externally — not assumed).
- **Deep:** 1D-CNN over short-time spectral/time features; TCN as a stretch goal, with the CNN kept as the robust fallback if TCN training is unstable (per §21).
- **Splitting:** scenario/trajectory-wise, never window-wise, to avoid leakage (§23) — same discipline as `audit_data_leakage.m` in the existing [[motor-fault]] project, reused here.
- **Ablation ladder (§34):** Vibration-only → MCSA-only → Fusion → Fusion+state → Fusion+state+physics-residual, each trained/evaluated identically so gains are attributable.

---

## H. Digital-Twin Methodology

A **reduced-order, physically-transparent** twin — not a full CFD/BIM twin. State: pump/fan degradation → flow & efficiency loss → cooling capacity loss → RC thermal network → server-inlet temperature. Every gain/time-constant in the RC network is declared in `model_parameters.m` with a one-line physical justification (e.g. thermal mass of a data-hall zone, chilled-water loop time constant). The twin runs open-loop against the physics/fault simulator so the same severity trajectory drives both the sensor signals and the thermal consequence — this is the mechanism that makes "predictive" maintenance possible (the twin sees the consequence before the threshold is crossed).

---

## I. Simulink Architecture

16 subsystems, numbered 01–16 exactly as listed in §38 of the brief, generated programmatically by `build_simulink_model.m` (`add_block`/`add_line` scripting rather than hand-built, so it is reproducible from source). MATLAB Function blocks are used only at well-defined boundaries (fault injection, feature extraction, decision logic) — no monolithic blocks. A Dashboard-block panel (with Scope/Display fallback if Dashboard blocks are unavailable) implements §39.

---

## J. Novelty / Contribution Statement

This is an **integrated, physics-informed, multimodal predictive-maintenance architecture** for data-center cooling equipment, combining: (1) a reduced-order physics + fault digital twin, (2) vibration+MCSA multimodal sensing with operating-condition awareness, (3) fault classification with explicit severity estimation, (4) a Health-Index/RUL layer, (5) an explicit fault→thermal-consequence model, and (6) a predictive-vs-reactive maintenance comparison with measured early-warning lead time. No single component is claimed as individually novel; the contribution is the end-to-end, physically-traceable chain from fault mechanism to maintenance decision.

---

## K. Project Folder Structure

Scaffolded exactly per §41 of the brief (see the created directory tree — `config/`, `data/{raw,processed,generated}/`, `models/{physics,ML,Simulink}/`, `src/{physics,faults,sensors,signal_processing,features,machine_learning,health_index,RUL,thermal,maintenance}/`, `experiments/`, `results/{figures,tables,metrics}/`, `docs/`).

---

## L. Implementation Roadmap (Phases 1–17)

| Phase | Deliverable | Status |
|---|---|---|
| 1 | Config/parameter system | Done |
| 2 | Physics models (pump, fan, motor) | Done |
| 3 | Fault models (severity-parameterized) | Done |
| 4 | Virtual sensors | Done |
| 5 | Signal conditioning | Done |
| 6 | Feature extraction | Done |
| 7 | Dataset generation pipeline | Done |
| 8 | ML training + ablation (baseline tree, RF/bag with kNN fallback, 1D-CNN, ablation A-D) | Done |
| 9 | Health Index + RUL (baseline formulations) | Done |
| 10 | Thermal digital twin (lumped RC + fault->effectiveness link) | Done |
| 11 | Predictive-maintenance decision engine | Done |
| — | Integration smoke-test wiring Phases 2-11 together (`experiments/experiment_00_integration_demo/run_demo.m`) | Done |
| 12 | Simulink model generation | Done |
| 13 | Validation suite (`validate_project.m`) | Done |
| 14 | Experiments 1–10 (§35), incl. reactive-vs-predictive comparison and physics-residual "Model E" | Done |
| 15 | Figures/tables generation | Done |
| 16 | Final report chapters | Done |
| 17 | Viva prep | Done |

Not yet built, called out explicitly rather than assumed: an ML-based Health
Index estimator to compare against the analytic baseline (§24), an
LSTM/TCN-based RUL model to compare against the trend-extrapolation baseline
(§25), MATLAB Coder edge-deployment codegen (§37), and a Simulink Dashboard-
block panel (Scope-block fallback is what's built) — all listed as pending,
not fabricated. `main.m` is the single entry point that reproduces every
phase end-to-end.

(Renumbered slightly from the brief's §52 phase list to match the folder/build order — parameters must exist before physics, physics before faults, etc.)

---

## M. Toolbox Requirements

| Toolbox | Used for | Fallback if absent |
|---|---|---|
| Signal Processing Toolbox | FFT/STFT/filtering | manual `fft`, `filter` (base MATLAB) |
| Statistics and Machine Learning Toolbox | RF/ensemble, classification metrics | manual metric computation |
| Deep Learning Toolbox | 1D-CNN/TCN | skip DL tier, report classical-ML-only results |
| Predictive Maintenance Toolbox | RUL utilities (optional) | custom trend-extrapolation RUL |
| Simscape / Simscape Fluids | higher-fidelity pump/fan physics (optional) | reduced-order equation blocks (default path) |
| Simulink Dashboard | live dashboard blocks | Scope/Display blocks |
| MATLAB Coder | edge-inference codegen (§37, optional) | skip codegen, report simulated latency only |

Base requirement: **MATLAB R2024a, Simulink**, no toolbox assumed beyond these two.

---

## N. Validation Strategy

`validate_project.m` (built in Phase 13) runs: parameter sanity checks, signal sanity checks (NaN/Inf, unit/dimension checks), fault-injection checks (severity monotonicity), ML data-leakage audit (scenario-wise split verification, reusing the pattern already validated in the [[motor-fault]] project), reproducibility check (`rng(42)` fixed-seed re-run comparison), and a Simulink model-compiles-and-runs check.

---

## O. Risks and Fallback Strategies

| Risk | Fallback |
|---|---|
| TCN training unstable | Fall back to 1D-CNN (already the required contingency in §21) |
| XGBoost/Deep Learning Toolbox unavailable | Use `fitcensemble` / classical ML only, report honestly |
| Full Simscape physics too slow | Use reduced-order equation-based physics (default design choice, not a fallback-of-last-resort) |
| Targets in §33 (>90% recall, <1% FPR) not met | Report actual numbers, diagnose, iterate — never adjust data/labels to hit targets (§51 is a hard constraint) |
| Dashboard blocks unavailable | Scope/Display blocks |
| Data-leakage risk from correlated time windows | Scenario/trajectory-wise splitting enforced from Phase 7 onward, audited in Phase 13 |

---

*End of Phase 0 architecture document. Phase 1 (configuration system) files follow.*
