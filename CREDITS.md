# Credits

This repository is a thin companion to Mia's AI Lab's
[GLM-5.3-Flash EXL3 on 2x DGX Sparks with TensorFold](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold).
Almost everything that makes the server work was built by others. The upstream [`CREDITS.md`](https://github.com/MiaAI-Lab/GLM-5.3-Flash-EXL3-2x-DGX-Sparks-TensorFold/blob/main/CREDITS.md)
is the authoritative list with the full detail; this page restates it for this distribution and adds the small part
this repository contributes.

This repository's own work is licensed under the Apache License 2.0 ([`LICENSE`](LICENSE)); [`NOTICE`](NOTICE) carries
the third-party notices that go with it and states what this distribution changes.

## This repository (sf-stav)

- **The streamed tool-call patch** (`patches/0123-glm-stream-calls.patch`): makes the incremental tool-call deltas
  that Mia's recipe sent before patch `0053` available again behind `TF_GLM_STREAM_CALLS`, and documents the
  trade-off. The diff is small; the behavior it restores is Mia's.
- **The deployment wrappers** (`start.sh`, `stop.sh`, `logs.sh`) and the one-time installer (`install.sh`).
- **The verification tools** (`tools/verify_tool_stream.py`, `tools/test_stream_calls.py`) and the documentation
  (`README.md`, `docs/streaming-tool-calls.md`).

## The recipe

- **Mia's AI Lab** ([MiaAI-Lab](https://github.com/MiaAI-Lab), [@MiaAI_lab](https://x.com/MiaAI_lab)): the recipe,
  its 96 patches up to `0122`, the prebuilt image, the benchmarks and the model card. Every patch listed below,
  except the parts credited to others, is Mia's, developed with [Claude Code](https://claude.com/claude-code) under
  the Apache License 2.0.

## Model

- **GLM-5.3-Flash** by **[Z.ai](https://huggingface.co/zai-org)**: the model's design, training and evaluations. Its
  license, on the model card, governs any use of the weights. The weights are not part of this repository.
- **Mia's AI Lab**: the default checkpoint,
  [`Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold`](https://huggingface.co/Mia-AiLab/GLM-5.3-Flash-EXL3-4bpw-TensorFold)
  (Apache-2.0), made with [exllamav3](https://github.com/turboderp-org/exllamav3) by **turboderp** (MIT).
- **[brandonmusic](https://huggingface.co/brandonmusic)**: the earlier default checkpoint, still selectable upstream
  with `MODEL_ID`, the EXL3 4-bit quantization
  [`brandonmusic/GLM-5.3-Flash-tr3-4bpw`](https://huggingface.co/brandonmusic/GLM-5.3-Flash-tr3-4bpw), served from
  its mirror `Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw`. It was made with **ShapleyMcg** by Brandon M. Music under the
  **ShapleyMcg License 1.0** (attribution required). Its attribution notice, kept from the upstream notice:

  > This work includes or was produced using ShapleyMcg, created by Brandon M. Music
  > (https://github.com/brandonmmusic-max/shapleymcg). ShapleyMcg is licensed under the ShapleyMcg License v1.0, an
  > attribution-required license that grants no rights to the person known as "0xSero." Use of ShapleyMcg without
  > this attribution is unlicensed.
- **[IncoAI](https://huggingface.co/incoai)**: the DFlash2 drafter,
  [`incoai/GLM-5.3-Flash-DFlash2`](https://huggingface.co/incoai/GLM-5.3-Flash-DFlash2) (**CC BY-NC-ND 4.0**:
  non-commercial use, no derivatives; commercial licensing: contact@inco.ai). Downloaded from its source, never
  redistributed here. `DRAFTER=mtp` serves without it.

## Inference engine

- **[TensorFold](https://github.com/ashhart/TensorFold)** by **Ash Hart** ([ashhart](https://github.com/ashhart)) and
  the TensorFold contributors (Apache 2.0 from v0.6.0; earlier releases MIT, and code written before v0.6.0 keeps
  its MIT notice): the engine that serves the model, including the two-rank CUDA engine for GLM-5.3-Flash, its EXL3
  expert kernels, DFlash2 and MTP drafting with exact verification, and the OpenAI-compatible server. Every file in
  `patches/` is a modification of TensorFold v0.6.0.
- TensorFold builds on, and credits in its
  [third-party notices](https://github.com/ashhart/TensorFold/blob/v0.6.0/THIRD_PARTY_NOTICES.md):
  [ExLlamaV3](https://github.com/turboderp-org/exllamav3) (turboderp, MIT), the GLM-5.3-Flash modeling code in
  Hugging Face [transformers](https://github.com/huggingface/transformers) (Apache 2.0), and
  [z-lab/dflash](https://github.com/z-lab/dflash) (Z Lab, MIT).

## Community patches and reports

The upstream recipe's `96` patches up to `0122` and the reports behind them:

- **`0003-glm-vision`**: GLM's image and video processors and vision tower, checked against Hugging Face
  `transformers` (Apache 2.0).
- **`0006-cuda-roce-allgather`**: the one-shot RoCE all-gather is the "RoCEnante" transport of
  **[b12x](https://github.com/local-inference-lab/b12x)** by local-inference-lab (Apache 2.0), modified for more than
  two Sparks.
- **`0012` / `0014` / `0039-glm-kda-chunked`**: the chunked WY / UT form of gated delta networks and Kimi Delta
  Attention, following [flash-linear-attention](https://github.com/fla-org/flash-linear-attention) (MIT); kernels
  written anew.
- **`0013-glm-decode-rounds`**: wider copy windows, after [TensorFold PR #115](https://github.com/ashhart/TensorFold/pull/115)
  by Ash Hart.
- **`0036-glm-tool-calls`**: the think-block call rule, the reasoning store and the typed argument decoder adapted
  from patch `0620` of [jayleaton/glm53-tensorfold-spark](https://github.com/jayleaton/glm53-tensorfold-spark)
  (Apache 2.0) by **Jay Leaton**; the rest is Mia's implementation.
- **`0037-cuda-tokenize`**: `/tokenize` and `/detokenize` follow [vLLM](https://github.com/vllm-project/vllm)
  (Apache 2.0).
- **`0043-glm-visible-pools`**: the idea follows [TensorFold PR #140](https://github.com/ashhart/TensorFold/pull/140)
  by **mikolaj92**.
- **`0044-cuda-context-errors`**, **`0045-cuda-metrics`**: extend TensorFold v0.6.0 code by Ash Hart (commits
  `68c6e35`, `4447ac3` / #110).
- **`0046-glm-l2-prefetch`**, **`0047-glm-exl3-decode-loads`**: adapted from patches `0460` and `0580` of
  [jayleaton/glm53-tensorfold-spark](https://github.com/jayleaton/glm53-tensorfold-spark) (Apache 2.0) by
  **Jay Leaton**.
- **`0054-glm-image-prompt-reuse`**: by **[abhicnv007](https://github.com/abhicnv007)** (issue #11).
- **`0057-server-thinking-alias`**: from **[Alexbob0](https://github.com/Alexbob0)**'s PR #25.
- **`0058-server-client-gone-poll`**: [TensorFold PR #218](https://github.com/ashhart/TensorFold/pull/218) by
  **[jayleaton](https://github.com/jayleaton)**.
- **`0059-server-refused-bodies`**: TensorFold v0.6.1's fix for #181 by **[SxMShaDoW](https://github.com/SxMShaDoW)**
  (Dorian).
- **`0060-glm-keep-thinking`**: by **[kky42](https://github.com/kky42)** (PR #23).
- **`0071-glm-shared-prefix-copy`**: by **[ezoushen](https://github.com/ezoushen)** (PR #44).
- **`0072-glm-display-kv`**: by **[ezoushen](https://github.com/ezoushen)** (PR #56), after the display-reserve idea
  of **[gabewillen](https://github.com/gabewillen)** in PR #234.
- **`0073-glm-queued-cancellation`**: by **[desy0305](https://github.com/desy0305)** (PR #51), with the
  delivery-failure handling from **[johnwhited](https://github.com/johnwhited)** (PR #48).
- **`0074-glm-compact-before-evict`**: by **[ezoushen](https://github.com/ezoushen)** (PR #62).
- **`0077-glm-kept-cap-shared-by-recency`**: diagnosis by **[meleesciony](https://github.com/meleesciony)**
  (issue #75).
- **`0078-glm-take-over-decide-then-copy`**: by **[m-naoki-m](https://github.com/m-naoki-m)**, also TensorFold
  PR #421.
- **`0079-glm-picture-cache`**, **`0080-vision-quoted-markers`**: by
  **[ThomasWadeZ](https://github.com/ThomasWadeZ)** (#63, #64).
- **`0081` / `0082` / `0083-tfcap-*`**: by **[johnwhited](https://github.com/johnwhited)** (#48), following vLLM's
  admission and abort semantics.
- **`0084-anthropic-messages`**: TensorFold v0.6.3's Anthropic Messages API by
  **[evilpsycho42](https://github.com/evilpsycho42)** and **[ashhart](https://github.com/ashhart)**, with request
  body reading by **Jordi Posthumus** ([JordiPosthumus](https://github.com/JordiPosthumus)); backported by
  **Eduardo Florencio** ([eduffd](https://github.com/eduffd)) in PR #90.
- **`0085`, `0086`, `0087`, `0098`, `0099`, `0100`–`0108`, and part of `0120`**: by
  **[BadAd84](https://github.com/BadAd84)**. `0087`/`0098` relate to
  [kindling spark-os](https://github.com/kindlingai/kindling-spark-os) by **Matt Mastracci** (Kindling AI).
- **`0088-glm-spill-tier`**: by **Robert Wojciechowski** ([wojo](https://github.com/wojo),
  [@rwojo](https://x.com/rwojo)); the design follows **Jay Leaton**'s patch `0250`, the idea follows
  **gabewillen** (PR #232), the conventions follow TensorFold PR #68 by **[gilby](https://github.com/gilby)** and
  [issue #155](https://github.com/ashhart/TensorFold/issues/155) by
  **[raymondkpwong](https://github.com/raymondkpwong)**, and the read checks follow
  **[jakejharris](https://github.com/jakejharris)**'s JSpark3.
- **`0089-glm-kept-state`**: by **[ThomasWadeZ](https://github.com/ThomasWadeZ)** (PR #65).
- **`0090-glm-expert-launch-order`**: by **Lukasz Raczylo**
  ([lukaszraczylo](https://github.com/lukaszraczylo), PR #95).
- **`0094-chunked-request-bodies`**: uses TensorFold's reader by **Jordi Posthumus**; the call sites are Mia's.
- **`0097-glm-kept-entries-share`**: diagnosis by **[jdecker76](https://github.com/jdecker76)** (issue #84).
- **`0109-responses-tool-image`**: by **[StrayDragon](https://github.com/StrayDragon)** (PR #175, issue #162).
- **`0110-vision-mpo-first-frame`**: diagnosis by **[robertforbes68](https://github.com/robertforbes68)**
  (issue #201).
- **`0111-server-sse-keepalive`**: diagnosis and first patch by **[stevehansen](https://github.com/stevehansen)**
  (issue #106); the version in the recipe, extended to the Messages and Responses streams, by
  **[BadAd84](https://github.com/BadAd84)**.
- **`0112`, `0114`, `0115`**: by **[kky42](https://github.com/kky42)** (commits authored as evilpsycho42);
  `0115`'s report adapted from **[BadAd84](https://github.com/BadAd84)**'s `0114` (#137).
- **`0113-http-get-delete-body-discard`**: by **[cawilliamson](https://github.com/cawilliamson)**.
- **`0116`, `0117-glm-reply-marker-ids`**: by **[ahinore](https://github.com/ahinore)** (commits authored as
  iegamo); `0117` follows `TENSORFOLD_REPLY_IDS` of
  [bertholomus/TensorFold](https://github.com/bertholomus/TensorFold) (commit `113a151c`, which credits the rule to
  **DeepInfer**'s output parsing).
- **`0118-glm-broken-health-exit`**: by **[bblicke1](https://github.com/bblicke1)** (PR #146).
- **`0119-glm-chat-continued`**: by **Robert Wojciechowski** ([wojo](https://github.com/wojo)); issue #104 by
  **[danielbanu](https://github.com/danielbanu)**.
- **`0120-glm-fork-point-shared`**: diagnosis and first fix by **[RyanLeeUPC](https://github.com/RyanLeeUPC)**
  (issue #121); the rest by **[BadAd84](https://github.com/BadAd84)**.
- **`0121-glm-kept-reasoning-linear`**: by **[cawilliamson](https://github.com/cawilliamson)**.
- **`0122-cuda-budget-parked-pages`**: by **Robert Wojciechowski** ([wojo](https://github.com/wojo)).
- **`0123-glm-stream-calls`** (this repository): by **sf-stav**; restores the incremental deltas Mia's recipe sent
  before patch `0053`, behind `TF_GLM_STREAM_CALLS`.
- **`docs/hermes-agent.md`, `tools/hermes_benchmark.py`**: by **Steve Darlow**
  ([kerpopule](https://github.com/kerpopule), PR #52).
- Every other patch: by **Mia's AI Lab**, developed with Claude Code, Apache-2.0.

## Runtime stack

- **[NVIDIA PyTorch container](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/pytorch)**
  (`nvcr.io/nvidia/pytorch:26.07-py3`), with NVIDIA's CUDA, cuDNN, cuBLAS, NCCL and related libraries. Governed by
  the NVIDIA Software License Agreement and the Product-Specific Terms for NVIDIA AI Products.
- **[PyTorch](https://pytorch.org/)** (BSD-3-Clause): tensors, CUDA streams and the extension builder.
- **[Triton](https://github.com/triton-lang/triton)** (MIT): the language many TensorFold CUDA kernels are written
  in.
- **[NCCL](https://github.com/NVIDIA/nccl)** (BSD-3-Clause) and **[rdma-core](https://github.com/linux-rdma/rdma-core)**
  (libibverbs): the ranks' exchanges over the ConnectX-7 RoCE link.
- **[PyAV](https://github.com/PyAV-Org/PyAV)** (BSD-3-Clause), **[FFmpeg](https://ffmpeg.org/)** (LGPL) and
  **[Pillow](https://python-pillow.org/)** (MIT-CMU): video and image decoding.
- **[xgrammar](https://github.com/mlc-ai/xgrammar)** (Apache 2.0): structured outputs.
- **[Hugging Face Hub](https://huggingface.co/)** and
  **[safetensors](https://github.com/huggingface/safetensors)** (Apache 2.0): model hosting and format.
- **[Docker](https://www.docker.com/)** and the
  **[NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit)** (Apache 2.0).

## Hardware

- **[NVIDIA DGX Spark](https://www.nvidia.com/en-us/products/workstations/dgx-spark/)** (GB10 Grace Blackwell,
  128 GB unified memory), two linked by their ConnectX-7 ports: every measurement in this repository was made there.

If something here is missing or credited wrongly, please open an issue.
