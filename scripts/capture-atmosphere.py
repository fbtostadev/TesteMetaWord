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
    parser.add_argument("--only-atmosphere", action="store_true")
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
    if args.only_atmosphere:
        command += ["-only-testing:TesteMetaWordUITests/DropMergeTests/testAtmosphereThroughThreeDragsAndUndo"]

    released = threading.Event()
    captures = []
    capture_errors = []

    def screenshot(path):
        capture = subprocess.run(["xcrun", "simctl", "io", args.device, "screenshot", str(path)],
                                 capture_output=True, text=True)
        if capture.returncode:
            capture_errors.append(capture.stderr)

    def transition_frames(stage):
        for index in range(8):
            screenshot(build / f"atmosphere-{stage}-{args.label}-{index + 1:02}.png")
            time.sleep(0.2)

    def start_capture(function, *arguments):
        worker = threading.Thread(target=function, args=arguments)
        captures.append(worker)
        worker.start()

    def held_drag():
        # XCTest cannot take a screenshot while its synchronous gesture is held down.
        # Capture from the host; stop if XCTest has already returned from the gesture.
        for index, delay in enumerate((3, 2, 2)):
            if released.wait(delay):
                return
            suffix = "" if index == 0 else f"-{index + 1}"
            path = build / f"atmosphere-armed-{args.label}{suffix}.png"
            screenshot(path)

    with (build / f"atmosphere-{args.label}.log").open("w") as log:
        process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in process.stdout:
            log.write(line)
            log.flush()
            if "ATMOSPHERE_CAPTURE_ARMED_BEGIN" in line:
                start_capture(held_drag)
            elif "ATMOSPHERE_CAPTURE_ARMED_END" in line:
                released.set()
                start_capture(transition_frames, "fusion")
            elif "ATMOSPHERE_CAPTURE_UNDO_BEGIN" in line:
                start_capture(transition_frames, "split")
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
                for name in ("atmosphere-initial", "atmosphere-first-fusion",
                             "atmosphere-long-phrase", "atmosphere-undo"):
                    if attachment["suggestedHumanReadableName"].startswith(name):
                        shutil.copy2(exported / attachment["exportedFileName"],
                                     build / f"{name}-{args.label}.png")
    if capture_errors:
        raise SystemExit("simctl screenshot failed: " + "\n".join(capture_errors))
    if code == 0 and not (build / f"atmosphere-armed-{args.label}.png").exists():
        raise SystemExit("No held-drag capture was produced. Check the XCTest markers in the log.")
    raise SystemExit(code)


if __name__ == "__main__":
    main()
