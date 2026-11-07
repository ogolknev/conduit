# Working on Conduit

Conduit connects native Android and macOS apps. Read the [documentation index](docs/README.md)
when orientation is needed and [build instructions](docs/BUILDING.md) for commands.
Load only material relevant to the current task.

## Continuous improvement

- Notice concrete problems in the product, code, tests, documentation and AI
  development workflow, including these instructions. Prioritize the user's task.
- Fix a small related problem now if its cause is understood, the change is local
  and reversible, and verification does not materially expand scope. Mention the
  improvement in the result; avoid a chain of incidental cleanups.
- Put larger or unrelated actionable problems in
  [GitHub Issues](https://github.com/ogolknev/conduit/issues). Search for a duplicate
  first; update an existing issue when appropriate.
- Keep issues short: observed evidence or reproduction, impact, and a completion
  check. Omit private data, identify uncertainty, and avoid researching an entire
  solution just to file a task.
- Record defects and meaningful friction. Skip speculative polish, routine
  recoverable tool failures, and tasks whose upkeep exceeds their value.
- Add a permanent rule only for a recurring or consequential non-obvious lesson.
  State its trigger and action. Prefer improving an existing rule, script or check;
  remove obsolete or redundant guidance when touching it.

## Context and verification

- Keep this file under 400 words. Store improvement tasks in GitHub Issues, without
  a parallel TODO or session log here. Read only issues relevant to the task.
- Keep one source of truth for each decision or procedure. Link to it; do not copy
  chat transcripts, historical reports or the full backlog into active context.
- Use plans for complex work. Add skills or automation when repeated work proves
  their value, with narrow triggers and details loaded on demand.
- Run checks appropriate to the change. Reuse passing results unless changed code
  or new evidence warrants another run; keep searches and tool output targeted.
- Distinguish builds/tests from device verification. Mark unavailable hardware
  checks as unverified; restore temporary phone settings after testing.
