# Mid-Sem / Viva Demonstration Guide (5–10 minutes)

**Before you present:** run `report = test_run_single_operating_point();` and
confirm all 5 tests pass. Do not present on an unconfirmed backend — see
`docs/INTERACTIVE_DIGITAL_TWIN.md` §12.

## Setup (do this before the audience arrives)
```matlab
cd('<project root>')
addpath(genpath(pwd));
app = launch_cooling_digital_twin();   % trains+saves the model on first run —
                                         % do this once before presenting so
                                         % the audience doesn't wait on it
```

## 0:00 – 0:30 — Opening state
The dashboard opens on the healthy baseline: IT Load 40 kW, Ambient 24°C,
Fault Healthy, Severity 0%, Health Index ≈100, Status NORMAL. Say: "This is
the system's resting state — everything you'll see change from here is
computed live by the same MATLAB functions validated in the project's 10
experiments, not scripted."

## 0:30 – 2:00 — Manual fault injection
1. Equipment → **Fan**. Fault Type → **BearingDegradation**.
2. Move Severity to ~30% and click **RUN**.
3. Point out, in order: the vibration waveform/spectrum changed → the AI
   Predicted fault updates (note it's shown separately from the injected
   fault — "the AI isn't being told the answer, it's diagnosing from
   features") → Health Index dropped → RUL now shows a number (or "N/A" if
   the trend isn't established yet from just one step — explain this is
   intentional: the system won't fabricate a RUL without a real trend).
4. Increase Severity to ~60%, click RUN again. Health Index drops further;
   point out the Pump/Fan/Cooling/Thermal status indicators update, each
   tied to a real value (D, cooling effectiveness, thermal margin) — "none of
   these four boxes are decorative."

## 2:00 – 4:00 — Scenario B: progressive degradation
Click **FAULT SWEEP** (or run `demo_bearing_degradation` from the command
line as a narrated alternative). Narrate the causal chain as it plays out:
"D increases → vibration/current signatures change → the AI's diagnosis
tracks it → Health Index falls → RUL falls → maintenance status escalates."
Switch to the Trends tab to show Health Index, RUL, temperature, and D all
moving together over simulated time.

## 4:00 – 7:00 — Scenario C: reactive vs predictive maintenance
Run `demo_severe_degradation` in the command window (this reuses Experiment 9
exactly — say so explicitly: "this is not a dashboard-only demo trick, it's
the same experiment already in the report"). Walk through the printed table:
no-intervention peak temperature vs. reactive (intervenes only after the
threshold is violated) vs. predictive (intervenes earlier, using Health
Index/RUL/thermal-margin trends) — read the actual numbers from that run, not
memorized ones, since they can shift slightly with the random scenario draw.

## 7:00 – 8:30 — Return to healthy, take questions
Click **HEALTHY** to reset. Good questions to be ready for:
- *"Is the Simulink model actually running any of this?"* — No; be honest
  that the `.slx` is a preserved architecture scaffold, not the live engine
  (see `docs/INTERACTIVE_DIGITAL_TWIN.md` §3/§13). The interactive engine is
  the MATLAB backend, tested independently in `tests/test_run_single_operating_point.m`.
- *"Does the AI ever get it wrong?"* — Yes, and that's expected and shown
  honestly (the Predicted-fault field can disagree with the injected fault);
  don't claim otherwise.
- *"Is this connected to a real sensor?"* — Not yet; explain the
  `generate_vibration_signal`/`generate_current_signal` seam described in
  §14 of `docs/INTERACTIVE_DIGITAL_TWIN.md` as the planned integration point.

## 8:30 – end — Close
"This dashboard is a live front-end over the same validated physics, AI,
health, RUL, thermal, and maintenance-decision code already used in the
project's 10 experiments — nothing here was recomputed or reimplemented for
the demo."
