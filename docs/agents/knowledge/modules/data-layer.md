# Data Layer

> Last updated: 2026-04-12

## Overview
- Python3 数据访问层，查询 OpenCode SQLite 数据库
- Key files: ./lib/data.py
- Dependencies: stdlib only (sqlite3, json, argparse, os, datetime)
- Database: ~/.local/share/opencode/opencode.db (SQLite, ~486MB)
- See also: [[fzf-views]]

## Decisions

### Python stdlib only, no sqlite3 CLI (2026-04-12)
- **Chosen:** python3 stdlib sqlite3 模块
- **Alternatives:** sqlite3 CLI, Node.js better-sqlite3
- **Reason:** 系统无 sqlite3 CLI，python3 universally available，stdlib 零依赖
- **Tradeoff:** 无法用一行命令快速调试 SQL（需 python3 -c 包装）

### TSV 作为数据层输出格式 (2026-04-12)
- **Chosen:** TSV (Tab-Separated Values) 用于列表数据，JSON 用于详情
- **Alternatives:** 纯 JSON, CSV
- **Reason:** fzf 原生支持 `--delimiter '\t'` 和 `--with-nth`，零解析开销
- **Tradeoff:** TSV 不支持嵌套数据，复杂结构需 JSON 预览命令

### READ ONLY 连接模式 (2026-04-12)
- **Chosen:** PRAGMA query_only = ON
- **Reason:** dashboard 只读，防止误操作修改数据库
- **Tradeoff:** 未来如需写操作（如 archive session）需另开连接

## Strategies

### 避免 N+1 查询 (2026-04-12)
- **Problem:** sessions 列表需要 message count 和 agent list，逐条查询会很慢
- **Approach:** 使用 LEFT JOIN + GROUP_CONCAT 一次查询获取所有数据；agent list 用 batch 查询
- **When to reuse:** 任何需要聚合关联表数据的列表查询

## Module Info

### 8个命令接口
| 命令 | 输出格式 | 用途 |
|------|----------|------|
| sessions | TSV | Session 列表 |
| session-meta | JSON | Session 预览详情 |
| messages | TSV | 消息列表 |
| message-detail | JSON | 消息完整内容+parts |
| agent-stats | TSV | Agent 使用统计 |
| agent-detail | JSON | Agent 按model/session分解 |
| todos | TSV | Todo 列表 |
| todo-stats | JSON | Todo 按状态统计 |

### 关键表结构
- session: id, project_id, title, directory, slug, time_created/updated (epoch ms)
- message: id, session_id, data (JSON: role, agent, tokens, modelID, providerID)
- part: id, message_id, data (JSON: type=text/tool/tool-result, text, tool, state)
- project: id, name, worktree
- todo: session_id, content, status, priority, position
