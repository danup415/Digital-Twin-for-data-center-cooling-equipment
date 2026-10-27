"""Static consistency checks for the Ignition integration (no Gateway needed).

Usage (from the project root):  python ignition_project/tools/check_consistency.py

What this verifies (all by reading the actual files):
  1. Generated tag JSON parses, has unique tag names, matches tag_spec.py.
  2. telemetry.py FIELD_MAP tags exist in the spec with matching data types.
  3. HEARTBEAT/TELEMETRY field lists in telemetry.py == the lists in
     build_telemetry_payload.m, and together == FIELD_MAP keys.
  4. commands.py COMMAND_MAP tags == Commands/* in the spec, and its JSON keys
     == the CMD-FIELDS list in validate_ignition_command.m.
  5. Fault / equipment / state whitelists in telemetry.py == the MATLAB project
     (config/project_config.m, interactive_code_tables.m,
     maintenance_decision_engine.m).
  6. Both Gateway scripts compile as Python (syntax only; they run as Jython
     2.7 on the Gateway, which can only be tested in Ignition itself).

This is a STATIC check. It does not prove the scripts work on a Gateway.
"""
import ast
import json
import os
import py_compile
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import tag_spec  # noqa: E402

results = []


def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print("%s  %s%s" % ("PASS" if ok else "FAIL", name, ("  -> " + detail) if detail and not ok else ""))


def read(rel):
    with open(os.path.join(ROOT, rel)) as f:
        return f.read()


def literal_assignment(source, name):
    for node in ast.parse(source).body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", None) == name for t in node.targets):
            return ast.literal_eval(node.value)
    raise KeyError(name)


def matlab_cellstr_block(source, begin, end, var):
    block = source.split(begin, 1)[1].split(end, 1)[0]
    m = re.search(var + r"\s*=\s*\{(.*?)\}\s*;", block, re.S)
    return re.findall(r"'([^']+)'", m.group(1))


def flat_tag_names(tree):
    names = []
    for folder in tree["tags"]:
        for t in folder["tags"]:
            names.append("%s/%s" % (folder["name"], t["name"]))
    return names


# ---- 1. generated tag JSON vs spec ----------------------------------------
tags_json = json.loads(read("ignition_project/tags/CoolingTwin_tags.json"))
json_names = flat_tag_names(tags_json)
spec_names = ["%s/%s" % (g, e[0]) for g, entries in tag_spec.GROUPS for e in entries]
check("tag JSON: names unique", len(json_names) == len(set(json_names)))
check("tag JSON matches tag_spec.py", sorted(json_names) == sorted(spec_names))

# ---- 2. telemetry FIELD_MAP vs spec ---------------------------------------
tele_src = read("ignition_project/webdev/telemetry.py")
field_map = literal_assignment(tele_src, "FIELD_MAP")
spec_types = {"%s/%s" % (g, e[0]): e[1] for g, entries in tag_spec.GROUPS for e in entries}
missing = [f for f, (path, _t) in field_map.items() if path not in spec_types]
check("telemetry FIELD_MAP: every tag exists in spec", not missing, str(missing))
bad_types = [f for f, (path, t) in field_map.items()
             if path in spec_types and tag_spec.DATATYPE_TO_PY[spec_types[path]] != t]
check("telemetry FIELD_MAP: data types match spec", not bad_types, str(bad_types))
status_written = {p for p, _t in field_map.values()}
unwritten = [n for n in spec_names if n.split("/")[0] in ("Status", "Meta")
             and n not in status_written and n not in ("Meta/LastUpdate", "Meta/StaleAfterSeconds")]
check("telemetry: every Status/Meta tag has a writer field", not unwritten, str(unwritten))

# ---- 3. payload field lists: Gateway vs MATLAB -----------------------------
hb_gw = literal_assignment(tele_src, "HEARTBEAT_FIELDS")
tm_gw = literal_assignment(tele_src, "TELEMETRY_FIELDS")
payload_m = read("src/ignition/build_telemetry_payload.m")
hb_m = matlab_cellstr_block(payload_m, "% FIELDS-BEGIN", "% FIELDS-END", "HEARTBEAT_FIELDS")
tm_m = matlab_cellstr_block(payload_m, "% FIELDS-BEGIN", "% FIELDS-END", "TELEMETRY_FIELDS")
check("HEARTBEAT_FIELDS: Gateway == MATLAB", hb_gw == hb_m, "%s vs %s" % (hb_gw, hb_m))
check("TELEMETRY_FIELDS: Gateway == MATLAB", tm_gw == tm_m, "%s vs %s" % (tm_gw, tm_m))
check("FIELD_MAP keys == heartbeat + telemetry fields", sorted(field_map) == sorted(hb_gw + tm_gw))
assigned = set(re.findall(r"payload\.(\w+)\s*=", payload_m))
unassigned = [f for f in hb_m + tm_m if f not in assigned]
check("MATLAB payload builder assigns every listed field", not unassigned, str(unassigned))

# ---- 4. commands: tags and JSON keys --------------------------------------
cmd_src = read("ignition_project/webdev/commands.py")
cmd_map = literal_assignment(cmd_src, "COMMAND_MAP")
spec_cmds = [e[0] for e in tag_spec.COMMAND_TAGS]
check("commands COMMAND_MAP tags == spec Commands/*", [n for n, _k in cmd_map] == spec_cmds)
validate_m = read("src/ignition/validate_ignition_command.m")
cmd_fields_m = matlab_cellstr_block(validate_m, "% CMD-FIELDS-BEGIN", "% CMD-FIELDS-END", "required")
check("command JSON keys: Gateway == MATLAB validator", [k for _n, k in cmd_map] == cmd_fields_m,
      "%s vs %s" % ([k for _n, k in cmd_map], cmd_fields_m))
meta_map = literal_assignment(cmd_src, "META_MAP")
check("commands META_MAP tags exist in spec",
      all(("Meta/" + n) in spec_types for n, _k in meta_map))

# ---- 5. whitelists vs the MATLAB project ----------------------------------
project_cfg = read("config/project_config.m")
faults_pump = re.search(r"cfg\.faults\.Pump\s*=\s*\{(.*?)\}", project_cfg, re.S).group(1)
faults_fan = re.search(r"cfg\.faults\.Fan\s*=\s*\{(.*?)\}", project_cfg, re.S).group(1)
union = []
for lab in re.findall(r"'([^']+)'", faults_pump + " " + faults_fan):
    if lab not in union:
        union.append(lab)
check("VALID_FAULTS == union of cfg.faults.Pump/Fan",
      sorted(literal_assignment(tele_src, "VALID_FAULTS")) == sorted(union),
      "%s vs %s" % (literal_assignment(tele_src, "VALID_FAULTS"), union))
codes = read("src/interactive/interactive_code_tables.m")
code_faults = re.findall(r"'([^']+)'", re.search(r"tables\.fault\s*=\s*\{(.*?)\}\s*;", codes, re.S).group(1))
check("VALID_FAULTS == interactive_code_tables fault list",
      sorted(literal_assignment(tele_src, "VALID_FAULTS")) == sorted(code_faults))
equip = re.findall(r"'([^']+)'", re.search(r"cfg\.equipment\s*=\s*\{(.*?)\}", project_cfg, re.S).group(1))
check("VALID_EQUIPMENT == cfg.equipment", literal_assignment(tele_src, "VALID_EQUIPMENT") == equip)
engine = read("src/maintenance/maintenance_decision_engine.m")
levels = re.findall(r"'([^']+)'", re.search(r"levels_order\s*=\s*\{(.*?)\}", engine, re.S).group(1))
check("VALID_STATES == maintenance engine levels", literal_assignment(tele_src, "VALID_STATES") == levels)

# ---- 6. Python syntax of the Gateway scripts ------------------------------
for rel in ("ignition_project/webdev/commands.py", "ignition_project/webdev/telemetry.py"):
    try:
        py_compile.compile(os.path.join(ROOT, rel), cfile=os.path.join(tempfile.gettempdir(), "x.pyc"), doraise=True)
        check("python syntax: " + rel, True)
    except py_compile.PyCompileError as e:
        check("python syntax: " + rel, False, str(e))

for rel in ("ignition_project/webdev/commands.py", "ignition_project/webdev/telemetry.py"):
    check("API key placeholder present (edit before use): " + rel, 'API_KEY = "CHANGE_ME"' in read(rel))

failed = [r for r in results if not r[1]]
print("\n%d checks, %d passed, %d failed" % (len(results), len(results) - len(failed), len(failed)))
sys.exit(1 if failed else 0)
