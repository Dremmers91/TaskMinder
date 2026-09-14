# TaskMinder

A lightweight WoW Retail addon for a character-specific recurring task checklist.

The addon exposes `TaskMinder:CreateTask`, `UpdateTask`, `DeleteTask`,
`CompleteTask`, and `ReactivateTask`. Tasks are saved per character in
`TaskMinderDB`. Use `/taskminder` or `/tm` to toggle the active-task checklist.
The native minimap button provides the same toggle and can be dragged around the
minimap; its position is also saved per character.
Use the checklist gear button to add, edit, or delete all tasks, including
completed tasks.

The checklist window can be dragged by its title bar and resized from its
bottom-right grip. Its size, position, and lock setting are saved per character.

TaskMinder's dark native-WoW theme is centralized in `TaskMinder.Theme` so future
Minder addons can reuse its palette, typography, spacing, and control styling.
