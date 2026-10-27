"""Single source of truth for the CoolingTwin tag namespace.

Every consumer of the tag contract is generated from, or checked against, this
file: the importable tag JSON (generate_tags.py), the manifest document, the
Web Dev scripts (check_consistency.py) and the MATLAB adapter field lists.

Each entry: (name, ignition_data_type, default_value, engineering_unit, writer, description)

Conventions
- Commands/* are written by Perspective controls and READ by the MATLAB adapter
  (through the 'commands' Web Dev endpoint).
- Status/* and Meta/* are written ONLY by the 'telemetry' Web Dev endpoint
  (by convention; the tags are not locked read-only, see docs).
- All values originate from the MATLAB simulation (run_single_operating_point.m),
  never from Ignition itself. Everything on screen is simulated data.
"""

COMMAND_TAGS = [
    ("Equipment",    "String",  "Fan",     "",     "Perspective", "Target equipment: Pump or Fan"),
    ("FaultType",    "String",  "Healthy", "",     "Perspective", "Injected fault label, exactly as defined in cfg.faults"),
    ("Severity",     "Float8",  0.0,       "",     "Perspective", "Injected fault severity D, fraction 0..1"),
    ("RPM",          "Float8",  1450.0,    "rpm",  "Perspective", "Shaft speed, within cfg.operating.speed_rpm_range"),
    ("LoadFraction", "Float8",  0.8,       "",     "Perspective", "Load fraction 0.3..1.0 (cfg.operating.load_pct_range / 100)"),
    ("AmbientC",     "Float8",  24.0,      "degC", "Perspective", "Ambient temperature, within cfg.operating.ambient_C_range"),
    ("ITLoadKW",     "Float8",  40.0,      "kW",   "Perspective", "IT heat load 10..100 kW (adapter design bound)"),
    ("Run",          "Boolean", False,     "",     "Perspective", "True = adapter advances the simulation one tick per tick interval"),
    ("ResetSeq",     "Int4",    0,         "",     "Perspective", "Increment to reset the simulation history (new trajectory)"),
]

STATUS_TAGS = [
    ("Connection",           "String",  "BACKEND DISCONNECTED", "",     "Telemetry endpoint", "CONNECTED while the adapter posts; BACKEND DISCONNECTED after a clean stop"),
    ("InjectedEquipment",    "String",  "",    "",     "Telemetry endpoint", "Equipment the injected fault was applied to"),
    ("InjectedFault",        "String",  "",    "",     "Telemetry endpoint", "Fault that was INJECTED (ground truth of the simulation)"),
    ("PredictedFault",       "String",  "",    "",     "Telemetry endpoint", "Fault PREDICTED by the trained classifier (independent of InjectedFault)"),
    ("Severity",             "Float8",  0.0,   "",     "Telemetry endpoint", "Injected severity D actually simulated, fraction 0..1"),
    ("VibrationRMS",         "Float8",  0.0,   "g",    "Telemetry endpoint", "Vibration RMS from extract_vibration_features"),
    ("CurrentRMS",           "Float8",  0.0,   "A",    "Telemetry endpoint", "Motor current RMS from extract_mcsa_features"),
    ("HealthIndex",          "Float8",  0.0,   "",     "Telemetry endpoint", "Health Index 0..100 from compute_health_index"),
    ("RULValid",             "Boolean", False, "",     "Telemetry endpoint", "False when estimate_rul has no degrading trend (RUL then NOT available)"),
    ("RULHours",             "Float8",  0.0,   "h",    "Telemetry endpoint", "RUL in simulated hours; meaningful only when RULValid is true"),
    ("RULHistoryPoints",     "Int4",    0,     "",     "Telemetry endpoint", "Number of history points behind the RUL estimate (small = provisional)"),
    ("CoolingEffectiveness", "Float8",  0.0,   "",     "Telemetry endpoint", "cooling_effectiveness_from_degradation output, 0..1"),
    ("ServerTemperatureC",   "Float8",  0.0,   "degC", "Telemetry endpoint", "Server inlet temperature from thermal_digital_twin"),
    ("ThermalMarginC",       "Float8",  0.0,   "degC", "Telemetry endpoint", "T_safe minus server temperature"),
    ("MaintenanceState",     "String",  "NO DATA", "", "Telemetry endpoint", "maintenance_decision_engine level (5 states)"),
    ("MaintenanceReason",    "String",  "",    "",     "Telemetry endpoint", "First reason string from the decision engine"),
    ("SimTimeHours",         "Float8",  0.0,   "h",    "Telemetry endpoint", "Simulated time in hours (NOT wall-clock time)"),
]

META_TAGS = [
    ("LastUpdate",        "DateTime", None,                "",  "Telemetry endpoint", "Gateway time of the last accepted post (any kind)"),
    ("Heartbeat",         "Int4",     0,                   "",  "Telemetry endpoint", "Adapter loop counter, increments every poll"),
    ("LastCommandResult", "String",   "NO COMMAND YET",    "",  "Telemetry endpoint", "OK, or REJECTED/ENGINE ERROR with the reason"),
    ("StaleAfterSeconds", "Int4",     10,                  "s", "Operator",           "Telemetry older than this is shown as BACKEND DISCONNECTED"),
]

GROUPS = [("Commands", COMMAND_TAGS), ("Status", STATUS_TAGS), ("Meta", META_TAGS)]

DATATYPE_TO_PY = {"Float8": "float", "Int4": "int", "Boolean": "bool", "String": "str", "DateTime": "datetime"}
