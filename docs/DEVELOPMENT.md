# Development with coding agents

[Agent guidance](../AGENTS.md) contains the short repository rules. This page is
loaded for planning, review or handoff, not required reading for every edit.

## Start a task

Use a focused branch such as `fix/bluetooth-reconnect` or `feat/notification-filter`.
An issue or the PR description holds the expected user-visible outcome and a
completion check. Small direct requests do not need a separate tracking issue.
Use [GitHub Issues](https://github.com/ogolknev/conduit/issues) for deferred work;
search for an existing task before adding one.

For complex changes, keep a short living plan in that same issue or PR:

- Outcome and constraints, including compatibility when relevant.
- A few implementation steps and the checks that prove each outcome.
- Current progress, important decisions and unresolved evidence.

A new chat should be able to resume from the branch, task and relevant documents.
Transfer only current facts and next actions. Do not copy a whole transcript or
maintain a second task backlog in the repository.

## Implement and check

Read the relevant architecture/design section and affected code. Keep the diff
focused; add regression coverage for observable behavior when it can catch a real
failure. Do not write tests that just repeat implementation details.

[Build instructions](BUILDING.md) contain commands. The `Checks` workflow runs on
pull requests and pushes to `main`:

| Job | Coverage |
| --- | --- |
| Repository | Agent context budget, local documentation links, brand/localization generation and release-packaging regression tests |
| Swift | Existing Swift test suites and compilation on macOS |
| Android JVM | Pairing, Bluetooth permission and diagnostic-text checks on JDK 17 |

CI does not currently assemble a full APK or prove device behavior. For runtime,
resource or packaging changes, build affected apps locally. For Bluetooth, Shizuku,
permissions, notifications or UI changes, exercise the relevant device scenario
when hardware is available. Describe missing checks explicitly. Restore temporary
screen or power settings after device testing.

## Review and finish

Before merging, review the actual diff and checks, especially:

- Both sides of changed protocol messages and stale-session behavior.
- Actual permission/connection state, cancellation and error paths.
- Generated-resource sources, signing identity and diagnostic privacy.

Use an independent AI review when useful; always inspect its findings against the
code. Review does not imply that another agent must be launched for every task.
Summarize behavior, validation and meaningful limits in the PR. Update affected
documentation, close the task when its acceptance check is met, and remove or mark
obsolete plans. A green build and a successful device scenario are separate evidence.

[Continuous improvement](../AGENTS.md#continuous-improvement-and-context-budget)
applies throughout. Improve the smallest relevant rule or check rather than adding
another general instruction after every incident.
