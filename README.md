# Qwen8000 — RTX8000 双卡 Qwen3.8-27B 私有推理站

基于 [vLLM-2080Ti-Definitive](https://github.com/weicj/vLLM-2080Ti-Definitive)（SM75 定制 fork）
在 **2× Quadro RTX 8000 (48GB, Turing)** 上部署 **Qwen3.8-27B-AWQ-INT4** 的完整
配置、脚本与文档。支持：多模态（图像）、MTP3 投机解码、工具调用、三档思考强度、
前缀缓存、单卡/双卡一键切换、崩溃自动重启。

## 快速开始（已配置好的本机）

```bash
cd ~/RTX8000
./qwen-start single    # 单卡模式（日常推荐, GPU1, ~4分钟）
./qwen-start dual      # 双卡模式（长上下文/大KV, GPU0+1, ~6分钟, 启动竞态自动重试）
./qwen-status          # 查看隧道/进程/显存/API 状态
./qwen-stop            # 关闭并释放显存
```

启动过程实时显示阶段进度，就绪后输出摘要框（API 地址 / 模式 / KV 池 / PID / 日志）。

## 新电脑从零接入

1. `git clone git@github.com:feifeidu-max/Qwen8000.git && cd Qwen8000`
2. 配置 `~/.ssh/config`：
   ```
   Host rtx8000
     HostName <服务器隧道域名>
     Port <端口>
     User duqifei
     IdentityFile ~/.ssh/id_ed25519
   ```
   （向管理员索取当前隧道地址；服务器侧需录入你的公钥）
3. 把 `server/*.sh` 上传到服务器 `/mnt/sdc/work/` 并 chmod +x：
   ```bash
   scp server/*.sh rtx8000:/mnt/sdc/work/
   ssh rtx8000 'chmod +x /mnt/sdc/work/*.sh'
   ```
4. 建 SSH 隧道：`./start-tunnel.sh`
5. pi / pi-web 接入：把 `pi/models.example.json` 内容合并进
   `~/.pi/agent/models.json`（Windows 为 `C:\Users\<你>\.pi\agent\models.json`），
   baseUrl 保持 `http://127.0.0.1:8000/v1`
6. 详细说明见 [模型使用文档.md](模型使用文档.md)

## 文件结构

```
├── qwen-start / qwen-stop / qwen-status   本地一键命令（带进度显示）
├── local/start-tunnel.sh · stop-tunnel.sh SSH 隧道管理
├── server/                                服务器端脚本（放 /mnt/sdc/work/）
│   ├── restart_qwen38_awq.sh              默认启动 = 多模态+APC+MTP3+工具 (TP=1)
│   ├── restart_qwen38_awq_textonly.sh     纯文本备份版
│   ├── restart_qwen38_awq_tp2.sh          双卡 TP=2 版（含 NCCL_P2P_DISABLE=1）
│   ├── supervise_qwen38.sh / supervise_tp2.sh   崩溃守护 + 启动竞态重试
│   └── stop_qwen38.sh                     停止（孤儿进程兜底清理）
├── bench/bench200k.py                     长上下文 prefill/decode 基准
├── pi/models.example.json                 pi agent 模型配置样例（脱敏）
└── 模型使用文档.md                        完整操作手册与故障排查
```

## 实测性能（Qwen3.8-27B-AWQ-INT4）

| 场景 | 单卡 TP=1 | 双卡 TP=2 |
|---|---:|---:|
| 4K prefill | 1068 tok/s | 845 tok/s |
| 128K prefill | 645 tok/s | **907 tok/s** |
| 200K+ prefill（冷） | 525 tok/s | ~794 tok/s |
| 128K decode | 52 tok/s | **80 tok/s** |
| KV 池 | 31.6 万 | 103 万 tokens |

双卡模式存在**启动竞态**（MTP×TP2 已知问题）：务必用守护模式启动，
挂起会自动重试直至成功。

## 注意事项

- API 无鉴权：任何 key 都能调；切勿把端口暴露公网，保持 SSH 隧道访问
- 服务器重启后模型不会自启（手动策略），需重新执行启动命令
- zicp.fun 隧道偶发 DNS/连接抖动，通常 1~5 分钟自愈；停止脚本/守护脚本均已做幂等
