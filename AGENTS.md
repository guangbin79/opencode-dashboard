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
