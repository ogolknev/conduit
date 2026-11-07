# Working on Conduit

Native Android and macOS apps for clipboard, notifications and files.

## Route context by task

- [Architecture](docs/ARCHITECTURE.md): transport, lifecycle, compatibility decisions.
- [Development](docs/DEVELOPMENT.md): tasks, plans, review and completion.
- [Building](docs/BUILDING.md): toolchains and verification commands.
- [Design](docs/DESIGN.md): interface and icons.
- [Validation](docs/VALIDATION.md): observed device results and remaining limits.
- Releases: use the project `conduit-release` skill and [release guide](docs/RELEASING.md).

Read only relevant material. Start work from this repository root.

## Project invariants

- Keep Mac/Android wire contracts compatible. Preserve app identities and update
  signing continuity; explain intentional compatibility changes in the task.
- Edit translations in `localization/strings.json` and brand geometry in
  `design/brand.json`; regenerate native resources instead of patching outputs.
- Keep clipboard/notification content, tokens, signing keys and raw device
  diagnostics out of tracked files. Restore temporary phone settings after testing.

## Work and verify

- Use a task branch. Record outcome and acceptance criteria in its issue or PR;
  keep a short living plan there for complex changes. Avoid duplicate paperwork.
- Run checks appropriate to the diff; see build instructions. Review the final
  change for compatibility, state handling and regressions before merging.
- Distinguish builds/tests from device verification; mark unavailable hardware
  checks as unverified. Reuse passing results until changes or evidence justify reruns.

## Continuous improvement and context budget

- Notice problems in the product and AI development workflow, including these rules.
  Fix small related, understood, reversible problems when verification stays within
  scope. Mention the improvement; prioritize the user's task over cleanup chains.
- Record larger or unrelated actionable problems in [GitHub Issues](https://github.com/ogolknev/conduit/issues).
  Search for duplicates first. Include evidence, impact and a completion check;
  omit private data and identify uncertainty. Do not research a whole solution to file it.
- Skip speculative polish, routine recoverable tool failures and low-value tasks.
- Add permanent guidance only for recurring or consequential non-obvious lessons.
  Prefer improving existing rules, scripts or checks; remove obsolete duplication.
- Keep this file under 400 words. Read issues and documents on demand; do not load
  the full backlog, historical reports or chat transcripts. Keep one source of truth.
- Add skills or automation when repeated work proves useful, with narrow triggers.
  Keep searches and tool output targeted; avoid repeated full-file reads.
