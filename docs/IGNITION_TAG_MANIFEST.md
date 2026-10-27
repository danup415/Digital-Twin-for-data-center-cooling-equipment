# Ignition Tag Manifest — `CoolingTwin`

Generated from `ignition_project/tools/tag_spec.py` by `generate_tags.py`. Do not edit by hand; edit the spec and regenerate.

All tags live in the `default` tag provider under `CoolingTwin/`. Every value is **simulated data produced by the MATLAB engine** (`src/interactive/run_single_operating_point.m`), never by Ignition.

## Commands/

| Tag | Type | Default | Unit | Written by | Meaning |
|---|---|---|---|---|---|
| `Commands/Equipment` | String | 'Fan' | - | Perspective | Target equipment: Pump or Fan |
| `Commands/FaultType` | String | 'Healthy' | - | Perspective | Injected fault label, exactly as defined in cfg.faults |
| `Commands/Severity` | Float8 | 0.0 | - | Perspective | Injected fault severity D, fraction 0..1 |
| `Commands/RPM` | Float8 | 1450.0 | rpm | Perspective | Shaft speed, within cfg.operating.speed_rpm_range |
| `Commands/LoadFraction` | Float8 | 0.8 | - | Perspective | Load fraction 0.3..1.0 (cfg.operating.load_pct_range / 100) |
| `Commands/AmbientC` | Float8 | 24.0 | degC | Perspective | Ambient temperature, within cfg.operating.ambient_C_range |
| `Commands/ITLoadKW` | Float8 | 40.0 | kW | Perspective | IT heat load 10..100 kW (adapter design bound) |
| `Commands/Run` | Boolean | False | - | Perspective | True = adapter advances the simulation one tick per tick interval |
| `Commands/ResetSeq` | Int4 | 0 | - | Perspective | Increment to reset the simulation history (new trajectory) |

## Status/

| Tag | Type | Default | Unit | Written by | Meaning |
|---|---|---|---|---|---|
| `Status/Connection` | String | 'BACKEND DISCONNECTED' | - | Telemetry endpoint | CONNECTED while the adapter posts; BACKEND DISCONNECTED after a clean stop |
| `Status/InjectedEquipment` | String | '' | - | Telemetry endpoint | Equipment the injected fault was applied to |
| `Status/InjectedFault` | String | '' | - | Telemetry endpoint | Fault that was INJECTED (ground truth of the simulation) |
| `Status/PredictedFault` | String | '' | - | Telemetry endpoint | Fault PREDICTED by the trained classifier (independent of InjectedFault) |
| `Status/Severity` | Float8 | 0.0 | - | Telemetry endpoint | Injected severity D actually simulated, fraction 0..1 |
| `Status/VibrationRMS` | Float8 | 0.0 | g | Telemetry endpoint | Vibration RMS from extract_vibration_features |
| `Status/CurrentRMS` | Float8 | 0.0 | A | Telemetry endpoint | Motor current RMS from extract_mcsa_features |
| `Status/HealthIndex` | Float8 | 0.0 | - | Telemetry endpoint | Health Index 0..100 from compute_health_index |
| `Status/RULValid` | Boolean | False | - | Telemetry endpoint | False when estimate_rul has no degrading trend (RUL then NOT available) |
| `Status/RULHours` | Float8 | 0.0 | h | Telemetry endpoint | RUL in simulated hours; meaningful only when RULValid is true |
| `Status/RULHistoryPoints` | Int4 | 0 | - | Telemetry endpoint | Number of history points behind the RUL estimate (small = provisional) |
| `Status/CoolingEffectiveness` | Float8 | 0.0 | - | Telemetry endpoint | cooling_effectiveness_from_degradation output, 0..1 |
| `Status/ServerTemperatureC` | Float8 | 0.0 | degC | Telemetry endpoint | Server inlet temperature from thermal_digital_twin |
| `Status/ThermalMarginC` | Float8 | 0.0 | degC | Telemetry endpoint | T_safe minus server temperature |
| `Status/MaintenanceState` | String | 'NO DATA' | - | Telemetry endpoint | maintenance_decision_engine level (5 states) |
| `Status/MaintenanceReason` | String | '' | - | Telemetry endpoint | First reason string from the decision engine |
| `Status/SimTimeHours` | Float8 | 0.0 | h | Telemetry endpoint | Simulated time in hours (NOT wall-clock time) |

## Meta/

| Tag | Type | Default | Unit | Written by | Meaning |
|---|---|---|---|---|---|
| `Meta/LastUpdate` | DateTime | (none) | - | Telemetry endpoint | Gateway time of the last accepted post (any kind) |
| `Meta/Heartbeat` | Int4 | 0 | - | Telemetry endpoint | Adapter loop counter, increments every poll |
| `Meta/LastCommandResult` | String | 'NO COMMAND YET' | - | Telemetry endpoint | OK, or REJECTED/ENGINE ERROR with the reason |
| `Meta/StaleAfterSeconds` | Int4 | 10 | s | Operator | Telemetry older than this is shown as BACKEND DISCONNECTED |

## Telemetry payload -> tag mapping

See `ignition_project/webdev/telemetry.py` (`FIELD_MAP`) for the exact payload-field-to-tag mapping; `check_consistency.py` verifies it against this manifest and the MATLAB payload builder.
