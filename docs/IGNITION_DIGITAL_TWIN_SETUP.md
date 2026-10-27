# Ignition Digital Twin — Setup and Runbook (vertical slice)

This is the **vertical slice**: one scenario controlled from Ignition → one call
to the real MATLAB engine → real output tags visible in Perspective. The full
set of views comes after this slice is confirmed working on your Gateway.

**Everything shown is SIMULATED data** from `src/interactive/run_single_operating_point.m`
(the project's existing physics, fault, sensor, AI, Health Index, RUL, thermal
and maintenance-decision functions). Nothing controls physical equipment.

Environment this was designed for (verified from your outputs): Windows, Ignition
**8.3.10 Maker Edition** at `http://localhost:8088` with Perspective and Web Dev,
MATLAB **R2024a**. No Python and no MATLAB toolbox is needed.

## 1. Architecture

```
Perspective controls ──write──> Commands/* tags
                                     │  GET /system/webdev/CoolingDigitalTwin/commands
                                     ▼
                      MATLAB adapter (run_ignition_adapter.m)
                        validate_ignition_command  ← rejects anything not allowed
                        ignition_engine_step → run_single_operating_point (UNCHANGED)
                                     │  POST /system/webdev/CoolingDigitalTwin/telemetry
                                     ▼
              Gateway script validates again → Status/* and Meta/* tags → Perspective
```

- MATLAB is only a **client**. There is no MATLAB server and no endpoint that
  runs commands; the Gateway exposes only two fixed endpoints.
- Both endpoints require the `X-Twin-Key` header **and** a loopback client address.
- Commands are validated twice-over in effect: only whitelisted labels and numeric
  ranges from the project config ever reach the engine; telemetry is range- and
  label-checked again before any tag is written.

## 2. One-time MATLAB setup

Pick a random API key (any string; keep it private) and make MATLAB aware of it:

```matlab
s = ['a':'z' '0':'9']; key = s(randi(numel(s), 1, 24))      % prints your key
fid = fopen(fullfile('src','ignition','ignition_secret.txt'),'w'); fprintf(fid,'%s',key); fclose(fid);
```

(Alternatively `setenv('COOLING_TWIN_API_KEY', key)` each session.) Then confirm the
offline tests, which need no Gateway:

```matlab
addpath(genpath(pwd));
report = test_ignition_adapter();        % expect: all tests PASSED
```

## 3. Gateway / Designer setup (manual — these cannot be automated from here)

**A. Tags.** Designer → Tag Browser → select the `default` provider → right-click →
**Import Tags** → choose `ignition_project/tags/CoolingTwin_tags.json`. Expect a
`CoolingTwin` folder with `Commands`, `Status`, `Meta` (30 tags). If Designer rejects
the file, copy the exact error to me; the JSON follows the standard tag-export
structure but could not be import-tested without a Designer.

**B. Web Dev resources** (project `CoolingDigitalTwin`; you already created `ping`):

1. Project Browser → Web Dev → right-click → **New Python Resource**, name `commands`.
   Enable **doGet** only. Paste the contents of `ignition_project/webdev/commands.py`.
2. Replace `CHANGE_ME` with **your key** (same text as in `ignition_secret.txt`).
3. Leave *Require Authentication* **off** (access is controlled by the key + loopback check).
4. Repeat for a resource named `telemetry`, enable **doPost** only, paste
   `ignition_project/webdev/telemetry.py`, same key.
5. Save the project (this publishes it to the Gateway).

**C. Live check from MATLAB** (needs A and B):

```matlab
report = test_ignition_live();           % expect: all 6 checks PASSED
```
This round-trips a heartbeat, posts one real engine step, and confirms the Gateway
**rejects** an unknown fault label and severity > 1.

**D. Minimal Perspective test view.** Designer → Perspective → Views → New View,
name `SliceTest` (Coordinate or Flex container). Add these components. For each
*bidirectional* binding use a **Tag binding** with the path shown
(`[default]CoolingTwin/...`).

| Component | Property | Binding / value |
|---|---|---|
| Dropdown "Equipment" | `props.value` (bidirectional) | `Commands/Equipment`; options `Pump`, `Fan` |
| Dropdown "Fault" | `props.value` (bidirectional) | `Commands/FaultType`; options: `Healthy`, `Cavitation`, `Unbalance`, `BearingDegradation`, `Misalignment`, `EfficiencyDegradation` (an option not valid for the chosen equipment is rejected by the adapter and shown in *Last command result*) |
| Slider or Numeric Entry "Severity" | `props.value` (bidirectional) | `Commands/Severity`, min 0, max 1, step 0.05 |
| Numeric Entry "RPM" | value (bidirectional) | `Commands/RPM`, min 1200, max 1800 |
| Numeric Entry "Load" | value (bidirectional) | `Commands/LoadFraction`, min 0.3, max 1.0 |
| Numeric Entry "Ambient °C" | value (bidirectional) | `Commands/AmbientC`, min 18, max 32 |
| Numeric Entry "IT load kW" | value (bidirectional) | `Commands/ITLoadKW`, min 10, max 100 |
| Toggle Switch "Run" | `props.selected` (bidirectional) | `Commands/Run` |
| Button "Reset" | `onActionPerformed` script (below) | writes `Commands/ResetSeq` + 1 |
| Labels (read-only) | `props.text` | `Status/InjectedFault`, `Status/PredictedFault`, `Status/Severity`, `Status/HealthIndex`, `Status/RULHours`, `Status/RULValid`, `Status/RULHistoryPoints`, `Status/CoolingEffectiveness`, `Status/ServerTemperatureC`, `Status/ThermalMarginC`, `Status/MaintenanceState`, `Status/SimTimeHours`, `Meta/LastCommandResult`, `Meta/LastUpdate` |
| Label "Backend" | `props.text` | expression below |

Reset button script:
```python
path = "[default]CoolingTwin/Commands/ResetSeq"
current = system.tag.readBlocking([path])[0].value
system.tag.writeBlocking([path], [int(current) + 1])
```

**Backend / stale indicator** (expression binding on the "Backend" label — verify the
syntax in the expression editor, which flags errors immediately):
```
if(isNull({[default]CoolingTwin/Meta/LastUpdate}), "BACKEND DISCONNECTED",
 if(abs(secondsBetween({[default]CoolingTwin/Meta/LastUpdate}, now(1000))) > {[default]CoolingTwin/Meta/StaleAfterSeconds}
    || {[default]CoolingTwin/Status/Connection} != "CONNECTED",
  "BACKEND DISCONNECTED", "CONNECTED"))
```
Also show **RUL** as `N/A` when `Status/RULValid` is false, and label it *provisional*
while `Status/RULHistoryPoints` < 5 (the RUL then rests on only a few points).

Open the page: add the view to the project's page configuration at `/`, then browse to
`http://localhost:8088/data/perspective/client/CoolingDigitalTwin`.
(Maker allows 10 Perspective sessions; close old browser tabs if you hit the limit.)

## 4. Run the slice

```matlab
run_ignition_adapter           % prints one line per simulation tick
```
In Perspective: pick **Fan**, **Healthy**, severity 0, switch **Run** on → watch the
labels update every ≈2 s (each tick = **1 simulated hour**; wall-clock and simulated
time are different things). Then change Fault to `BearingDegradation`, raise severity
0.2 → 0.5 → 0.8 → 1.0 and watch Injected vs Predicted fault, Health Index, RUL,
cooling effectiveness, temperature, thermal margin and Maintenance state move.

**Stop** (it never runs forever): Ctrl+C in MATLAB, or create the file
`src/ignition/STOP_ADAPTER`, or wait for the 30-minute limit
(`run_ignition_adapter('MaxRuntimeS', 600)` to shorten). On any exit the adapter posts a
disconnect, and Perspective shows **BACKEND DISCONNECTED**. To stop for real, also close
the Perspective session; Ignition itself keeps running as a Windows service until you
stop it from the Ignition Gateway control utility.

## 5. Behavior you should know before demonstrating

- **First tick after a start/reset shows the server temperature equal to ambient.** The
  existing thermal model starts each trajectory at ambient; the next tick shows the
  settled value. This is the engine's real behavior, not a display fault.
- **RUL is "N/A" until there is a degrading Health-Index trend** (≥ 2 points, falling).
  A RUL from only a few ticks is provisional and can be small; the tag
  `Status/RULHistoryPoints` tells you how many points back it.
- **The AI may mislabel a Healthy fan.** In the earlier backend test, a healthy fan
  (D = 0) was predicted as `EfficiencyDegradation`; that fault leaves almost no vibration
  or current signature, and the classifier does not see flow, pressure or power. The
  display shows the **injected** and **predicted** faults separately precisely so such a
  disagreement is visible, not hidden. The model has deliberately not been altered.
- Changing the **equipment or fault label** starts a new trajectory (history cleared);
  changing severity, RPM, load, ambient or IT load continues the current one.
- There is **no classifier confidence** and no classifier severity estimate: the model
  returns labels only, so no such tags exist.
- Flow rate (for flow-driven animation) is **not yet exposed**; a thin wrapper around the
  existing `pump_model`/`fan_model` will add it in the next step.

## 6. Troubleshooting (paste me the exact text if stuck)

| Symptom | Likely cause |
|---|---|
| `Gateway rejected request: bad_key` | Key in the Web Dev script ≠ key in MATLAB |
| `forbidden_remote:<address>` | Client address not in `ALLOWED_REMOTE` (loopback only); tell me the address shown |
| `body is not valid JSON object` | This Gateway delivers the POST body under another request key; send me the exact message and I will adapt `_body()` |
| `bad_quality_command_tags` | Tags not imported, or imported to a provider other than `default` |
| HTTP 404 from `webread` | Resource not saved/published, wrong name, or wrong project name |
| `API key not set` | See section 2 |
| Labels never change but adapter prints ticks | Telemetry posts failing: read the adapter's "Telemetry post failed" line |

## 7. Security and limits (honest)

The API key is stored in a plain text file and in the Web Dev scripts; the loopback check
and key are appropriate for a **local demonstration**, not a hardened deployment. Status
tags are written only by the telemetry endpoint **by convention** — they are not locked
read-only. Do not expose the Gateway beyond localhost with these scripts as they are.
