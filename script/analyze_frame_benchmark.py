#!/usr/bin/env python3
"""Measure native input response and captured WindowServer cadence separately."""

import json
import math
import statistics
import sys
from pathlib import Path


def percentile(values, fraction):
    values = sorted(values)
    return values[math.ceil((len(values) - 1) * fraction)] if values else 0


def analyze(path):
    raw = json.loads(path.read_text())
    frames = sorted(raw["capturedFrames"], key=lambda frame: frame["time"])
    # Idle frames have no new surface. Complete frames can also contain changes
    # outside the sidebar, so deduplicate the region's pixels across all frames.
    changes = []
    previous = None
    for frame in frames:
        value = frame.get("hash")
        if frame["status"] == 0 and value is not None:
            if previous is not None and value != previous:
                changes.append(frame["time"])
            previous = value
    results = []
    refresh = raw["maximumFPS"]
    period = 1 / refresh
    failures = []
    for trial in raw["trials"]:
        start = trial["start"] + 0.5  # Ignore onset/edge crossing and reset paint.
        end = trial["end"]
        updates = [time for time in changes if start <= time <= end]
        gaps = [b - a for a, b in zip(updates, updates[1:])]
        display = [s for s in raw["displaySamples"] if start <= s["time"] <= end]
        callback_gaps = [b["time"] - a["time"] for a, b in zip(display, display[1:])]
        keys = trial["keys"]
        headers = [f["headerHash"] for f in frames
                   if start <= f["time"] <= end and f.get("headerHash") is not None]
        interval = trial.get("inputInterval", 1 / 30)
        lateness = [max(0, k["time"] - k["intended"]) * 1000 for k in trial["posted"]]
        selection = [f["selectionTop"] for f in frames
                     if start <= f["time"] <= end and f.get("selectionTop") is not None]
        direction = 1 if trial["name"].startswith("down-") else -1
        reversals = [direction * (b["y"] - a["y"])
                     for a, b in zip(display, display[1:])
                     if direction * (b["y"] - a["y"]) < -0.5]
        result = {
            "name": trial["name"], "seconds": end - start,
            "presented_updates": len(updates), "fps": len(updates) / (end - start),
            "gap_p50_ms": percentile(gaps, 0.5) * 1000,
            "gap_p95_ms": percentile(gaps, 0.95) * 1000,
            "gap_max_ms": max(gaps, default=0) * 1000,
            "missed_refresh_slots": sum(max(0, round(gap / period) - 1) for gap in gaps),
            "display_callback_hz": len(display) / (end - start),
            "callback_gap_max_ms": max(callback_gaps, default=0) * 1000,
            "keys": len(keys),
            "input_hz": (len(keys) - 1) / (keys[-1]["time"] - keys[0]["time"]) if len(keys) > 1 else 0,
            "input_lateness_p95_ms": percentile(lateness, 0.95),
            "input_lateness_max_ms": max(lateness, default=0),
            "dispatch_delay_p95_ms": percentile([(k["time"] - k["queued"]) * 1000 for k in keys], 0.95),
            "dispatch_delay_max_ms": max(((k["time"] - k["queued"]) * 1000 for k in keys), default=0),
            "key_work_p50_ms": percentile([k["duration"] * 1000 for k in keys], 0.5),
            "key_work_p95_ms": percentile([k["duration"] * 1000 for k in keys], 0.95),
            "key_work_max_ms": max((k["duration"] * 1000 for k in keys), default=0),
            "motion_samples": sum(abs(b["y"] - a["y"]) > 0.1
                                  for a, b in zip(display, display[1:])),
            "display_samples": len(display),
            "pinned_header_changes": sum(a != b for a, b in zip(headers, headers[1:])) if headers else None,
            "selection_bounce_px": max(selection) - min(selection) if selection else None,
            "viewport_reversals": len(reversals),
            "selection_steps_valid": all(b["row"] - a["row"] == direction
                                         for a, b in zip(keys, keys[1:])),
        }
        results.append(result)
        if trial["name"].startswith(("down-", "up-")):
            if not display or any(not (s["active"] and s["key"] and s["visible"]) for s in display):
                failures.append(f'{trial["name"]}: window lost foreground focus or visibility')
            if len(trial["posted"]) != round(3 / interval) or result["input_lateness_max_ms"] > interval * 1000:
                failures.append(f'{trial["name"]}: input scheduler missed a key deadline')

    by_name = {r["name"]: r for r in results}
    if by_name["idle"]["presented_updates"] > 1:
        failures.append("stationary control contains sidebar pixel changes")
    if by_name["calibration"]["fps"] < refresh * 0.90:
        failures.append("capture calibration cannot sustain 90% of the display refresh rate")
    if by_name["stall-control"]["gap_max_ms"] < 80:
        failures.append("negative control did not detect the deliberate 100ms stall")
    processing = [f["processingMilliseconds"] for f in frames]
    if percentile(processing, 0.95) > 1:
        failures.append("capture hash processing exceeds 1ms at p95")
    capture_lag = [(f["received"] - f["time"]) * 1000 for f in frames if f["time"] > 0]
    if not capture_lag or min(capture_lag) < -1 or percentile(capture_lag, 0.95) > 50:
        failures.append("capture clock/delivery lag is invalid")
    measured = [r for r in results if r["name"].startswith(("down-", "up-"))]
    smooth = all(r["fps"] >= refresh * 0.95 and r["gap_p95_ms"] <= period * 1500
                 and r["gap_max_ms"] <= period * 2500
                 and r["pinned_header_changes"] == 0
                 and r["selection_bounce_px"] is not None and r["selection_bounce_px"] <= 2
                 and r["motion_samples"] >= 0.85 * r["display_samples"]
                 and r["viewport_reversals"] == 0 and r["selection_steps_valid"] for r in measured)
    # Native row steps produce one changed surface per key, not per refresh.
    # Keep the continuous-motion target visible; never infer 60 FPS from the
    # display-link callback rate. Response checks use the actual input interval.
    response_failures = []
    for r in measured:
        for metric, budget in [("key_work_p95_ms", period * 1000),
                               ("dispatch_delay_p95_ms", period * 1000),
                               ("gap_max_ms", 1000 / r["input_hz"] + period * 2500)]:
            if r[metric] > budget:
                response_failures.append(f'{r["name"]}: {metric}={r[metric]:.3f} exceeds {budget:.3f}ms')
        if r["fps"] < min(r["input_hz"], refresh) * 0.95:
            response_failures.append(f'{r["name"]}: captured updates below 95% of input rate')
        if (r["pinned_header_changes"] != 0 or r["selection_bounce_px"] is None
                or r["selection_bounce_px"] > 2 or r["viewport_reversals"] != 0
                or not r["selection_steps_valid"]):
            response_failures.append(f'{r["name"]}: navigation stability failed')
    responsive = not response_failures
    summary = {
        "screen": raw["screen"], "refresh_hz": refresh,
        "valid": not failures, "validity_failures": failures,
        "smoothness_gate_passed": smooth,
        "native_response_gate_passed": responsive,
        "native_response_failures": response_failures,
        "fps_median": statistics.median(r["fps"] for r in measured),
        "fps_min": min(r["fps"] for r in measured),
        "fps_max": max(r["fps"] for r in measured),
        "capture_work_p95_ms": percentile(processing, 0.95),
        "capture_delivery_p95_ms": percentile(capture_lag, 0.95),
        "trials": results,
    }
    path.with_name("summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    lines = ["# Held-arrow presentation benchmark", "",
             f'Display: {raw["screen"]}, {refresh} Hz. Release; 300 offline apps; '
             f'{raw["windowWidth"]:g}×{raw["windowHeight"]:g} window; system repeat, 30 and 60 keys/s.',
             "", "| Trial | Captured motion FPS | p95 gap (ms) | Worst gap (ms) | Missed refreshes | Input Hz | Key work p95 (ms) | Scheduled input delay p95 (ms) | Header changes | Selection bounce (px) | Reversals |",
             "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for r in results:
        lines.append(f'| {r["name"]} | {r["fps"]:.2f} | {r["gap_p95_ms"]:.2f} | '
                     f'{r["gap_max_ms"]:.2f} | {r["missed_refresh_slots"]} | {r["input_hz"]:.2f} | '
                     f'{r["key_work_p95_ms"]:.2f} | {r["dispatch_delay_p95_ms"]:.2f} | '
                     f'{r["pinned_header_changes"] if r["pinned_header_changes"] is not None else "unmeasured"} | '
                     f'{r["selection_bounce_px"]} | {r["viewport_reversals"]} |')
    lines += ["", f'Measured FPS median: {summary["fps_median"]:.2f}; range '
              f'{summary["fps_min"]:.2f}–{summary["fps_max"]:.2f}.', "",
              f'Validity: {"PASS" if not failures else "FAIL"}. '
              f'Continuous-motion target: {"PASS" if smooth else "FAIL"}. ',
              f'Native response gate: {"PASS" if responsive else "FAIL"}.', "",
              "Gate: every measured trial ≥95% of refresh, p95 gap ≤1.5 refresh periods, worst gap ≤2.5 periods; motion in ≥85% of diagnostic display samples; pinned-header pixels unchanged; capsule drift ≤2px; no opposite viewport steps >0.5pt.",
              "Native response gate: key work and dispatch delay p95 within one refresh period; "
              "captured changes ≥95% of input rate (capped at refresh); worst paint gap within "
              "one input interval plus 2.5 refresh periods; unchanged headers, ≤2px capsule drift, no reversal.", "",
              "Scheduled input delay includes the benchmark's main-queue posting bridge; "
              "it is not hardware keyboard-to-photon latency.", "",
              "FPS counts distinct sidebar pixels at WindowServer display times during steady motion. "
              "It does not prove physical scanout or performance on a 120Hz display.", "",
              f'Capture processing p95: {summary["capture_work_p95_ms"]:.3f}ms; '
              f'delivery p95: {summary["capture_delivery_p95_ms"]:.3f}ms.']
    lines += [f"- {failure}" for failure in failures + response_failures]
    report = "\n".join(lines) + "\n"
    path.with_name("report.md").write_text(report)
    print(report)
    print(f"Raw samples and report: {path.parent}")
    return 0 if not failures and responsive else 1


if __name__ == "__main__":
    sys.exit(analyze(Path(sys.argv[1])))
