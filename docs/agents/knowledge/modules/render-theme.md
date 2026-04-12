# Render Theme

> Last updated: 2026-04-12

## Overview
- Nord 配色 ANSI 转义码变量和格式化工具函数
- Key files: ./lib/render.sh
- Dependencies: bash 5.0+, coreutils (date, printf, tr)
- See also: [[fzf-views]]

## Decisions

### Nord 配色方案 (2026-04-12)
- **Chosen:** Nord (https://www.nordtheme.com/) 16色方案
- **Alternatives:** Dracula, Solarized, Catppuccin, Tokyo Night
- **Reason:** 冷色调低对比度，长时间使用不疲劳，与终端/tmux 集成好
- **Tradeoff:** 暖色调偏好用户可能不喜欢

### 颜色变量集中定义在 render.sh (2026-04-12)
- **Chosen:** 所有 ANSI 颜色定义为 bash 变量，视图文件 source 引用
- **Alternatives:** 每个视图文件自行定义颜色
- **Reason:** 单一真相源，改一处全局生效
- **Tradeoff:** 所有视图依赖 render.sh

## Bug Experience

### ANSI 转义码字面量问题 (2026-04-12)
- **Symptom:** fzf 列表和预览面板显示 `\033[38;2;...` 字面文本而非彩色输出
- **Root cause:** bash 中 `local C='\033[...'` 存储的是字面字符串，不是 ANSI 转义码。需要 `$'\033[...'` 语法才能得到真正的转义字符
- **Fix:** 所有颜色变量从 `'\033...'` 改为 `$'\033...'`。影响 render.sh、sessions.sh、detail.sh 中的颜色定义
- **Prevention:** bash 中定义 ANSI 转义码变量时，始终用 `$'...'` 语法而非 `'...'`。这个规则适用于所有通过 printf/echo 输出的颜色变量

## Module Info

### 颜色-语义映射
| 语义 | 颜色 | 变量 |
|------|------|------|
| 标题/高亮 | nord8 cyan | N_CYAN |
| 路径/目录 | nord9 blue | N_BLUE |
| Agent名 | nord7 teal | N_TEAL |
| 成功/完成 | nord14 green | N_GREEN |
| 进行中/警告 | nord13 yellow | N_YELLOW |
| 错误/停止 | nord11 red | N_RED |
| 主文本 | nord4 | N_FG |
| 暗淡/时间戳 | nord3 | N_DIM |
| 特殊 | nord15 purple | N_PURPLE |

### 11个工具函数
n_color, n_bold, n_dim, n_truncate, n_relative_time, n_format_tokens, n_status_icon, n_priority_icon, n_role_icon, n_separator, n_header_bar

### fzf 颜色配置
FZF_NORD_COLORS 字符串用于 fzf `--color` 选项，覆盖 fg/bg/hl/pointer/prompt/marker 等16个槽位
