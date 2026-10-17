#!/usr/bin/env python3
"""Run tests on an explicit simulator and capture the held XCTest drag with simctl."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="UDID of a dedicated, booted iPad simulator")
    parser.add_argument("--label", default="normal", help="Artifact suffix; does not change simulator settings")
    subset = parser.add_mutually_exclusive_group()
    subset.add_argument("--only-atmosphere", action="store_true")
    subset.add_argument("--only-metal", action="store_true", help="Only the Metal path, including A/B and rotation")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    build = root / "build"
    build.mkdir(exist_ok=True)
    result = build / f"atmosphere-{args.label}.xcresult"
    if result.exists():
        parser.error(f"Result already exists: {result}. Use a new --label.")
    command = [
        "xcodebuild", "test", "-project", "TesteMetaWord.xcodeproj",
        "-scheme", "TesteMetaWord", "-destination", f"platform=iOS Simulator,id={args.device}",
        "-derivedDataPath", "build/DerivedData", "-parallel-testing-enabled", "NO",
        "-resultBundlePath", str(result), "CODE_SIGNING_ALLOWED=NO",
    ]
    if args.only_metal:
        command += ["-only-testing:TesteMetaWordUITests/DropMergeTests/testAtmosphereThroughThreeDragsAndUndo"]
    elif args.only_atmosphere:
        command += [f"-only-testing:TesteMetaWordUITests/DropMergeTests/{test}" for test in (
            "testAtmosphereThroughThreeDragsAndUndo", "testGradientAtmosphereThroughThreeDragsAndUndo",
            "testShallowDropDoesNotMerge") ]

    released = threading.Event()
    mode = "metal"
    armed_modes = set()
    captures = []
    capture_errors = []

    def screenshot(path):
        capture = subprocess.run(["xcrun", "simctl", "io", args.device, "screenshot", str(path)],
                                 capture_output=True, text=True)
        if capture.returncode:
            capture_errors.append(capture.stderr)

    def transition_frames(stage, renderer):
        for index in range(8):
            screenshot(build / f"atmosphere-{stage}-{renderer}-{args.label}-{index + 1:02}.png")
            time.sleep(0.2)

    def start_capture(function, *arguments):
        worker = threading.Thread(target=function, args=arguments)
        captures.append(worker)
        worker.start()

    def resistance_capture(renderer):
        time.sleep(2)
        screenshot(build / f"atmosphere-resistance-{renderer}-{args.label}.png")

    def landscape_capture(renderer):
        time.sleep(2)
        screenshot(build / f"atmosphere-landscape-screen-{renderer}-{args.label}.png")

    def held_drag(renderer, release_event):
        # XCTest cannot take a screenshot while its synchronous gesture is held down.
        # Capture from the host; stop if XCTest has already returned from the gesture.
        for index, delay in enumerate((3, 2, 2)):
            if release_event.wait(delay):
                return
            suffix = "" if index == 0 else f"-{index + 1}"
            path = build / f"atmosphere-armed-{renderer}-{args.label}{suffix}.png"
            screenshot(path)

    with (build / f"atmosphere-{args.label}.log").open("w") as log:
        process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in process.stdout:
            log.write(line)
            log.flush()
            if "ATMOSPHERE_MODE=" in line:
                mode = line.strip().split("ATMOSPHERE_MODE=", 1)[1]
            elif "ATMOSPHERE_CAPTURE_ARMED_BEGIN" in line:
                released = threading.Event()
                armed_modes.add(mode)
                start_capture(held_drag, mode, released)
            elif "ATMOSPHERE_CAPTURE_ARMED_END" in line:
                released.set()
                start_capture(transition_frames, "fusion", mode)
            elif "ATMOSPHERE_CAPTURE_UNDO_BEGIN" in line:
                start_capture(transition_frames, "split", mode)
            elif "ATMOSPHERE_CAPTURE_RESISTANCE_BEGIN" in line:
                start_capture(resistance_capture, mode)
            elif "ATMOSPHERE_CAPTURE_LANDSCAPE_BEGIN" in line:
                start_capture(landscape_capture, mode)
            if any(marker in line for marker in ("Test Case", "passed", "failed", "ATMOSPHERE_", "** TEST")):
                print(line.rstrip(), flush=True)
        code = process.wait()
    released.set()
    for worker in captures:
        worker.join()
    if result.exists():
        exported = build / f"atmosphere-attachments-{args.label}"
        export = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                                 "--output-path", str(exported)], capture_output=True, text=True)
        if export.returncode:
            raise SystemExit(export.stderr)
        manifest = json.loads((exported / "manifest.json").read_text())
        for test in manifest:
            for attachment in test.get("attachments", []):
                name = attachment["suggestedHumanReadableName"].split("_", 1)[0]
                if name.startswith("atmosphere-"):
                    shutil.copy2(exported / attachment["exportedFileName"],
                                 build / f"{name}-{args.label}.png")
    if capture_errors:
        raise SystemExit("simctl screenshot failed: " + "\n".join(capture_errors))
    if code == 0:
        for renderer in (("metal",) if args.only_metal else ("metal", "gradients")):
            if renderer not in armed_modes or not (build / f"atmosphere-armed-{renderer}-{args.label}.png").exists():
                raise SystemExit(f"No held-drag capture was produced for {renderer}. Check the XCTest markers.")
    raise SystemExit(code)


if __name__ == "__main__":
    main()
