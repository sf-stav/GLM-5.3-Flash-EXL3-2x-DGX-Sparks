#!/usr/bin/env python3
"""Offline check of patch 0123's GlmCallStreamer (no GPU, no server).

Run it in the recipe's image, with this directory mounted:

    docker run --rm --network none \
      -v "$PWD/tools:/tools:ro" --entrypoint python \
      tensorfold-glm53:v0.6.0 /tools/test_stream_calls.py

It feeds a GLM tool call to GlmCallStreamer one character at a time and checks that, with TF_GLM_STREAM_CALLS=1,
the header and arguments stream in many deltas and assemble to exactly what parse_tool_calls returns; with 0, the
call arrives as one whole delta, as the recipe's patches 0053/0055 send it.
"""
from __future__ import annotations

import json
import os
import sys

from tensorfold.cuda.reply_text import GlmCallStreamer, parse_tool_calls

TOOLS = [{
    "type": "function",
    "function": {
        "name": "write_file",
        "parameters": {
            "type": "object",
            "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
        },
    },
}]
CALL = (
    "<tool_call>write_file<arg_key>path</arg_key><arg_value>/tmp/x.py</arg_value>"
    "<arg_key>content</arg_key><arg_value>print(1)\nprint(2)\n</arg_value></tool_call>"
)


def assemble(deltas):
    merged: dict[int, dict[str, str]] = {}
    for delta in deltas:
        for call in delta.get("tool_calls", []):
            slot = merged.setdefault(call["index"], {"name": "", "arguments": ""})
            if "id" in call:
                slot["id"] = call["id"]
            fn = call.get("function") or {}
            slot["name"] = fn.get("name") or slot["name"]
            slot["arguments"] += fn.get("arguments") or ""
    return merged


def run(mode: str) -> tuple[list[dict], dict[int, dict[str, str]]]:
    os.environ["TF_GLM_STREAM_CALLS"] = mode
    streamer = GlmCallStreamer(TOOLS)
    deltas: list[dict] = []
    for end in range(1, len(CALL) + 1):
        deltas += streamer.feed(CALL[:end])
    deltas += streamer.feed(CALL)
    return deltas, assemble(deltas)


def main() -> int:
    expected = parse_tool_calls(CALL, TOOLS)[1]
    assert expected and len(expected) == 1, "the end parser did not read one call"
    want_name = expected[0]["function"]["name"]
    want_args = expected[0]["function"]["arguments"]

    problems: list[str] = []
    for mode, want_many in (("1", True), ("0", False)):
        deltas, merged = run(mode)
        print(f"TF_GLM_STREAM_CALLS={mode}: {len(deltas)} deltas")
        if want_many and len(deltas) < 3:
            problems.append(f"mode {mode}: expected streaming deltas, got {len(deltas)}")
        if not want_many and len(deltas) != 1:
            problems.append(f"mode {mode}: expected one whole delta, got {len(deltas)}")
        slot = merged.get(0, {})
        if slot.get("name") != want_name:
            problems.append(f"mode {mode}: name {slot.get('name')!r} != {want_name!r}")
        if slot.get("arguments") != want_args:
            problems.append(f"mode {mode}: arguments {slot.get('arguments')!r} != {want_args!r}")
        print(f"  assembled: {json.dumps(slot, sort_keys=True)}")

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("\nPASS: streamed and whole deltas both assemble to the end parser's call")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
