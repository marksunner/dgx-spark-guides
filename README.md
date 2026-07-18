# GLM 5.2 on 4× DGX Spark

> **Update — 18 July 2026.** The multi-node deadlock investigated across this repo has since been **root-caused**: a FlashInfer sparse-MLA (`sparse_mla_sm120`) **mbarrier livelock on GB10** — one kernel block spin-waiting forever on a barrier phase that never arrives, everything else piling up behind it — with a **validated one-flag workaround** (route the main model's attention to the Triton sparse-MLA kernels via `--attention-backend FLASHMLA_SPARSE`). The full evidence — cuda-gdb captures, RAS dumps, 500 consecutive clean ceiling sessions — lives in **[glm52-dgx-spark-deadlock-evidence](https://github.com/marksunner/glm52-dgx-spark-deadlock-evidence)**, and the write-up is the **[RFC #48720 results update](https://github.com/vllm-project/vllm/issues/48720#issuecomment-5010866477)**. The documents below are preserved as written — they record the investigation as it actually unfolded — with the new evidence as the final word.

*The complete journey from unboxing to first inference — 671B parameters, all 256 experts, 200K context, MTP speculative decoding, ~26 tok/s. Built on [tonyd2wild's QuantTrio recipe](https://github.com/tonyd2wild/GLM-5.2-QuantTrio-200K-4x-DGX-Spark). Three days, four bugs, one UPS incident, and a haiku.*

→ For all DGX Spark work (other models, benchmarks, comparisons), see **[dgx-spark](https://github.com/marksunner/dgx-spark)**.

---

## What's Here

### ✨ [GLM 5.2 Quad-Spark Deployment Guide](glm-5.2-quad-spark-deployment.md)
The main event. From shrink-wrap to serving: OOBE setup, cluster networking, custom vLLM build, the four bugs we found and fixed, and the power-loss recovery that taught us about GID table instability. Written so that someone with four DGX Sparks and enthusiasm — but no prior cluster experience — can follow it end to end.

### 🔧 [What Is Fabric?](what-is-fabric.md)
Companion guide: building a lossless RoCE fabric with a MikroTik CRS812 QSFP switch. Starts from first principles (what is RDMA? why does it hate dropped packets?), covers the RouterOS config step by step, and ends with verification and a pitfall table where every row is a scar. Standalone — usable for any multi-Spark cluster, not just GLM.

### 📡 [DGX Spark Multi-Node Deadlock Analysis](dgx-spark-multi-node-deadlock-analysis.md)
Community root-cause analysis of the multi-node NCCL deadlock affecting all DGX Spark (GB10) clusters running tensor-parallel inference. Four-layer diagnosis: engine-level TP race, missing GPUDirect RDMA on stock Spark, GB10 UMA driver leak, and NCCL’s lack of collective timeout. Five specific asks of NVIDIA.

### 🔒 [GLM 5.2 Stability Fixes](glm-5.2-stability-fixes.md)
Field report: diagnosing and fixing a reproducible NCCL deadlock with MTP speculative decoding. If your cluster serves 3–5 requests then silently hangs at 96% GPU — this is the guide. Covers root cause (cudagraph rank desync + async-scheduling MTP races + NCCL NVLS), a copy-paste fix, and a step-by-step recovery ladder from 15 → 23 tok/s stable.

### 🛡️ [preflight.sh](preflight.sh)
Pre-launch GID index validator. The RoCE GID table shifts after a reboot; this script catches it before NCCL fails silently. Run `./preflight.sh --fix && ./launch-castle.sh` after any power cycle.

### 🧪 [Deadlock Evidence Repo](https://github.com/marksunner/glm52-dgx-spark-deadlock-evidence)
The verdict to the analysis above. cuda-gdb captures of the live kernel livelock, per-rank RAS op-count dumps, stall dossiers, and the soak statistics — 500 consecutive clean ceiling sessions on the Triton attention route — behind the [RFC #48720 results update](https://github.com/vllm-project/vllm/issues/48720#issuecomment-5010866477). If the deadlock analysis is the investigation, this is the closing evidence.

### 🪶 [baton-pass](https://github.com/marksunner/baton-pass)
The handoff discipline that kept a multi-day, multi-session debugging campaign coherent: self-briefs, a campaign ledger, one variable per relaunch, receipts for everything. The method behind the documents above.

### 🛰️ [spark-stability-sentry](https://github.com/marksunner/spark-stability-sentry)
The watchdog and failover stack from the campaign, packaged as a standalone field kit: wedge detection (the 96%-util spin signature), evidence capture *before* any exit path runs, restart budgets, and incident bundling. Detect and recover, not prevent — the two underlying platform bugs remain open.

---

## Credits

This work stands on **[tonyd2wild's QuantTrio recipe](https://github.com/tonyd2wild/GLM-5.2-QuantTrio-200K-4x-DGX-Spark)** — the build commands, serve configuration, and performance targets are theirs. Tony's recipe credits the wider community (CosmicRaisins, Zatz, back199640, ciprianveg, eugr, QuantTrio) — full acknowledgements in the guide.

## License

Apache 2.0 — see [LICENSE](LICENSE).
