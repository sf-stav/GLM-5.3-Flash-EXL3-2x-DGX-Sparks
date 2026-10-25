#!/usr/bin/env python3
"""Verify that GLM tool-call arguments stream (patch 0123).

Sends a streamed chat completion that must write a file with the write_file tool, merges the streamed
tool_calls deltas, and checks:

  * the arguments assemble into valid JSON with the expected keys;
  * finish_reason is "tool_calls";
  * no gap between successive stream events exceeds --max-gap seconds (the whole-call behavior is silent for the
    entire time the call is written, which is tens of seconds for a large file).

Run it on the head against the live server:

    python3 tools/verify_tool_stream.py
    python3 tools/verify_tool_stream.py --base-url http://192.168.178.170:9101/v1 --lines 200
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request

TOOLS = [{
    "type": "function",
    "function": {
        "name": "write_file",
        "description": "Write a text file to disk",
        "parameters": {
            "type": "object",
            "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
            "required": ["path", "content"],
        },
    },
}]


def main() -> int:
    ap = argparse.ArgumentParser(description="Check that GLM tool-call arguments stream continuously.")
    ap.add_argument("--base-url", default="http://127.0.0.1:9101/v1")
    ap.add_argument("--model", default="GLM-5.3-Flash-EXL3")
    ap.add_argument("--lines", type=int, default=120, help="lines of Python to ask the tool to write")
    ap.add_argument("--max-tokens", type=int, default=4000)
    ap.add_argument("--max-gap", type=float, default=2.0, help="largest allowed pause between events, seconds")
    ap.add_argument("--timeout", type=float, default=900)
    args = ap.parse_args()

    prompt = (f"Use write_file to write /tmp/tool_stream_check.py containing a {args.lines}-line Python program "
              "with several small functions. Write the whole file with the tool.")
    body = {
        "model": args.model,
        "stream": True,
        "max_tokens": args.max_tokens,
        "reasoning_effort": "low",
        "tools": TOOLS,
        "messages": [
            {"role": "system", "content": "You are a coding agent. Use the tools when asked."},
            {"role": "user", "content": prompt},
        ],
    }
    req = urllib.request.Request(
        args.base_url.rstrip("/") + "/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )

    t0 = time.time()
    events: list[tuple[float, str]] = []
    slots: dict[int, dict[str, str]] = {}
    finish = None
    done = None
    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            for raw in resp:
                now = time.time()
                line = raw.decode("utf-8", "replace").rstrip("\n")
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    done = now
                    break
                event = json.loads(data)
                choice = (event.get("choices") or [{}])[0]
                delta = choice.get("delta") or {}
                kind = ("reasoning" if delta.get("reasoning_content") else
                        "content" if delta.get("content") else
                        "tool_calls" if delta.get("tool_calls") else None)
                if kind:
                    events.append((now, kind))
                for call in delta.get("tool_calls") or []:
                    slot = slots.setdefault(call["index"], {"name": "", "arguments": ""})
                    if "id" in call:
                        slot["id"] = call["id"]
                    fn = call.get("function") or {}
                    slot["name"] = fn.get("name") or slot["name"]
                    slot["arguments"] += fn.get("arguments") or ""
                if choice.get("finish_reason"):
                    finish = choice["finish_reason"]
    except Exception as exc:  # noqa: BLE001 - report the failure, do not traceback at the user
        print(f"FAIL: request failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1

    if done is None:
        print("FAIL: the stream ended without [DONE]", file=sys.stderr)
        return 1

    gaps = [(b[0] - a[0], a[1], b[1]) for a, b in zip(events, events[1:])]
    largest = max(gaps, default=(0.0, "", ""))
    tool_times = [t for t, kind in events if kind == "tool_calls"]
    problems: list[str] = []

    if not slots:
        problems.append("no tool_calls deltas at all")
    else:
        for index, slot in slots.items():
            try:
                parsed = json.loads(slot["arguments"])
            except Exception as exc:  # noqa: BLE001
                problems.append(f"call {index} arguments are not valid JSON: {exc}")
                continue
            if slot["name"] != "write_file":
                problems.append(f"call {index} names {slot['name']!r}, not write_file")
            if not isinstance(parsed, dict) or "path" not in parsed or "content" not in parsed:
                problems.append(f"call {index} arguments lack path/content: keys={list(parsed or {})}")
    if finish != "tool_calls":
        problems.append(f"finish_reason is {finish!r}, not 'tool_calls' (a cut call is 'length')")
    if largest[0] > args.max_gap:
        problems.append(f"largest gap {largest[0]:.2f}s ({largest[1]}->{largest[2]}) exceeds {args.max_gap:g}s")

    print(f"events: {len(events)}  (reasoning {sum(k == 'reasoning' for _, k in events)}, "
          f"content {sum(k == 'content' for _, k in events)}, tool_calls {len(tool_times)})")
    if tool_times:
        print(f"tool-call deltas: first {tool_times[0] - t0:.2f}s, last {tool_times[-1] - t0:.2f}s, "
              f"span {tool_times[-1] - tool_times[0]:.2f}s")
    print(f"largest gap between events: {largest[0]:.2f}s ({largest[1]}->{largest[2]})")
    print(f"finish_reason: {finish!r}   total: {done - t0:.2f}s")
    for index, slot in slots.items():
        print(f"call {index} {slot['name']}: {len(slot['arguments'])} argument characters")

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("\nPASS: tool-call arguments streamed continuously and assembled into a valid call")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
