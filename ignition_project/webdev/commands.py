# Ignition Web Dev Python resource: "commands"   (enable doGet only)
#
# MATLAB polls this endpoint to read the operator's commands. It exposes NO way
# to run anything: it only reads a fixed list of tags and returns their values.
#
# SETUP: replace API_KEY below with your own random string, and put the SAME
# string in MATLAB (env var COOLING_TWIN_API_KEY or src/ignition/ignition_secret.txt).
# Leave "Require Authentication" OFF for this resource: access is restricted by
# the localhost check and the X-Twin-Key header instead.
#
# Python 2.7 / Jython compatible (Ignition Gateway scripting).

API_KEY = "CHANGE_ME"
ALLOWED_REMOTE = ["127.0.0.1", "0:0:0:0:0:0:0:1", "::1", "::ffff:127.0.0.1"]   # loopback only
TAG_ROOT = "[default]CoolingTwin/"

# (tag name under CoolingTwin/Commands/, JSON key returned to MATLAB)
COMMAND_MAP = [
    ("Equipment", "equipment"),
    ("FaultType", "faultType"),
    ("Severity", "severity"),
    ("RPM", "rpm"),
    ("LoadFraction", "loadFraction"),
    ("AmbientC", "ambientC"),
    ("ITLoadKW", "itLoadKW"),
    ("Run", "run"),
    ("ResetSeq", "resetSeq"),
]

# (tag name under CoolingTwin/Meta/, JSON key) - echoed so MATLAB can verify
# that its last telemetry post really reached the Gateway (round trip).
META_MAP = [
    ("Heartbeat", "heartbeat"),
    ("LastUpdate", "lastUpdateMs"),
    ("LastCommandResult", "lastCommandResult"),
]


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


def _plain(value):
    # java.util.Date -> epoch milliseconds; everything else passes through.
    if value is None:
        return None
    if hasattr(value, 'getTime'):
        return int(value.getTime())
    return value


def doGet(request, session):
    problem = _check_access(request)
    if problem:
        return {'json': {'ok': False, 'error': problem}}

    paths = [TAG_ROOT + "Commands/" + n for n, _k in COMMAND_MAP]
    paths += [TAG_ROOT + "Meta/" + n for n, _k in META_MAP]
    values = system.tag.readBlocking(paths)

    out = {'ok': True}
    bad = []
    keys = [k for _n, k in COMMAND_MAP] + [k for _n, k in META_MAP]
    for i in range(len(paths)):
        qv = values[i]
        if qv.quality.isGood():
            out[keys[i]] = _plain(qv.value)
        else:
            if i < len(COMMAND_MAP):
                bad.append(paths[i])
            else:
                out[keys[i]] = None
    if bad:
        return {'json': {'ok': False, 'error': 'bad_quality_command_tags', 'tags': bad}}
    return {'json': out}
