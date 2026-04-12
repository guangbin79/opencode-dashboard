# Tmux Integration

> Last updated: 2026-04-12

## Overview
- tmux 环境管理：自动创建 session、Nord 主题、窗口标题
- Key files: ./lib/tmux.sh
- Dependencies: tmux 3.2a+
- See also: [[render-theme]]

## Decisions

### 自动检测 tmux 并启动 (2026-04-12)
- **Chosen:** 不在 tmux 中时自动 `tmux_init_session`，已在 tmux 中则直接运行
- **Alternatives:** 要求用户手动启动 tmux
- **Reason:** 零摩擦启动体验
- **Tradeoff:** dashboard.sh 被 tmux attach 后重新执行，需注意脚本幂等性

## Module Info

### 8个函数
| 函数 | 用途 |
|------|------|
| tmux_init_session | 创建/附加 tmux session + Nord 主题 |
| tmux_is_running | 检测是否在 tmux 内 |
| tmux_get_width/height | 获取终端尺寸 |
| tmux_popup | tmux 3.2+ popup 或降级 split-window |
| tmux_set_title | 设置窗口标题 |
| tmux_clear | Nord 背景色清屏 |
| tmux_restore | 退出时恢复 tmux 状态 |

### Nord tmux 主题配置
- window-style: bg=#2E3440 (nord0)
- pane-border-style: fg=#4C566A (nord3)
- pane-active-border-style: fg=#88C0D0 (nord8)
- status: off (dashboard 运行时隐藏状态栏)
