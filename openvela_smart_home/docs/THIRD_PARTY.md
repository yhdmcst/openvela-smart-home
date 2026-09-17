# 第三方依赖声明 (Third-Party Dependencies)

本项目依赖于以下第三方开源组件，特此声明其许可证信息。

---

## 核心框架依赖

| 依赖名称 | 版本 | 许可证 | 用途 | 上游仓库 |
|----------|------|--------|------|----------|
| openvela (NuttX-based) | main | Apache-2.0 | 嵌入式 RTOS + AI Agent 核心框架 | https://github.com/YashTech/vela_agent |
| NuttX | - | Apache-2.0 | 底层 RTOS（openvela 底层） | https://github.com/apache/nuttx |

## 构建工具依赖

| 依赖名称 | 版本 | 许可证 | 用途 |
|----------|------|--------|------|
| GCC (arm-none-eabi) | ≥ 10.3 | GPLv3+ (with Runtime Library Exception) | ARM64 交叉编译 |
| repo (Google) | ≥ 2.17 | Apache-2.0 | 多仓库源码管理 |
| GNU Make | ≥ 4.0 | GPLv3+ | 构建系统 |
| QEMU (goldfish-arm64) | ≥ 7.0 | GPLv2 | 模拟器运行环境 |

## LLM 后端依赖

| 依赖名称 | 许可证 | 用途 |
|----------|--------|------|
| DeepSeek API | 服务条款 | 远程 LLM 推理（可选） |
| 通义千问 (Qwen) API | 服务条款 | 远程 LLM 推理（可选） |
| Ollama | MIT | 本地 LLM 推理（可选） |

## 系统工具依赖

| 依赖名称 | 版本 | 许可证 | 用途 |
|----------|------|--------|------|
| Bash | ≥ 5.0 | GPLv3+ | Shell 脚本解释器 |
| curl | ≥ 7.68 | curl License (MIT-like) | API 请求 |
| jq | ≥ 1.6 | MIT | JSON 解析（测试用） |
| git | ≥ 2.25 | GPLv2 | 版本控制 |
| python3 | ≥ 3.8 | PSF License | 工具脚本 |

## 测试框架依赖

| 依赖名称 | 用途 | 备注 |
|----------|------|------|
| Bash 内置断言 | smoke_test.sh 中的单元测试 | 无额外依赖 |
| gcc -fsyntax-only | C 代码语法检查 | 仅开发阶段使用 |

---

## 说明

1. 本项目 **不直接分发** 上述依赖的源码或二进制文件，所有依赖由 `auto_build_vela.sh` 在用户环境中自动下载安装。
2. openvela 框架及其依赖遵循各上游项目的原始许可证。
3. 本项目的自定义 Tool 源码（`tools/`）和 Skill 文件（`skills/`）遵循 **Apache-2.0** 协议。
4. LLM API 服务（DeepSeek/通义千问/Ollama）为可选后端，用户需自行申请 API Key 并按各平台服务条款使用。
