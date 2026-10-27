# Interactive Simulink Digital Twin — Visual, Animated Cooling-System Model

This document covers `models/Simulink/InteractiveCoolingDigitalTwin.slx`, a
**separate** model from `CoolingPredictiveMaintenance.slx` (untouched) and
from the MATLAB dashboard app in `app/CoolingDigitalTwinApp.m` (also
untouched). Press Run in Simulink and watch a rotating pump/fan schematic
whose color and the companion dashboard's numbers respond to injected faults,
computed by the project's real functions.

## Read this first: the architecture decision

A true rotating-equipment animation inside Simulink, driven genuinely by
simulation state, needs either Simscape Multibody (CAD import, revolute
joints, Mechanics Explorer) or a custom graphics-driving block. **This build
could not confirm whether Simscape Multibody is installed**, so it uses the
documented fallback path instead (§8 of the request this was built from
explicitly allows this): two `matlab.System` classdef blocks.

This is worth being explicit about, because it is a genuinely different
mechanism from the MATLAB Function blocks used in
`models/Simulink/build_simulink_model.m` (the original model):

| | MATLAB Function block | `matlab.System` block (used here) |
|---|---|---|
| Execution | Code-generation-restricted | Interpreted by default |
| Can call project's existing functions directly (structs, strings, tables, trained classifier objects)? | No — must re-express equations in scalar/codegen-safe form | **Yes** — literal function calls |
| Can draw live graphics? | No | Yes |

Because of this, `DigitalTwinCoreAndDashboard.m` **literally calls**
`run_single_operating_point.m` — and through it, `pump_model.m`,
`fan_model.m`, `motor_model.m`, `apply_pump_fault.m`, `apply_fan_fault.m`,
`bearing_fault_frequencies.m`, `generate_vibration_signal.m`,
`generate_current_signal.m`, `condition_vibration_signal.m`,
`condition_current_signal.m`, `extract_vibration_features.m`,
`extract_mcsa_features.m`, `predict_model.m`, `compute_health_index.m`,
`estimate_rul.m`, `cooling_effectiveness_from_degradation.m`,
`thermal_digital_twin.m`, and `maintenance_decision_engine.m` — with **zero**
of their equations re-expressed or duplicated. This is actually a cleaner
reuse story than the original model's MATLAB Function blocks could achieve.

## What's physically modeled, schematic, or synthetic (§25 — read before presenting)

| Element | What it actually is |
|---|---|
| Pump/fan efficiency, torque, flow, cavitation/bearing/unbalance/misalignment/efficiency degradation, motor slip/current, bearing fault frequencies | Real: the project's existing reduced-order physics/fault models, called unchanged |
| Vibration and current waveforms shown in the dashboard window | Real synthesized signals from `generate_vibration_signal.m` / `generate_current_signal.m` — not placeholders |
| AI fault classification | Real: the trained classifier (`predict_model.m`), run on the real extracted features |
| Health Index, RUL, thermal trajectory, maintenance decision | Real: the existing, validated functions, called unchanged |
| The rotating pump/fan/flow-dot drawing | **Schematic** — simple 2D lines and circles, not a CAD model or a physically simulated mechanical structure. It rotates at an angle genuinely integrated from the commanded RPM each animation tick (0.05s), so the ROTATION itself is simulation-driven, but the SHAPE is a labeled diagram, not a rendering of real pump/fan geometry |
| The flow-dot indicator's speed | Proxied directly by commanded RPM, citing the real `Q ~ N` affinity-law relationship already used in `pump_model.m`/`fan_model.m` — not the exact simulated `Q` value, which exists inside `run_single_operating_point.m`'s computation but is not one of that (already-tested) function's returned fields; adding it was avoided specifically to keep that function unmodified |
| The blade/vane shapes, the "WARNING"/"CRITICAL" color thresholds on the animation | Schematic presentation choices, colored from the real `D` severity value, not from any separately-fabricated formula |

## Animation implementation

`MechanicalAnimation.m` (fast rate, 0.05 s = 20 Hz): integrates
`theta += RPM * (2*pi/60) * SampleTime` each tick and redraws 4 rotated line
segments per rotor (pump, fan) by updating their XData/YData — genuinely
driven by simulation time and the RPM signal, not a pre-rendered loop, static
image, or GIF. Color (green/yellow/red) comes directly from the injected
severity `D` for whichever equipment is selected; the non-selected equipment
is dimmed, not hidden, so both are visible but only the active one is
colored. A separate small panel shows 4 dots moving along a line as the flow
indicator (speed proxied by RPM, see table above).

## Time-scale / multi-rate design (§16-17)

Two genuinely different sample times, each set via its block's own
`getSampleTimeImpl`:

```
MechanicalAnimation           : 0.05 s (20 Hz)  — smooth visual rotation
DigitalTwinCoreAndDashboard   : 2.0 s            — one supervisory tick
                                                    = SupervisoryTickHours
                                                    (default 1.0) simulated hour
```

**No Rate Transition block connects them**, and this is a deliberate design
choice, not an oversight: in this model, neither block's output feeds the
other. Both are driven directly by the user's Controls (which are Constant
blocks — rate-agnostic, Simulink resolves them at whatever rate the consumer
needs). The animation's RPM input and the core block's physics/AI/thermal
inputs are the SAME underlying control signals, just consumed at two
different rates by two independent blocks. A Rate Transition block exists to
solve data-dependency-across-rates problems; there isn't one here to solve,
so adding one would have been decorative. The genuine multi-rate behavior
this project's own physics requires — a fast, continuous shaft rotation
alongside a slow, hours-scale health/thermal trend (the RUL and thermal-twin
math elsewhere in this project already operates on an hours timescale, see
`docs/architecture.md` §H) — is what's implemented, just without an
unnecessary extra block.

## Model architecture

See `build_interactive_digital_twin.m`'s docstring for the full rationale.
Summary: the requested §9 subsystem hierarchy exists, named exactly as
specified, but subsystems `02`–`14` (Operating Conditions through Signal
Processing) are labeled, single-input, pass-through-to-Terminator containers,
each fed by a direct branch of the one most relevant control signal — not
threaded through a shared bus, because that would have meant a lot of
unverifiable wiring for a build with no execution-testing available, where
one mistake would break a 12-subsystem chain instead of staying local. All
real computation is centralized in `19_Visualization`, which contains both
custom blocks. Subsystems `15`–`18` (AI Fault Diagnosis, Health Index, RUL,
Maintenance Decision) each carry a REAL branch of the corresponding output
from `19_Visualization` — these are not placeholders.

## Faults supported
Exactly `cfg.faults.Pump` and `cfg.faults.Fan` (`config/project_config.m`) —
`Healthy`, `Cavitation`, `Unbalance`, `BearingDegradation`, `Misalignment`,
`EfficiencyDegradation` — no new fault names were introduced. The Fault
control is a single numeric code shared across both equipment types
(`interactive_code_tables.m`); selecting a fault that doesn't apply to the
chosen equipment (e.g. Pump + EfficiencyDegradation) falls back to Healthy
with a one-time warning rather than erroring out a live demo.

## Signals connected
Controls → `19_Visualization`'s 7 inputs (Equipment, Fault, D, RPM,
LoadFrac, Ambient, ITLoad) → `DigitalTwinCoreAndDashboard` (computes
everything) → 7 outputs (HI, RUL_hr, T_server, Margin, CoolEff,
DecisionCode, PredictedCode) → the 4 labeled output subsystems + a native
Simulink Scope (HI, T_server, Margin). `MechanicalAnimation` is driven
directly by RPM/D/Equipment, independent of the core block's rate.

## AI / HI / RUL / thermal integration
All real, all unchanged — see the architecture-decision table above. The
model does not duplicate, approximate, or bypass any of this logic.

## Validation
Run `validate_interactive_digital_twin()` (Phase 20): structural (model
opens, compiles, all expected subsystems present), functional (Healthy, Fan
BearingDegradation, Fan Unbalance, Pump Cavitation all run cleanly through
`run_single_operating_point.m`, using only real `cfg.faults` entries),
visual-structure (the animation/core blocks and the ports they depend on
exist and are wired — **this checks model structure, not rendered pixel
output**; no automated script can verify what a figure actually looks like,
that still needs a human to press Run and look), and integration (severity
`D` demonstrably changes Health Index, vibration RMS, and — for a
primary-thermal-path fault — cooling effectiveness).

**As of this document's writing, this has not been confirmed by an actual
MATLAB execution** — this entire interactive-Simulink layer was built in one
pass per an explicit "build it all" instruction, without the usual
phase-by-phase execution-confirmation gate used earlier in this project. Run
the validation function and `demo_healthy_visual()` before presenting this to
anyone.

## Known limitations
- No Simscape Multibody — animation is 2D schematic (see table above).
- No in-canvas Dashboard Knob/Dropdown controls — see
  `configure_interactive_dashboard.m` for the exact settings to add them
  yourself; this build used the guaranteed-correct Constant-block mechanism
  instead because the exact Dashboard block parameter API could not be
  verified without execution testing.
- The flow-indicator speed is a proxy (RPM, citing `Q ~ N`), not the exact
  simulated flow value.
- Subsystems `02`–`14` are organizational labels, not independent
  computation stages (see Model architecture above).
- No performance/timing measurements were taken (this build's §16
  performance-measurement phase was not reached).
- This has not been run in a real MATLAB/Simulink session by the builder —
  see Validation above.

## Launch commands

```matlab
addpath(genpath(pwd));

% Build (also backs up any existing InteractiveCoolingDigitalTwin.slx
% with a timestamp) and validate:
build_interactive_digital_twin();
validate_interactive_digital_twin();

% Open and press Run manually:
open_system('InteractiveCoolingDigitalTwin');

% Or run a scripted progressive-fault demo:
run_interactive_demo('Fan', 'BearingDegradation', [0, 0.3, 0.5, 0.7, 1.0], 5);

% Or the three prebuilt demo scenarios:
demo_healthy_visual();
demo_bearing_visual();
demo_severe_cooling_visual();
```
