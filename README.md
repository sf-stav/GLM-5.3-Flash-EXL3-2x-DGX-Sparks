<h1 align="center">GLM-5.3-Flash EXL3 on 2x DGX Sparks: streamed tool calls</h1>

<p align="center">
  <sub>by <a href="https://github.com/sf-stav">sf-stav</a></sub>
  <br><br>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache-2.0"></a>
  <a href="https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold"><img src="https://img.shields.io/badge/built%20on-Mia's%20recipe-8A2BE2.svg" alt="Built on Mia's recipe"></a>
  <a href="docs/streaming-tool-calls.md"><img src="https://img.shields.io/badge/patch-0123%20streamed%20tool%20calls-2ea44f.svg" alt="Patch 0123"></a>
</p>

A small companion to [Mia's AI Lab](https://x.com/MiaAI_lab)'s
[GLM-5.3-Flash EXL3 on 2x DGX Sparks with TensorFold](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold)
recipe. It keeps the recipe's serving stack and adds:

* **Streamed tool calls** (patch `0123`): GLM tool-call arguments go out as they are written, instead of arriving in
  one delta after tens of seconds of silence.
* **Deployment wrappers** (`start.sh`, `stop.sh`, `logs.sh`) for a head + worker pair, with the API on
  `0.0.0.0:9101`.
* **A one-time installer** (`install.sh`) that clones the upstream recipe, installs the patch, configures it, and
  prepares both Sparks.
* **Verification tools** for both the live server and the streamer in isolation.

The model, engine, checkpoint, quantization, patches, image and almost all of the work are Mia's and the upstream
communities'. See [Credits](#credits) and [`CREDITS.md`](CREDITS.md).

## The problem this fixes

Mia's patches `0053` and `0055` hold each GLM tool call until `</tool_call>` and send it whole, so a call the token
limit cuts is never sent. The side effect is a silent stream while the call is generated. Measured here with
`reasoning_effort: "low"` and a 200-line `write_file` call:

| Phase | Before patch `0123` | After patch `0123` |
| --- | ---: | ---: |
| reasoning streams | 0.47 – 1.82 s | 0.63 – 1.96 s |
| tool-call output | **silent until 14.40 s** | 201 argument deltas, 1.96 – 14.80 s |
| largest gap while writing | **12.58 s** | 0.11 s |
| assembled call | whole JSON at 14.40 s | 6199 chars, valid JSON, `finish_reason: tool_calls` |

The wait scales with the size of the call. The 2 s `delta: {}` keep-alives the server sends while holding a call are
ignored by most clients, so they are not visible output. Full diagnosis, design and measurements:
[`docs/streaming-tool-calls.md`](docs/streaming-tool-calls.md).

## Requirements

The same as Mia's recipe:

* **Two NVIDIA DGX Sparks** (GB10, 128 GB unified memory), each with ~110 GiB free when the server starts, linked by
  their ConnectX-7 ports over a direct cable with a static IPv4 address on each end (RoCE v2).
* **Key-based ssh** from the head to the worker (`ssh-copy-id user@worker`).
* **Docker** with the NVIDIA container runtime, the NVIDIA CDI spec generated, `rsync`, and **~205 GB** of disk per
  Spark for the image and checkpoint.
* Optionally the `hf` CLI and a Hugging Face token (the default checkpoint is public; the token only speeds up or
  unlocks gated weights).

See the upstream [Requirements](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold#requirements)
for the link, CDI, memory and disk details; nothing here changes them.

## Quick start

```bash
git clone https://github.com/sf-stav/GLM-5.3-Flash-EXL3-2x-DGX-Sparks.git
cd GLM-5.3-Flash-EXL3-2x-DGX-Sparks

cp config.sh.example config.sh
$EDITOR config.sh          # HEAD, WORKER, FABRIC_PEER, REMOTE_DIR, PORT

./install.sh               # run on the head Spark; clones Mia's recipe, adds the patch, prepares both Sparks
./start.sh                 # ranks load; the recipe runs its smoke test and prints LIVE
./logs.sh                  # both ranks, prefixed
./stop.sh                  # both ranks, frees GPU memory
```

`install.sh` clones the upstream recipe into `REMOTE_DIR`, copies `patches/0123-glm-stream-calls.patch` into its
`patches/`, writes `WORKER` / `FABRIC_PEER` / `HOST` / `PORT` into its `scripts/local.sh`, adds the
`TF_GLM_STREAM_CALLS` switch to its `scripts/config.sh`, and runs `scripts/prepare.sh`.

Because the patch changes the image hash, `prepare.sh` does **not** pull the pinned prebuilt image; it builds locally
from the cached base and TensorFold layers (about a minute in our run) and copies the image to the worker. The
checkpoint is downloaded on the head and copied over the link on the first run.

The OpenAI-compatible API is then at `http://<head>:9101/v1`, model id `GLM-5.3-Flash-EXL3`:

```bash
curl -s http://<head>:9101/v1/models
curl -s http://<head>:9101/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "GLM-5.3-Flash-EXL3",
  "messages": [{"role": "user", "content": "Write a Python fibonacci function."}],
  "max_tokens": 2000
}'
```

## Scripts

### `./start.sh [options] [-- extra recipe args]`

Runs the upstream `start.sh` on `HEAD` over ssh, with `HOST`, `PORT` and `TF_GLM_STREAM_CALLS` in the environment.

| Option | Meaning |
| --- | --- |
| `-r`, `--restart` | Restart both ranks (after a setting change) |
| `-c`, `--context N` | Context window in tokens (default: 1048576) |
| `-s`, `--stream-calls 0\|1` | Override `STREAM_CALLS` for this start |
| `-n`, `--dry-run` | Show the recipe's plan; change nothing |
| `-v`, `--validate` | Query `/v1/models` after startup |
| `-h`, `--help` | Usage |

Extra arguments go to the recipe's `start.sh` after its defaults, e.g.
`./start.sh --restart --max-tokens 16384`.

### `./stop.sh`

Stops both ranks and prints any remaining `glm53` containers on each Spark. The recipe saves each rank's log,
gzipped, under `~/.cache/tensorfold-glm53/logs` on that Spark first.

### `./logs.sh [head|worker|both] [-n N] [--timestamps] [--no-follow]`

Follows `docker logs` on one or both ranks, prefixed `[head]` / `[worker]`.

### `./install.sh [--no-prepare]`

One-time setup on the head. Idempotent: an existing recipe clone is kept, a missing `scripts/local.sh` is created
from the example, existing keys are replaced, and the config block is appended only if absent.

## Configuration

Copy `config.sh.example` to `config.sh` (git-ignored). Every value can also be set in the environment.

| Variable | Default | Meaning |
| --- | --- | --- |
| `HEAD` | `localhost` | ssh target of the Spark that runs rank 0 and the API; `localhost` if you run the wrappers there |
| `WORKER` | — | ssh target of the second Spark; written into the recipe's `scripts/local.sh` |
| `FABRIC_PEER` | — | the worker's ConnectX-7 address when `WORKER` is reached over another network |
| `REMOTE_DIR` | `$HOME/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold` | where the upstream recipe lives on `HEAD` |
| `HOST` | `0.0.0.0` | API listen address |
| `PORT` | `9101` | API port |
| `MODEL` | `GLM-5.3-Flash-EXL3` | served model id (printed by the wrappers) |
| `CONTAINER` | `glm53-flash-tf` | container name on both Sparks |
| `STREAM_CALLS` | `1` | `1`: patch `0123` streaming; `0`: the recipe's whole-call deltas |

## The patch

`patches/0123-glm-stream-calls.patch` modifies only `tensorfold/cuda/reply_text.py`:

* adds `stream_calls()`, which reads `TF_GLM_STREAM_CALLS` (`1` / `0`, default `0` in the code, so the recipe is
  unchanged unless enabled);
* when enabled, `GlmCallStreamer.feed` returns the header and argument fragments that `_follow` produces as the GLM
  markup is parsed, instead of waiting for `</tool_call>` and returning the whole call;
* updates `sent` so the final handler does not resend a call that was already streamed.

The end parser still decides what the call is, so complete calls assemble to exactly what
`parse_tool_calls` returns. The switch is server-side and reaches both ranks.

**Trade-off:** with streaming on, a call cut by `max_tokens` is sent in part and carries
`finish_reason: "length"`; the standard rule is not to execute it. A call that needs patch `0055`'s missing-`<arg_key>`
repair can reach the client in its unrepaired form before the repair is known. Use `STREAM_CALLS=0` if either matters
for your client.

## Verification

Live, against the running server:

```bash
python3 tools/verify_tool_stream.py
```

The tool sends a streamed 120-line `write_file` request, merges the argument deltas, and checks that they form valid
JSON with `path`/`content`, that `finish_reason == "tool_calls"`, and that no gap between events exceeds 2 s. It
exits non-zero on failure.

Offline, in the image (no GPU, no server):

```bash
docker run --rm --network none \
  -v "$PWD/tools:/tools:ro" --entrypoint python \
  tensorfold-glm53:v0.6.0 /tools/test_stream_calls.py
```

This feeds a GLM call to `GlmCallStreamer` one character at a time and checks that both modes assemble to the end
parser's call, and that mode `1` really emits many deltas.

## Compatibility

* Upstream recipe: the `main` of Mia's repository as of 2026-10-25 (TensorFold `v0.6.0`, patches `0001`–`0122`).
  Patch `0123` is written to apply after `0122` with `patch -p0`.
* Model: `Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold` at revision `078455ff…`, with the DFlash2 drafter
  `incoai/GLM-5.3-Flash-DFlash2` (the recipe's defaults).
* The wrappers only need `ssh`, `docker` and `curl` on the head. `install.sh` additionally needs `git`.
* This repository does not vendor the recipe, the image, the weights or the drafter. `install.sh` fetches the recipe;
  the recipe fetches the rest.

## Credits

This repository is a thin layer. The model, the engine, the quantization, the 96 upstream patches, the image and the
performance work are by **Mia's AI Lab** and the people credited in Mia's
[`CREDITS.md`](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/blob/main/CREDITS.md).
In particular:

* **Mia's AI Lab** ([MiaAI-Lab](https://github.com/MiaAI-Lab)): the recipe, the
  [`Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold`](https://huggingface.co/Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold)
  checkpoint, and the patches this repo builds on — including `0053`/`0055`, whose whole-call behavior patch `0123`
  makes optional again.
* **Z.ai** ([zai-org](https://huggingface.co/zai-org)): the GLM-5.3-Flash model and its license.
* **Ash Hart and the TensorFold contributors** ([ashhart/TensorFold](https://github.com/ashhart/TensorFold)): the
  serving engine and its OpenAI-compatible CUDA server.
* **IncoAI**: the DFlash2 drafter (`CC BY-NC-ND 4.0`, non-commercial; not redistributed here).
* **NVIDIA**: the PyTorch container, CUDA stack and the DGX Spark hardware.
* **b12x / local-inference-lab**, **Jay Leaton** (`glm53-tensorfold-spark`), **Z Lab** (`dflash`), **turboderp**
  (ExLlamaV3), Hugging Face `transformers`, and every community contributor named in Mia's credits —
  ezoushen, desy0305, johnwhited, meleesciony, jdecker76, ThomasWadeZ, m-naoki-m, gabewillen, mikolaj92,
  Eduardo Florencio (eduffd), evilpsycho42, Jordi Posthumus, BadAd84, Robert Wojciechowski (wojo/@rwojo),
  Lukasz Raczylo, cawilliamson, SxMShaDoW, brandonmusic, stevehansen, kky42, Alexbob0, abhicnv007, StrayDragon,
  ahinore, bblicke1, RyanLeeUPC, robertforbes68, kerpopule, danielbanu, and the TensorFold maintainers.

The full list, with what each person contributed, is in [`CREDITS.md`](CREDITS.md) and upstream's
[`CREDITS.md`](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/blob/main/CREDITS.md) and
[`NOTICE`](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/blob/main/NOTICE).

## License

This repository's own work (the patch, scripts, tools and docs) is Apache-2.0; see [`LICENSE`](LICENSE).
[`NOTICE`](NOTICE) carries the upstream notices and states what this distribution changes. Patched TensorFold code
remains under TensorFold's licenses (Apache-2.0, and MIT for code written before v0.6.0).

This is an independent companion project. It is not affiliated with or endorsed by Mia's AI Lab, TensorFold, NVIDIA,
Z.ai or IncoAI. The weights and the drafter keep their own licenses; nothing here redistributes them.
