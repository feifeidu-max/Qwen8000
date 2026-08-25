#!/usr/bin/env python3
"""Long-context prefill/decode benchmark for Qwen3.8-27B-AWQ-INT4 on rtx8000.

Measures, per prompt length (exact token counts):
  - TTFT                -> prefill speed = prompt_tokens / TTFT
  - steady decode speed = completion_tokens / (done_time - first_token_time)

Usage:
  python3 bench200k.py --model-dir /mnt/sdc/work/models/Qwen3.8-27B-AWQ-INT4 \
      --served-name rtx8000-qwen38-27b-awq-int4 --lengths 4096 131072 196608 --reps 2
"""
import argparse
import json
import statistics
import sys
import time

import requests
from transformers import AutoTokenizer


def build_exact_prompt(tok, target_tokens):
    prefix = "Long filler text follows. FILLER START\n"
    suffix = "\nFILLER END\nReply with exactly: PROFILE_OK"
    p_ids = tok.encode(prefix, add_special_tokens=False)
    s_ids = tok.encode(suffix, add_special_tokens=False)
    fill = max(1, target_tokens - len(p_ids) - len(s_ids))
    text = prefix + (" the" * fill) + suffix
    ids = tok.encode(text, add_special_tokens=False)
    if len(ids) > target_tokens:
        ids = ids[:target_tokens]
        text = tok.decode(ids, skip_special_tokens=False)
    n = len(tok.encode(text, add_special_tokens=False))
    return text, n


def run_once(base_url, model, prompt, gen_tokens, timeout_s):
    payload = {
        "model": model,
        "prompt": prompt,
        "max_tokens": gen_tokens,
        "min_tokens": gen_tokens,
        "temperature": 0.0,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    t0 = time.perf_counter()
    first_t = None
    done_t = None
    usage = None
    err = None
    try:
        with requests.post(base_url + "/v1/completions", json=payload,
                           stream=True, timeout=(60, timeout_s)) as resp:
            resp.raise_for_status()
            for raw in resp.iter_lines(decode_unicode=True):
                if not raw or not raw.startswith("data: "):
                    continue
                data = raw[6:]
                if data == "[DONE]":
                    done_t = time.perf_counter()
                    break
                obj = json.loads(data)
                if obj.get("choices") and obj["choices"]:
                    if first_t is None:
                        first_t = time.perf_counter()
                if obj.get("usage"):
                    usage = obj["usage"]
    except Exception as exc:  # noqa: BLE001
        err = f"{type(exc).__name__}: {exc}"
    t_end = time.perf_counter()
    return {
        "error": err,
        "ttft_s": None if first_t is None else first_t - t0,
        "total_s": (done_t or t_end) - t0,
        "prompt_tokens": (usage or {}).get("prompt_tokens"),
        "completion_tokens": (usage or {}).get("completion_tokens"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:8000")
    ap.add_argument("--model-dir", required=True)
    ap.add_argument("--served-name", required=True)
    ap.add_argument("--lengths", type=int, nargs="+",
                    default=[4096, 32768, 65536, 98304, 131072,
                             163840, 180224, 196608])
    ap.add_argument("--gen-tokens", type=int, default=256)
    ap.add_argument("--reps", type=int, default=2)
    ap.add_argument("--warmup", action="store_true")
    args = ap.parse_args()

    tok = AutoTokenizer.from_pretrained(args.model_dir, trust_remote_code=True)
    print(f"[bench] tokenizer loaded from {args.model_dir}", flush=True)

    if args.warmup:
        w = run_once(args.base_url, args.served_name,
                     "Reply with exactly: WARM_OK", 16, 120)
        print(f"[warmup] {w}", flush=True)

    rows = []
    for n in args.lengths:
        prompt, real_n = build_exact_prompt(tok, n)
        ttfts, decodes, prefills = [], [], []
        for rep in range(args.reps):
            r = run_once(args.base_url, args.served_name, prompt,
                         args.gen_tokens, 3600)
            if r["error"]:
                print(f"[len={real_n} rep={rep}] ERROR {r['error']}", flush=True)
                continue
            ct = r["completion_tokens"] or 0
            decode_span = r["total_s"] - (r["ttft_s"] or 0)
            prefill_tps = real_n / r["ttft_s"] if r["ttft_s"] else float("nan")
            decode_tps = (ct - 1) / decode_span if decode_span > 0 and ct > 1 else float("nan")
            ttfts.append(r["ttft_s"])
            prefills.append(prefill_tps)
            decodes.append(decode_tps)
            print(f"[len={real_n} rep={rep}] ttft={r['ttft_s']:.3f}s "
                  f"prefill={prefill_tps:.1f} tok/s total={r['total_s']:.2f}s "
                  f"out={ct}tok decode={decode_tps:.2f} tok/s", flush=True)
            time.sleep(2)
        if ttfts:
            rows.append({
                "prompt_tokens": real_n,
                "ttft_med_s": round(statistics.median(ttfts), 3),
                "prefill_tok_s": round(statistics.median(prefills), 1),
                "decode_tok_s": round(statistics.median(decodes), 2),
                "gens": args.gen_tokens,
                "reps_ok": len(ttfts),
            })
    print("\n=== SUMMARY (median over reps) ===", flush=True)
    hdr = f"{'prompt_tok':>10} {'ttft_s':>9} {'prefill tok/s':>14} {'decode tok/s':>13}"
    print(hdr)
    for row in rows:
        print(f"{row['prompt_tokens']:>10} {row['ttft_med_s']:>9} "
              f"{row['prefill_tok_s']:>14} {row['decode_tok_s']:>13}")
    with open("bench200k-result.json", "w") as fh:
        json.dump(rows, fh, indent=2)
    print("[bench] saved bench200k-result.json", flush=True)


if __name__ == "__main__":
    sys.exit(main())
