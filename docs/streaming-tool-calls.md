# Streamed tool calls (patch `0123`)

## The symptom

Agent clients saw the reasoning stream normally, then **no output for tens of seconds** while the model was writing a
tool call, and finally the whole call arrived in one event. It looked like a stall or a client-side buffering bug, and
it grew with the size of the call (a large `write_file` / edit could be silent for 20-60 s).

It was not reasoning: `reasoning_effort: "low"` still showed it, and the pause began after the last reasoning delta.
It was not the smoothing buffer: normal text replies never paused.

## The cause

GLM writes tool calls as text markup:

```
<tool_call>write_file<arg_key>path</arg_key><arg_value>/tmp/x.py</arg_value>...</tool_call>
```

Mia's recipe patches 0053 (`glm-whole-tool-calls`) and 0055 (`glm-open-tool-calls`) changed
`GlmCallStreamer.feed` in `tensorfold/cuda/reply_text.py` to **hold each call until `</tool_call>`** and then send the
header and the whole argument JSON in one `tool_calls` delta. The reason is defensible: a call the token limit cuts
is never sent, so a client cannot store or run half of it.

The consequence is a silent stream for the entire time the call is generated. The server does send an empty
`delta: {}` every 2 s while a call is held (`CALL_KEEPALIVE_S`), but most clients ignore empty deltas, so they show
nothing.

Measured on two DGX Sparks, `reasoning_effort: "low"`, a 200-line `write_file` call:

```
reasoning streams:  0.47s .. 1.82s
no output:          1.82s .. 14.40s     (12.58s gap)
tool_calls delta:   14.40s              (the whole call, 4456 characters of JSON)
finish / [DONE]:    14.40s
```

The 2 s empty deltas were arriving during that gap; they are not visible output.

## The fix

`patches/0123-glm-stream-calls.patch` adds `TF_GLM_STREAM_CALLS`:

* `1` (this repo's default): `feed` returns the deltas `_follow` produces as the markup is parsed — a header
  (`index`, `id`, `name`) once the name is known, then the arguments' JSON in pieces (`{"path":"`, `/tmp/x.py`, ...)
  as `<arg_value>` arrives. This is OpenAI's tool-call streaming shape, and it is what the recipe did before patch
  0053.
* `0`: the recipe's whole-call behavior, unchanged.

The end parser is still the authority. When the reply ends, `server.py` folds the streamed call into `result["calls"]`
and the handler does not resend it (`calls_streamed`), so the assembled arguments are identical to what
`parse_tool_calls` returns. The same patch leaves `TF_GLM_STREAM_CALLS` out of the request body: it is a server-side
switch, set for both ranks (the code that parses the call runs on rank 0).

Measured with the same request after the patch:

```
reasoning streams:     0.63s .. 1.96s
argument deltas:       1.96s .. 14.80s     (201 deltas, largest gap 0.11s)
assembled arguments:   6199 characters, valid JSON, keys ['content', 'path']
finish_reason:         tool_calls
```

A 0.5 s gap can still appear if the engine takes a longer round, but the stream is never silent for the length of the
call.

## Trade-off: a call cut by `max_tokens`

With `TF_GLM_STREAM_CALLS=1`, a call that the token limit cuts has already been sent in part. The final chunk says
`finish_reason: "length"`, which is the standard signal **not to execute** an incomplete call. Clients that execute a
call regardless of `finish_reason` should keep `0`.

This is the only behavioral difference from the recipe's whole-call policy. Complete calls are byte-identical in the
assembled arguments; only the timing of the deltas changes.

A second, rarer edge case: patch 0055 repairs a GLM call whose `<arg_key>` markup is missing. With streaming on, the
header and the (possibly wrong) argument fragments may already be out before the repair is known; the non-streamed
`calls` result and the end parser still see the repaired call. Leave `0` if a client must never see the unrepaired
form.

## Enabling it

`install.sh` writes this block into the recipe's `scripts/config.sh`:

```bash
STREAM_CALLS="${STREAM_CALLS:-1}"
export TF_GLM_STREAM_CALLS="${TF_GLM_STREAM_CALLS:-$STREAM_CALLS}"
```

`start.sh` also passes `TF_GLM_STREAM_CALLS` on the remote command, so a direct recipe start and the wrapper agree.
To turn it off:

```bash
STREAM_CALLS=0 ./start.sh --restart
# or add STREAM_CALLS=0 to scripts/local.sh in the recipe
```

The patch changes the image hash (`patches/*.patch` + `IMAGE_EXTRAS`), so `scripts/prepare.sh` will not find the
pinned prebuilt image and builds locally instead. The base image and the TensorFold install layer are cached; in our
test the rebuild took about a minute per Spark plus the image copy to the worker.

## Verifying

Live, against the running server (from the head):

```bash
python3 tools/verify_tool_stream.py
```

It sends a streamed `write_file` request, merges the deltas, and fails if the assembled arguments are not valid JSON,
the finish reason is not `tool_calls`, or any gap between events exceeds 2 s.

Offline, in the image (no GPU, no server):

```bash
docker run --rm --network none \
  -v "$PWD/tools:/tools:ro" --entrypoint python \
  tensorfold-glm53:v0.6.0 /tools/test_stream_calls.py
```

It checks that `1` and `0` both assemble to exactly what the end parser returns, and that `1` really emits many
deltas while `0` emits one.

## Files

* `patches/0123-glm-stream-calls.patch` — `tensorfold/cuda/reply_text.py` only: `stream_calls()`,
  `GlmCallStreamer.feed` and comments. Applies with `patch -p0` after patches `0001`–`0122`.
* `install.sh` — clones the recipe, copies the patch, sets the config switch.
* `tools/verify_tool_stream.py` — live check.
* `tools/test_stream_calls.py` — offline check.
