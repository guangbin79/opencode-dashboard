# AGENTS.md

## AGENTS.md 读写元规则
- 只写清单，不写说明
- 说明写在 `./docs/agents`
- 遵循渐进式披露
> 详细: `./docs/agents/index.md`

## 开发指南

### 核心原则
- 中英双语思维链
- 先理解再行动
- 通过构建系统理解
- 遇到问题先检索 ./docs

### Worktree 规则
- 目录: `.worktrees/<分支名>`
- 分支命名: `feature/<功能名>` | `fix/<问题名>`
- 完成后清理 worktree，保证线性历史

### 验证
- 代码修改后必须通过构建验证
- 所有警告必须修复

### 知识查询与沉淀
- 开始模块任务前，先查 `./docs/agents/knowledge/` 了解已有经验
- 功能迭代后更新 `./docs/agents/knowledge/`
- 任务完成后记录决策、策略、bug 经验到 `./docs/agents/knowledge/`
> 详细: `./docs/agents/knowledge/knowledge-index.md`
