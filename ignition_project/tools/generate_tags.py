"""Generate ignition_project/tags/CoolingTwin_tags.json and docs/IGNITION_TAG_MANIFEST.md.

Usage (from the project root):  python ignition_project/tools/generate_tags.py

The JSON follows the standard Ignition tag export structure (a Folder containing
AtomicTags with valueSource 'memory'). It could not be import-tested here because
no Gateway/Designer was available: if Designer rejects it, paste the error, or
export one tag from Designer and compare the property names.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import tag_spec  # noqa: E402


def atomic(entry):
    name, dtype, default, unit, _writer, desc = entry
    tag = {"name": name, "tagType": "AtomicTag", "valueSource": "memory",
           "dataType": dtype, "tooltip": desc}
    if default is not None:
        tag["value"] = default
    if unit:
        tag["engUnit"] = unit
    return tag


def build_tree():
    folders = []
    for group, entries in tag_spec.GROUPS:
        folders.append({"name": group, "tagType": "Folder",
                        "tags": [atomic(e) for e in entries]})
    return {"name": "CoolingTwin", "tagType": "Folder", "tags": folders}


def build_manifest():
    lines = ["# Ignition Tag Manifest — `CoolingTwin`", "",
             "Generated from `ignition_project/tools/tag_spec.py` by "
             "`generate_tags.py`. Do not edit by hand; edit the spec and regenerate.", "",
             "All tags live in the `default` tag provider under `CoolingTwin/`. "
             "Every value is **simulated data produced by the MATLAB engine** "
             "(`src/interactive/run_single_operating_point.m`), never by Ignition.", ""]
    for group, entries in tag_spec.GROUPS:
        lines += ["## %s/" % group, "",
                  "| Tag | Type | Default | Unit | Written by | Meaning |",
                  "|---|---|---|---|---|---|"]
        for name, dtype, default, unit, writer, desc in entries:
            shown = "(none)" if default is None else (repr(default) if isinstance(default, str) else str(default))
            lines.append("| `%s/%s` | %s | %s | %s | %s | %s |" %
                         (group, name, dtype, shown, unit or "-", writer, desc))
        lines.append("")
    lines += ["## Telemetry payload -> tag mapping", "",
              "See `ignition_project/webdev/telemetry.py` (`FIELD_MAP`) for the exact "
              "payload-field-to-tag mapping; `check_consistency.py` verifies it against "
              "this manifest and the MATLAB payload builder.", ""]
    return "\n".join(lines)


def main():
    tags_path = os.path.join(ROOT, "ignition_project", "tags", "CoolingTwin_tags.json")
    doc_path = os.path.join(ROOT, "docs", "IGNITION_TAG_MANIFEST.md")
    os.makedirs(os.path.dirname(tags_path), exist_ok=True)
    with open(tags_path, "w") as f:
        json.dump(build_tree(), f, indent=2)
    with open(doc_path, "w") as f:
        f.write(build_manifest())
    count = sum(len(e) for _g, e in tag_spec.GROUPS)
    print("Wrote %s (%d tags)" % (tags_path, count))
    print("Wrote %s" % doc_path)


if __name__ == "__main__":
    main()
