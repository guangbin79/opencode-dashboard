# Fzf Views

> Last updated: 2026-04-12

## Overview
- 5个 fzf TUI 视图：projects, sessions, session-agents, agents, todos
- Key files: ./lib/views/projects.sh, ./lib/views/sessions.sh, ./lib/views/session-agents.sh, ./lib/views/agents.sh, ./lib/views/todos.sh, ./lib/views/_agent_preview.py
- Dependencies: fzf 0.70+, bash 5.0+, python3
- Entry point: ./dashboard.sh
- See also: [[data-layer]], [[render-theme]], [[tmux-integration]]

## Decisions

### --expect 替代 --bind 'key:accept' 做按键路由 (2026-04-12)
- **Chosen:** fzf `--expect=Enter,1,2,3,4,q` + 解析首行获取按键
- **Alternatives:** `--bind '1:accept'` + exit code 区分（无法区分）
- **Reason:** `--bind 'key:accept'` 都以 exit code 0 返回，无法区分哪个键触发。`--expect` 在输出首行写入按键名，可精确路由
- **Tradeoff:** 输出多一行 header（key 行），需用 `head -1` / `tail -n +2` 分离

### 子进程模型：每个视图独立 fzf 调用 (2026-04-12)
- **Chosen:** dashboard.sh 主循环调用 view_* 函数，每次调用启动独立 fzf 进程
- **Alternatives:** 单一 fzf 实例 + reload，或专用 TUI 框架
- **Reason:** 简单可靠，每个视图完全独立，无状态泄漏
- **Tradeoff:** 视图切换时 fzf 重新启动（约1-2秒延迟），不如常驻 TUI 流畅

### 视图返回字符串协议 (2026-04-12)
- **Chosen:** view 函数 echo 字符串，主循环 case 解析
- 协议: "quit" | "back" | "view:projects" | "view:sessions" | "view:session-agents:<id>" | "view:agents" | "view:todos"
- **Reason:** 简单文本协议，bash 原生 case 模式匹配
- **Tradeoff:** 只支持单层导航，无法传递复杂状态

## Bug Experience

### fzf 预览面板 ANSI 转义码未渲染 (2026-04-12)
- **Symptom:** 预览面板显示 `\033[38;2;136;192;208m` 字面文本
- **Root cause:** 预览函数内的 local 颜色变量用 `'\033...'` 定义（字面量），而非 `$'\033...'`（真转义）
- **Fix:** preview 函数中的颜色变量全部改为 `$'\033...'` 语法。此 bug 与 render.sh 是同一根因，但 preview 函数定义了自己的 local 颜色变量，需要单独修复
- **Prevention:** 任何 bash 文件中定义 ANSI 转义码变量时，一律用 `$'...'` 语法

### agents.sh 列表 ANSI 未渲染 (2026-04-12)
- **Symptom:** agents 列表显示字面 `\033` 而非彩色
- **Root cause:** render.sh 的颜色变量（N_BRIGHT 等）用 `'\033...'` 定义，被 `_agent_format_line` 的 `printf '%s'` 原样输出
- **Fix:** render.sh 全局颜色变量从 `'\033...'` 改为 `$'\033...'`
- **Prevention:** 颜色变量必须在一开始就用 `$'...'` 语法定义

## Strategies

### fzf 数据流水线模式 (2026-04-12)
- **Problem:** fzf 需要带 ANSI 颜色的 TSV 输入
- **Approach:** python3 data.py 输出原始 TSV -> awk 注入 ANSI 颜色 -> fzf 消费。预览则通过独立脚本调用 data.py JSON 命令格式化
- **When to reuse:** 任何 fzf + 外部数据源的场景

### 视图文件的可独立执行设计 (2026-04-12)
- **Problem:** fzf --preview 需要调用外部命令渲染预览内容
- **Approach:** 每个视图文件 detect `$1 == "_preview"` 时执行预览逻辑，否则仅定义函数。fzf --preview 调用 `sessions.sh _preview {1} datapath`
- **When to reuse:** 任何 fzf 预览需要复杂格式化的场景

## Module Info

### 4个视图
| 视图 | 函数 | 数据命令 | 特点 |
|------|------|----------|------|
| Projects | view_projects | projects | 项目列表 |
| Sessions | view_sessions | sessions, session-meta | L2 视图，100条 |
| Session Agents | view_session_agents(id) | session-agents, session-meta | L3 视图，显示 session 的 agents |
| Agents | view_agents | agent-stats, agent-detail | 全局 agent 统计 |
| Todos | view_todos | todos, session-meta | 543条, 状态分组 |

### 按键映射
- j/k: 上下移动
- Enter: 选择/展开
- 1-4: 切换视图
- b: 返回上层
- q: 退出
- /: 搜索过滤

### agents.sh 特殊架构
- 列表颜色通过 _agent_color_name() 按agent类型映射
- 预览通过独立 Python 脚本 _agent_preview.py 渲染（避免 shell 嵌套引号问题）
