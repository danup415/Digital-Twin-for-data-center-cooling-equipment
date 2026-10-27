"""Logic tests for ignition_project/webdev/*.py using a stubbed Ignition runtime.

Usage (from the project root):  python ignition_project/tools/test_webdev_logic.py

SCOPE: this executes the real script code with a fake `system` module, so it
verifies the validation/authorization/write logic. It does NOT prove the
scripts run on a Gateway (Jython 2.7, real request dict, real tag provider);
that needs a live Ignition test (see docs/IGNITION_DIGITAL_TWIN_SETUP.md).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
KEY = "test-key"


class FakeQuality(object):
    def __init__(self, good=True):
        self._good = good

    def isGood(self):
        return self._good


class FakeQV(object):
    def __init__(self, value, good=True):
        self.value = value
        self.quality = FakeQuality(good)


class FakeSystem(object):
    def __init__(self):
        self.written = {}
        self.read_values = {}
        self.fail_writes = False
        outer = self

        class Util(object):
            @staticmethod
            def jsonDecode(text):
                return json.loads(text)

        class Tag(object):
            @staticmethod
            def writeBlocking(paths, values):
                for p, v in zip(paths, values):
                    outer.written[p] = v
                return [FakeQuality(not outer.fail_writes) for _ in paths]

            @staticmethod
            def readBlocking(paths):
                return [outer.read_values.get(p, FakeQV(None, good=False)) for p in paths]

        class Date(object):
            @staticmethod
            def now():
                return "NOW"

        self.util, self.tag, self.date = Util(), Tag(), Date()


def load(script, fake):
    path = os.path.join(ROOT, "ignition_project", "webdev", script)
    ns = {"system": fake}
    with open(path) as f:
        source = f.read().replace('API_KEY = "CHANGE_ME"', 'API_KEY = "%s"' % KEY)
    exec(compile(source, path, "exec"), ns)
    return ns


def request(body=None, key=KEY, remote="127.0.0.1", raw_text=False):
    req = {"remoteAddr": remote, "headers": {"X-Twin-Key": key} if key is not None else {}}
    if body is not None:
        req["data"] = json.dumps(body) if raw_text else body
    return req


def good_telemetry():
    return {"kind": "telemetry", "schema": 1, "tsUtc": "2026-01-01T00:00:00.000Z",
            "connection": "CONNECTED", "commandResult": "OK", "heartbeat": 7,
            "injectedEquipment": "Fan", "injectedFault": "BearingDegradation",
            "predictedFault": "BearingDegradation", "severity": 0.3, "vibrationRMS": 0.12,
            "currentRMS": 9.5, "healthIndex": 50.0, "rulValid": True, "rulHours": 40.0,
            "rulHistoryPoints": 5, "coolingEffectiveness": 0.95, "serverTemperatureC": 26.9,
            "thermalMarginC": 5.1, "maintenanceState": "WARNING",
            "maintenanceReason": "Health Index 50 <= warning", "simTimeHours": 4.0}


passed, failed = [], []


def case(name, condition, detail=""):
    (passed if condition else failed).append(name)
    print("%s  %s%s" % ("PASS" if condition else "FAIL", name, ("  -> " + str(detail)) if detail and not condition else ""))


def run():
    # ---------------- telemetry.py ----------------
    def post(body, **kw):
        fake = FakeSystem()
        ns = load("telemetry.py", fake)
        out = ns["doPost"](request(body, **kw), None)["json"]
        return out, fake

    out, fake = post(good_telemetry())
    case("telemetry: valid payload accepted", out.get("ok") is True, out)
    case("telemetry: writes injected AND predicted fault to separate tags",
         fake.written.get("[default]CoolingTwin/Status/InjectedFault") == "BearingDegradation"
         and "[default]CoolingTwin/Status/PredictedFault" in fake.written)
    case("telemetry: LastUpdate set by the Gateway (not the client)",
         fake.written.get("[default]CoolingTwin/Meta/LastUpdate") == "NOW")

    out, _ = post(good_telemetry(), raw_text=True)
    case("telemetry: JSON text body accepted", out.get("ok") is True, out)

    hb = {"kind": "heartbeat", "schema": 1, "tsUtc": "x", "connection": "CONNECTED",
          "commandResult": "REJECTED: bad", "heartbeat": 3}
    out, fake = post(hb)
    case("telemetry: heartbeat accepted and writes only liveness tags",
         out.get("ok") is True and "[default]CoolingTwin/Status/HealthIndex" not in fake.written, out)

    out, fake = post({"kind": "disconnect", "schema": 1})
    case("telemetry: disconnect marks BACKEND DISCONNECTED",
         out.get("ok") is True
         and fake.written.get("[default]CoolingTwin/Status/Connection") == "BACKEND DISCONNECTED", out)

    out, fake = post(good_telemetry(), key="wrong")
    case("telemetry: wrong API key rejected, nothing written", out.get("ok") is False and not fake.written, out)
    out, fake = post(good_telemetry(), key=None)
    case("telemetry: missing API key rejected", out.get("ok") is False and not fake.written, out)
    out, fake = post(good_telemetry(), remote="192.168.1.50")
    case("telemetry: non-localhost client rejected", out.get("ok") is False and not fake.written, out)

    def mutate(**changes):
        body = good_telemetry()
        body.update(changes)
        return body

    for label, body in [
        ("unknown fault label", mutate(injectedFault="Bogus")),
        ("unknown predicted label", mutate(predictedFault="Bogus")),
        ("unknown maintenance state", mutate(maintenanceState="PANIC")),
        ("unknown equipment", mutate(injectedEquipment="Chiller")),
        ("severity above 1", mutate(severity=1.5)),
        ("negative severity", mutate(severity=-0.1)),
        ("health index above 100", mutate(healthIndex=140.0)),
        ("NaN temperature", mutate(serverTemperatureC=float("nan"))),
        ("absurd temperature", mutate(serverTemperatureC=5000.0)),
        ("string where number expected", mutate(healthIndex="fifty")),
        ("boolean where number expected", mutate(severity=True)),
        ("number where boolean expected", mutate(rulValid=1)),
        ("non-integer heartbeat", mutate(heartbeat=2.5)),
        ("wrong schema", mutate(schema=2)),
        ("unknown kind", mutate(kind="hack")),
        ("connection not CONNECTED", mutate(connection="whatever")),
        ("overlong text", mutate(maintenanceReason="x" * 500)),
    ]:
        out, fake = post(body)
        case("telemetry: rejects " + label, out.get("ok") is False and not fake.written, out)

    body = good_telemetry()
    del body["healthIndex"]
    out, fake = post(body)
    case("telemetry: rejects missing field", out.get("ok") is False and not fake.written, out)

    fake = FakeSystem()
    fake.fail_writes = True
    ns = load("telemetry.py", fake)
    out = ns["doPost"](request(good_telemetry()), None)["json"]
    case("telemetry: reports tag write failure", out.get("ok") is False and out.get("error") == "tag write failed", out)

    fake = FakeSystem()
    ns = load("telemetry.py", fake)
    req = request(None)
    out = ns["doPost"](req, None)["json"]
    case("telemetry: rejects empty body", out.get("ok") is False, out)

    # ---------------- commands.py ----------------
    def get(values=None, **kw):
        fake = FakeSystem()
        base = "[default]CoolingTwin/"
        defaults = {"Commands/Equipment": "Fan", "Commands/FaultType": "Healthy", "Commands/Severity": 0.0,
                    "Commands/RPM": 1450.0, "Commands/LoadFraction": 0.8, "Commands/AmbientC": 24.0,
                    "Commands/ITLoadKW": 40.0, "Commands/Run": False, "Commands/ResetSeq": 0,
                    "Meta/Heartbeat": 12, "Meta/LastUpdate": None, "Meta/LastCommandResult": "OK"}
        defaults.update(values or {})
        for k, v in defaults.items():
            fake.read_values[base + k] = v if isinstance(v, FakeQV) else FakeQV(v)
        ns = load("commands.py", fake)
        return ns["doGet"](request(None, **kw), None)["json"]

    out = get()
    case("commands: returns every command key plus meta echo",
         out.get("ok") is True and all(k in out for k in
         ["equipment", "faultType", "severity", "rpm", "loadFraction", "ambientC", "itLoadKW",
          "run", "resetSeq", "heartbeat", "lastUpdateMs", "lastCommandResult"]), out)
    out = get(key="wrong")
    case("commands: wrong API key rejected", out.get("ok") is False and "equipment" not in out, out)
    out = get(remote="10.0.0.9")
    case("commands: non-localhost client rejected", out.get("ok") is False and "equipment" not in out, out)
    out = get({"Commands/Severity": FakeQV(None, good=False)})
    case("commands: bad-quality command tag reported, no stale values served",
         out.get("ok") is False and out.get("error") == "bad_quality_command_tags", out)

    print("\n%d passed, %d failed" % (len(passed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(run())
