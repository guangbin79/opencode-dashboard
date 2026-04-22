# AGENTS.md

## AGENTS.md 读写元规则
> 详细: `./docs/agents/index.md`
- 只写清单，不写说明
- 说明写在 `./docs/agents`
- 遵循渐进式披露

## 开发指南

### 核心原则
> 详细: `./docs/agents/core/principles.md`
- 中英双语思维链
- 先理解再行动
- 通过构建系统理解
- 遇到问题先检索 `./docs`

### 行为准则
> 详细: `./docs/agents/core/principles.md`
- 澄清意图再动手（需求有歧义就问，不假设）
- 简单优先（不写超出需求的代码，不过度抽象）
- 精准修改（只改必须改的，不附带重构）
- Trivial 豁免（≤ 1 文件且 ≤ 20 行直接执行）

### 项目结构

```
.
├── dashboard.sh          # 主入口脚本（tmux 检测、主循环、视图路由）
├── lib/
│   ├── data.py           # Python 数据层（SQLite 查询，11 个命令）
│   ├── render.sh         # Nord 主题配色与格式化工具
│   ├── tmux.sh           # tmux 环境管理（session、分屏、popup）
│   └── views/
│       ├── projects.sh   # L1: 项目列表视图（fzf）
│       ├── sessions.sh   # L2: Session 列表视图（fzf）
│       ├── agent.sh      # L3: Agent 交互视图（tmux 分屏）
│       ├── detail.sh     # 消息详情视图
│       ├── agents.sh     # Agent 统计视图
│       └── todos.sh      # Todo 列表视图
├── docs/
│   └── agents/           # Agent 开发文档
│       ├── core/         # 核心原则与开发指南
│       └── knowledge/    # 知识库（模块经验、决策记录）
└── tasks.md              # 任务计划清单
```

**关键文件说明：**
- `dashboard.sh` - 3级导航主循环（Projects → Sessions → Agent）
- `lib/data.py` - 数据访问层，提供 11 个 CLI 命令（sessions, messages, agent-status 等）
- `lib/tmux.sh` - tmux 集成，支持自动启动、分屏管理、Nord 主题
- `lib/views/*.sh` - 6 个 fzf/tmux 视图，遵循返回字符串协议（quit/back/view:*）

### Worktree 规则
- 目录: `.worktrees/<分支名>`
- 分支命名: `feature/<功能名>` | `fix/<问题名>`
- 完成后清理 worktree，保证线性历史

### 验证
- 代码修改后必须通过构建验证
- 所有警告必须修复

### 任务计划
- 编写 `tasks.md` + `tasks/` 子文件，agent 按顺序执行（参考 `./docs/agents/core/task-plan.md`）

### 知识查询与沉淀
> 详细: `./docs/agents/knowledge/knowledge-index.md`
- 操作前先加载 `project-compound` skill（提供 ingest/query/lint 三种操作模板）
- 开始模块任务前，先查 `./docs/agents/knowledge/` 了解已有经验
- 功能迭代后通过 project-compound ingest 更新知识库
- 任务完成后记录决策、策略、bug 经验（非 trivial 变更必须归档）
