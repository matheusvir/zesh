# Contributing to protoshell on sackOS

This document is the single workflow reference for all three fronts of this project.
It covers how to open issues, branch, commit, open pull requests, test, review,
and integrate work across fronts.

## 0. Purpose and scope

- `zesh` holds the shell, utilities, docs, and project issues. It includes
  `zepa-machine` as a submodule.
- `zepa-machine` (fork under active development, base branch `sackOS-paginated`)
  holds the ZEPA virtual machine, the sackOS paginated kernel, the
  cross-assembler, and the TUI debugger.
- Front 1 owns syscalls, the syscall/argv contract, and console.
  Front 2 owns `exec` and the read-only in-memory filesystem.
  Front 3 owns the shell loop and the `echo`, `true`, `false`, `pid`, `wc`
  utilities plus the `help` and `exit` builtins.
- Issues and GitHub Projects are the official task administration.

## 1. Language

- Write in English: commits, branch names, pull requests, code comments in
  `.asm` and Go, issues, and `contracts.md`.
- Portuguese is allowed only for: the course report, the Substack post,
  and meeting notes.
- Rationale: mixed-language git history is unsearchable.

## 2. Repository structure

Target layout — directories appear as their issues land (`shell/`, `utils/`, `rt.asm`, `stubs.asm`, `contracts.md` do not exist yet).

| Path | Content |
|---|---|
| `contracts.md` | Frozen syscall/argv contract (see section 11) |
| `shell/` | Shell sources in ZEPA assembly |
| `utils/` | `echo`, `true`, `false`, `pid`, `wc` sources |
| `rt.asm`, `stubs.asm` | Shared assembly idioms and test doubles |
| `docs/` | Report drafts, demo logs, meeting notes |
| `zepa-machine/` | Submodule pointer to the fork (see section 9) |

Assembly file naming: `<component>_<name>.asm` in English, for example
`shell_loop.asm`, `util_echo.asm`. Test fixtures end with `_test.asm` and live
next to the file they exercise.

## 3. Issue model and lifecycle

An issue is the unit of planning. A big issue can have subtasks and can be
delivered through more than one pull request.

Lifecycle (board columns):

```text
Backlog -> To Do -> In Progress -> Review -> Validated -> Done
```

- `Backlog`: accepted idea, scope or owner not yet fixed.
- `To Do`: issue body complete (section 4), owner and reviewer assigned.
- `In Progress`: someone is actively working on it.
- `Review`: at least one PR is open against it.
- `Validated`: the reviewer re-ran the acceptance criteria green and approved. Approval does not merge — the lead merges afterwards (see section 12).
- `Done`: closed after validation.

An issue is done when all its acceptance criteria are checked, not when a
given number of PRs is merged.

## 4. Issue format

Title the issue like a conventional commit (section 7):

```text
feat(f3): echo utility
fix(f1): wait faults on untouched status address
docs(contracts): freeze argv block layout
```

Body template:

```markdown
## Objective

## Planning

| Field | Value |
|---|---|
| Complexity | [ ] Low [x] Medium [ ] High |
| Estimated effort (h) | 4h |
| Owner(s) | @user |
| Reviewer | @user (assigned at creation, see section 12) |
| Where | zesh (shell/utils/docs) or zepa-machine fork (kernel/VM) |

## Description

## Supporting Material

### Required

### Supplementary

## Deliverables

## Acceptance criteria

- [ ] Criterion 1, replicable in the TUI
- [ ] Criterion 2

## Notes

## Subtasks

- [ ] Subtask 1 -> branch `feat/f3-echo-utility-12`, PR #<n>
- [ ] Subtask 2 -> branch `test/f3-echo-fixtures-12`, PR #<n>
```

Rules:

- Fill `Where` explicitly: work on shell, utilities, or docs branches off
  `zesh`; work on the kernel, emulator, or TUI branches off the
  `zepa-machine` fork from `sackOS-paginated`. This keeps the two flows
  from being mixed in one issue.
- Every issue names its reviewer at creation time.
- Acceptance criteria must be replicable: exact commands plus expected
  outputs or exit codes.

## 5. Labels

Minimum viable set:

| Label | Use |
|---|---|
| `front-1`, `front-2`, `front-3` | Which front owns the issue |
| `integration` | Cross-front testing on the integration board |
| `type: feat`, `type: fix`, `type: docs`, `type: test`, `type: chore` | Mirrors the commit type |
| `priority: critical-path`, `priority: normal` | Critical path blocks other fronts |
| `blocked` | Waiting on another front or contract decision |
| `needs-review` | Waiting for reviewer attention |
| `needs-validation` | Merged but not yet re-ran by a second person |
| `good-first-task` | Low complexity, no dependencies |
| `size: S`, `size: M`, `size: L` | Rough size for board filtering |

Rules:

- Every issue carries exactly one `front-*` label, one `type:*` label,
  and one `priority:*` label. `integration` is added only when the card
  moves to the integration board.
- Labels live on issues. Pull requests inherit context through the linked
  issue. Only `needs-review` and `needs-validation` are also applied
  to pull requests.
- The global lead creates the full label set above before the boards open.

## 6. Branches

Two flows, same naming logic:

- `zesh` (shell, utilities, docs, contracts): branch off `main`.
- `zepa-machine` fork (kernel, emulator, TUI, assembler): branch off
  `sackOS-paginated`.

Name branches with the issue type, scope slug, and issue number.
Parentheses are not valid in branch names, so the issue title
`feat(f3): echo utility` with issue #12 maps to branch `feat/f3-echo-utility-12`:

```text
<type>/<short-slug>-<issue-number>
```

- `<type>` mirrors the commit type: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, or `chore`.
- `<short-slug>` is 2-4 kebab-case words, starting with the front or
  component (`f1-`, `f2-`, `f3-`, `kernel-`, `contracts-`).
- `<issue-number>` is the GitHub issue the branch implements (the board is
  the source of truth — if it is not on the board, it is not being worked on).

| Prefix | Use | Example |
|---|---|---|
| `feat/` | New functionality | `feat/f3-echo-utility-12` |
| `fix/` | Bug fix | `fix/f1-wait-status-touch-18` |
| `refactor/` | Code change without behavior change | `refactor/kernel-schedule-loop-22` |
| `perf/` | Performance-only change | `perf/tui-refresh-rate-24` |
| `docs/` | Contracts, issues docs, report drafts | `docs/contracts-argv-v2-21` |
| `test/` | Fixtures and test-only changes | `test/f3-wc-fixtures-27` |
| `chore/` | Pin bumps, tooling | `chore/bump-zepa-machine-sha-30` |

Rules:

- Every branch implements exactly one issue; a large issue may have several branches, one per subtask (see section 4). Never push directly to `main` or to `sackOS-paginated`.
- Branch from an up-to-date base (`main` for `zesh`, `sackOS-paginated`
  for the `zepa-machine` fork); keep the branch focused on its issue.
- If the scope changes, open a new issue and a new branch instead of
  widening the current one.
- Delete the branch after merge.

## 7. Commits

Follow Conventional Commits with a scope:

```text
<type>(<scope>): <short description>
```

- Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`.
- Scopes: `f1`, `f2`, `f3`, `kernel`, `contracts`, `docs`, `chore`.
- Small commits, imperative mood.

Rules:

- Imperative, lowercase subject, no trailing period, keep it short.
- Keep commits small and single-purpose; prefer a series of reviewable
  commits over one large one.
- Do not mix unrelated areas in one commit.

Examples:

```bash
feat(f3): echo utility (closes #12, subtask 1)
fix(kernel): touch wait status slot before syscall
docs(contracts): freeze read/write numbers
test(f3): add wc fixtures with hand counts
chore: bump zepa-machine to e8fd798
```

## 8. Pull requests

Title a PR like a commit. Body template:

```markdown
## What was done

## How to test
## Task reference
## Evidence

## Docs

- [ ] `CONTRIBUTING.md` section 2 tree still matches the repo, or N/A
```

- `How to test` must be copy-pasteable: working directory, exact
  `go run -tags kernel . <memory_size> <time_slice>` command, TUI input
  sequence, and expected outputs or exit codes.
- `Task reference` states the issue and subtasks, for example
  `Issue #12, subtasks 1-2`. An issue delivered through several PRs
  closes only on the last validation PR or on a validation comment with
  TUI evidence.
- `Evidence` is exit codes, TUI memory dumps, or `go test` output.
- One PR covers one syscall on the kernel side or one utility on the
  shell side when that makes sense. A PR never spans two issues; split
  it instead.
- Use `Closes #<n>` only on the final PR of a multi-PR issue; earlier PRs
  use `Refs #<n>` so the issue is not auto-closed early.
- When opening the PR, set the GitHub reviewer to the reviewer already
  named in the issue. GitHub issues have no reviewer field, only
  assignees, so the issue body field plus the PR reviewer assignment
  together carry the reviewer from birth to merge.
- The reviewer approves without merging. After approval the card moves to
  `Validated`; the lead then merges or reports conflicts back to the dev.

## 9. Submodule workflow

- Development on the machine and kernel happens in the fork on top of
  `sackOS-paginated`. Never point work at an unrelated base.
- The `zepa-machine` pin in `zesh` moves only to an already reviewed
  commit, through a tiny PR such as `chore: bump zepa-machine to <sha>`.
- The front lead prepares the bump for their own delivery; the global
  lead merges the bump so the shared pointer stays consistent.
- Never commit a pin pointing at an unreviewed local commit.

Prerequisite: Go ≥ 1.23 (see `zepa-machine/go.mod`; 1.23.1 required).

Clone with submodules:

```bash
git clone --recurse-submodules <zesh-url>
# or, on an existing clone:
git submodule update --init
```

Run from inside the submodule checkout (the kernel path is relative):

```bash
cd zepa-machine
go run -tags kernel . 2GB 128
```

## 10. Testing and replication standard

Three tiers:

1. `go test ./...` inside `zepa-machine` for Go-side changes
   (`go test ./machine`, `go test ./cross-assembler` for a focused run).
2. `.asm` fixtures asserting through exit codes. Codes 1-3 are reserved
   (1 fault, 2 external kill, 3 out of frames), so test assertions use
   codes >= 10.
3. Manual TUI replication steps written in the PR body.

No PR merges without a fixture for behavior changes plus TUI steps in
the body. Validation means the reviewer re-runs both.

Useful checks:

```bash
cd zepa-machine
go test ./...
go vet ./...
python3 instruction_counter.py sackOS/kernel.asm
```

## 11. Syscall/argv contract and cross-front changes

ABI means the binary contract here: syscall numbers, which registers
carry which arguments (`W8`/`W7`/`W6`), the return in `W9`, and the argv
block layout with its fixed load address. The rest of this document
calls it the syscall/argv contract. `contracts.md` is its single source
of truth.

Simple rule for changes:

- Whoever changes the contract notifies the affected fronts in the
  related issue and updates `contracts.md` in the same PR.
- No formal multi-front sign-off. If there is a conflict, the alignment
  meeting resolves it.

## 12. Roles and responsibilities

- Front leads merge pull requests for their own front's attributions, only after the issue is `Validated`. If the merge surfaces conflicts, the lead reports them back to the dev instead of resolving silently.
- The global lead arbitrates contract conflicts, keeps the boards tidy,
  and merges the submodule pin bumps.
- Every issue names owner and reviewer at creation.
- Every PR needs at least one review, and reviewer and author must be
  different people.
### The reviewer role

Every issue has exactly one reviewer, named in the Planning table at
creation and set as PR reviewer when the first PR opens (section 8).
The reviewer owns verification, never implementation:
- re-runs the TUI steps and fixtures and checks every acceptance criterion;
- comments or suggests; the author applies the fix (see below);
- sets `needs-review` when their attention is required;
- flips the card to `Validated` after a green re-run and approval, recording evidence in the issue or PR (approval never merges — the lead merges afterwards);
- sends scope or acceptance problems back to `To Do` with the original
  owner instead of fixing them silently.
The front lead assigns the reviewer at issue creation; the global lead
arbitrates conflicts.
- The author fixes, the reviewer points. The reviewer comments or
  suggests; the author applies the fix. Direct reviewer commits are
  allowed only for typos and Portuguese content under `docs/`. A scope or acceptance
  problem found in review sends the issue back to `To Do` with its
  original owner.
- Reviewing means re-running the TUI steps and checking the acceptance
  criteria, not just reading the diff.
- Getting help: ping your front lead, or the global lead for contract and
  board questions. Adding the `blocked` label plus a comment on the issue
  is the escalation path; the alignment meeting resolves conflicts.

## 13. GitHub Projects workflow

Four boards: `Front 1`, `Front 2`, `Front 3`, and `Integration`.

Boards live in https://github.com/users/matheusvir/projects/6 as four board views (tabs): `Front 1`, `Front 2`, `Front 3`, `Integration` (GitHub exposes no per-view deep links — open the project and pick the tab).
The board is the source of truth for what is in flight — if it is not
on the board, it is not being worked on.

Each front board uses the columns from section 3:

```text
Backlog -> To Do -> In Progress -> Review -> Validated -> Done
```

### The pipeline

Each transition has an entry condition. Do not skip ahead, and do not
park an issue in `In Progress` once the work is finished.

| Transition | Move it when | Also do |
|---|---|---|
| `Backlog` -> `To Do` | Assignment: scope is frozen, the issue body follows section 4, and owner plus reviewer are named. | Apply one `front-*`, one `type:*`, and one `priority:*` label. |
| `To Do` -> `In Progress` | Start: you have actually started the work and can name what you are doing next. | Assign the issue to yourself on the board. |
| `In Progress` -> `Review` | Implementation done: the work is committed and a PR is open. | Link the PR from the issue, set the PR reviewer to the issue reviewer (section 8), and describe how you ran the acceptance criteria. Checkboxes may only be ticked if you actually ran them. |
| `Review` -> `Validated` | Review: the reviewer re-ran the TUI steps and fixtures green and approved (approval does not merge). | Record evidence (exit codes, dumps, `go test` output) in the issue or PR. |
| `Validated` -> `Done` | Merge / conflict resolution: the lead merged the PR (or the last PR), or reported merge conflicts back to the dev. | Close the issue once merged. A PR closed without merging is not `Review` — return the issue to `In Progress`. |

### Rules

- **One task at a time.** A single `In Progress` item per person. If you are
  blocked, add the `blocked` label and say so on the issue rather than
  leaving it silently claimed.
- **Claim before starting.** Setting `In Progress` and an assignee is how the
  team knows a task is taken. It is a coordination signal, not bookkeeping.
- **A task without verified acceptance criteria is not `Review`.**
  "Looks right" is not a check. Record the command you ran and what it
  printed, in the PR or in a validation comment.
- **One card is one issue.** Link PRs to the card. Filter by labels
  from section 5.
- **Integration board.** A card moves to the `integration` board only after
  it is `Validated` on its home board and needs cross-front testing (for
  example real shell plus real `exec`). `Done` on the integration board
  means the end-to-end demo passes.
- **Respect the dependency order** stated in the issue graph. The board does
  not enforce it, so it is on whoever picks up a task to check that its
  dependencies are `Validated` first.
- **Spikes are disposable.** A spike exists to prove or kill an assumption.
  Killing it is a successful outcome: close the issue, record the finding,
  and replan before building on it.
