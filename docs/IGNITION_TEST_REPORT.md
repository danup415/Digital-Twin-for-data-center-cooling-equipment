# Ignition Integration — Test Report (vertical slice)

Three categories, kept strictly apart. **Nothing in category B or C has been
executed by the author of this code** — the build environment had neither MATLAB nor
an Ignition Gateway.

## A. Executed (Python, in the build environment)

| Suite | Command | Result |
|---|---|---|
| Static consistency (20 checks): tag spec ↔ tag JSON ↔ Web Dev scripts ↔ MATLAB payload/command field lists ↔ project fault/equipment/state labels; Python syntax of both Gateway scripts | `python ignition_project/tools/check_consistency.py` | 20 / 20 passed |
| Gateway-script logic (33 cases) with a stubbed Ignition `system` object: valid telemetry/heartbeat/disconnect accepted; wrong or missing key, non-loopback client, unknown fault/equipment/state labels, out-of-range or NaN values, wrong types, missing fields, bad schema, overlong text, empty body, tag-write failure all rejected with nothing written; commands endpoint returns every key and refuses bad quality | `python ignition_project/tools/test_webdev_logic.py` | 33 / 33 passed |

Limits of category A: the scripts run here under CPython with a fake `system`; the
Gateway runs Jython 2.7 with the real request object and tag provider. These tests
verify the decision logic, not Gateway behavior.

## B. Written, to be executed by you in MATLAB R2024a

| Suite | Needs | Covers |
|---|---|---|
| `tests/test_ignition_adapter.m` | MATLAB only | valid command accepted; invalid fault name rejected (incl. fault of the other equipment, wrong case); severity outside 0–1 and wrong types rejected; Healthy with severity > 0 rejected; invalid RPM/load/ambient/IT-load rejected; payload fields, finiteness and JSON-encodability; non-finite result refused; unreachable Gateway reported (not thrown); missing key refused; stale-timestamp detection; Healthy, Fan bearing-degradation and Pump cavitation scenarios; injected vs predicted labels separate; payload HI / cooling effectiveness / thermal / RUL equal **direct calls** to the existing functions on the same history; progressive severity changes real outputs; history reset on scenario change |
| `tests/test_ignition_live.m` | Gateway + tags + both Web Dev resources + key | endpoint reachable and command values valid; heartbeat round trip and recent `LastUpdate`; a real engine step accepted; unknown fault label and severity > 1 **rejected by the Gateway**; disconnect accepted |

Status: **not yet run.** Record results here after running them.

## C. Manual checks (Designer / Perspective / Gateway)

| Check | How |
|---|---|
| Tag JSON imports | Setup guide §3A |
| Web Dev resources save and respond | Setup guide §3B, then `test_ignition_live` |
| Perspective bindings point to valid tags | Open each bound component in Designer: the binding editor shows a bad tag path immediately (Static check A already confirms every telemetry field maps to a tag that exists in the manifest) |
| Controls write the Commands tags | Change a control, confirm the tag value in the Tag Browser |
| End to end: Perspective → adapter → real model → tags → Perspective | Setup guide §4 |
| BACKEND DISCONNECTED appears after stopping the adapter | Stop the adapter, wait `StaleAfterSeconds` |
| Stale telemetry indicator | Same as above (expression in §3D) |

## Requirement 15 — unsupported modules or components

Used and verified from Ignition's 8.3 documentation as Maker-compatible: **Perspective**
and **Web Dev**. Not used: MQTT modules, OPC UA, Vision, the Gateway's database
connections, native Ignition alarm pipelines. The Alarms-and-History view planned for a
later step will therefore show **status indicators and a history table fed by tags**,
and will not be labeled as native Ignition alarms unless alarm pipelines are configured.
