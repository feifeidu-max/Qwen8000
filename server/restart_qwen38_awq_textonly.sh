#!/bin/bash
# Qwen3.8-27B-AWQ-INT4 vLLM restart (RTX8000 GPU1 TP=1, awq_marlin, MTP3, FlashQLA legacy)
pkill -9 -f "vllm.entrypoints.openai.api_server" 2>/dev/null
pkill -9 -f "VLLM::EngineCore" 2>/dev/null
pkill -9 -f "multiprocessing.resource_tracker" 2>/dev/null
sleep 3
LEFT=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader -i 1)
[ -n "$LEFT" ] && { echo "killing orphan GPU procs: $LEFT"; for pid in $LEFT; do kill -9 $pid 2>/dev/null; done; sleep 2; }
cd /mnt/sdc/work/vllm-2080ti
export CUDA_HOME=/usr/local/cuda-12.4
export PATH=/usr/local/cuda-12.4/bin:$PATH
export CUDA_VISIBLE_DEVICES=1
export VLLM_SM75_SPEC_SYNC_MODE=safe
export VLLM_ALLOW_MAMBA_SPEC_FULL_CUDAGRAPH=0
LOG=run-logs/vllm-rtx8000-qwen38-27b-awq-int4-$(date +%Y%m%d-%H%M%S).log
nohup ./.venv/bin/python -m vllm.entrypoints.openai.api_server \
  --host 127.0.0.1 --port 8000 \
  --model /mnt/sdc/work/models/Qwen3.8-27B-AWQ-INT4 \
  --served-model-name rtx8000-qwen38-27b-awq-int4 \
  --dtype half --tensor-parallel-size 1 \
  --generation-config vllm \
  --gpu-memory-utilization 0.92 \
  --max-model-len 208896 \
  --enable-chunked-prefill --max-num-seqs 1 --max-num-batched-tokens 4096 \
  --speculative-config "{\"method\":\"mtp\",\"num_speculative_tokens\":3}" \
  --language-model-only --skip-mm-profiling \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder \
  --disable-log-stats \
  --reasoning-parser qwen3 \
  --additional-config "{\"gdn_prefill_backend\":\"flashqla_legacy\"}" \
  --compilation-config "{\"cudagraph_mode\":\"PIECEWISE\",\"cudagraph_capture_sizes\":[1,2,4],\"max_cudagraph_capture_size\":4}" \
  > "$LOG" 2>&1 &
echo "started pid=$! log=$LOG"
for i in $(seq 1 40); do
  sleep 15
  if ss -tln 2>/dev/null | grep -q ":8000 "; then echo "READY in $((i*15))s"; break; fi
done
ss -tln | grep ":8000 " || echo "NOT_READY_YET"
