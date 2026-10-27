# Ignition Web Dev Python resource: "telemetry"   (enable doPost only)
#
# MATLAB posts simulation results here. Nothing reaches a tag unless it passes
# the checks below, so a backend bug cannot put NaN, out-of-range numbers or
# unknown labels on the HMI.
#
# SETUP: replace API_KEY with the same random string used in commands.py and in
# MATLAB. Leave "Require Authentication" OFF for this resource.
#
# Payload kinds
#   telemetry  - full set of results (HEARTBEAT_FIELDS + TELEMETRY_FIELDS)
#   heartbeat  - liveness + last command result only (HEARTBEAT_FIELDS)
#   disconnect - sent by MATLAB on clean shutdown; marks the backend disconnected
#
# Python 2.7 / Jython compatible (Ignition Gateway scripting).

API_KEY = "CHANGE_ME"
ALLOWED_REMOTE = ["127.0.0.1", "0:0:0:0:0:0:0:1", "::1", "::ffff:127.0.0.1"]   # loopback only
TAG_ROOT = "[default]CoolingTwin/"
SCHEMA_VERSION = 1

# These lists mirror project config / the maintenance engine; check_consistency.py
# verifies they stay identical to the MATLAB side.
VALID_EQUIPMENT = ['Pump', 'Fan']
VALID_FAULTS = ['Healthy', 'Cavitation', 'Unbalance', 'BearingDegradation',
                'Misalignment', 'EfficiencyDegradation']
VALID_STATES = ['NORMAL', 'MONITOR', 'WARNING', 'MAINTENANCE_REQUIRED', 'CRITICAL']

HEARTBEAT_FIELDS = ['connection', 'commandResult', 'heartbeat']
TELEMETRY_FIELDS = ['injectedEquipment', 'injectedFault', 'predictedFault', 'severity',
                    'vibrationRMS', 'currentRMS', 'healthIndex', 'rulValid', 'rulHours',
                    'rulHistoryPoints', 'coolingEffectiveness', 'serverTemperatureC',
                    'thermalMarginC', 'maintenanceState', 'maintenanceReason',
                    'simTimeHours']

# payload field -> (tag path under CoolingTwin/, python type name)
FIELD_MAP = {
    'connection': ('Status/Connection', 'str'),
    'commandResult': ('Meta/LastCommandResult', 'str'),
    'heartbeat': ('Meta/Heartbeat', 'int'),
    'injectedEquipment': ('Status/InjectedEquipment', 'str'),
    'injectedFault': ('Status/InjectedFault', 'str'),
    'predictedFault': ('Status/PredictedFault', 'str'),
    'severity': ('Status/Severity', 'float'),
    'vibrationRMS': ('Status/VibrationRMS', 'float'),
    'currentRMS': ('Status/CurrentRMS', 'float'),
    'healthIndex': ('Status/HealthIndex', 'float'),
    'rulValid': ('Status/RULValid', 'bool'),
    'rulHours': ('Status/RULHours', 'float'),
    'rulHistoryPoints': ('Status/RULHistoryPoints', 'int'),
    'coolingEffectiveness': ('Status/CoolingEffectiveness', 'float'),
    'serverTemperatureC': ('Status/ServerTemperatureC', 'float'),
    'thermalMarginC': ('Status/ThermalMarginC', 'float'),
    'maintenanceState': ('Status/MaintenanceState', 'str'),
    'maintenanceReason': ('Status/MaintenanceReason', 'str'),
    'simTimeHours': ('Status/SimTimeHours', 'float'),
}

# payload field -> (min, max), inclusive. Anything outside is rejected.
RANGES = {
    'severity': (0.0, 1.0),
    'vibrationRMS': (0.0, 1000.0),
    'currentRMS': (0.0, 1000.0),
    'healthIndex': (0.0, 100.0),
    'rulHours': (-1.0e6, 1.0e6),
    'rulHistoryPoints': (0, 100000),
    'coolingEffectiveness': (0.0, 1.0),
    'serverTemperatureC': (-50.0, 200.0),
    'thermalMarginC': (-250.0, 250.0),
    'simTimeHours': (0.0, 1.0e7),
    'heartbeat': (0, 2000000000),
}

MAX_TEXT = 200

try:
    NUMBER_TYPES = (int, long, float)
except NameError:
    NUMBER_TYPES = (int, float)


def _header(request, name):
    headers = request.get('headers')
    if headers is None:
        return None
    target = name.lower()
    try:
        keys = list(headers.keys())
    except AttributeError:
        keys = list(headers.keySet())
    for k in keys:
        if str(k).lower() == target:
            return headers[k]
    return None


def _check_access(request):
    remote = request.get('remoteAddr')
    if remote not in ALLOWED_REMOTE:
        return "forbidden_remote:%s" % (remote,)
    key = _header(request, 'X-Twin-Key')
    if key is None or str(key) != API_KEY:
        return "bad_key"
    return None


def _body(request):
    # The docs show both request['data'] (parsed) and request['postData'] (raw
    # text) for different versions; accept either.
    data = request.get('data')
    if isinstance(data, dict):
        return data
    for key in ('postData', 'data'):
        raw = request.get(key)
        if raw is None:
            continue
        try:
            parsed = system.util.jsonDecode(str(raw))
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            pass
    return None


def _is_number(v):
    return isinstance(v, NUMBER_TYPES) and not isinstance(v, bool)


def _check_value(field, value):
    """Return (clean_value, error). Strict type, range and whitelist checks."""
    kind = FIELD_MAP[field][1]
    if kind == 'bool':
        if not isinstance(value, bool):
            return None, "%s must be boolean" % field
        return bool(value), None
    if kind == 'str':
        if not (hasattr(value, 'lower') and hasattr(value, 'strip')):
            return None, "%s must be text" % field
        text = str(value)
        if len(text) > MAX_TEXT:
            return None, "%s too long" % field
        if field == 'injectedEquipment' and text not in VALID_EQUIPMENT:
            return None, "unknown equipment"
        if field in ('injectedFault', 'predictedFault') and text not in VALID_FAULTS:
            return None, "unknown fault label in %s" % field
        if field == 'maintenanceState' and text not in VALID_STATES:
            return None, "unknown maintenance state"
        if field == 'connection' and text != 'CONNECTED':
            return None, "connection must be CONNECTED"
        return text, None
    if not _is_number(value):
        return None, "%s must be a number" % field
    if value != value or abs(value) > 1.0e12:
        return None, "%s is NaN or infinite" % field
    if kind == 'int':
        if value != int(value):
            return None, "%s must be an integer" % field
        value = int(value)
    else:
        value = float(value)
    if field in RANGES:
        lo, hi = RANGES[field]
        if value < lo or value > hi:
            return None, "%s out of range" % field
    return value, None


def doPost(request, session):
    problem = _check_access(request)
    if problem:
        return {'json': {'ok': False, 'error': problem}}

    p = _body(request)
    if p is None:
        return {'json': {'ok': False, 'error': 'body is not valid JSON object'}}
    if p.get('schema') != SCHEMA_VERSION:
        return {'json': {'ok': False, 'error': 'unsupported schema'}}

    kind = p.get('kind')
    paths = []
    values = []

    if kind == 'disconnect':
        paths.append(TAG_ROOT + "Status/Connection")
        values.append("BACKEND DISCONNECTED")
    elif kind in ('telemetry', 'heartbeat'):
        required = list(HEARTBEAT_FIELDS)
        if kind == 'telemetry':
            required += TELEMETRY_FIELDS
        for field in required:
            if field not in p:
                return {'json': {'ok': False, 'error': 'missing field %s' % field}}
            clean, err = _check_value(field, p[field])
            if err:
                return {'json': {'ok': False, 'error': err}}
            paths.append(TAG_ROOT + FIELD_MAP[field][0])
            values.append(clean)
    else:
        return {'json': {'ok': False, 'error': 'unknown kind'}}

    paths.append(TAG_ROOT + "Meta/LastUpdate")
    values.append(system.date.now())

    results = system.tag.writeBlocking(paths, values)
    failed = [paths[i] for i in range(len(paths)) if not results[i].isGood()]
    if failed:
        return {'json': {'ok': False, 'error': 'tag write failed', 'tags': failed}}
    return {'json': {'ok': True, 'written': len(paths)}}
