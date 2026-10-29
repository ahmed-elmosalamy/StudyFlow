# StudyFlow - Implementation Roadmap

- **Status:** Draft v0.1 - awaiting approval
- **Date:** 2026-10-29
- **Related:** [Product requirements](product-requirements.md) - [Architecture](architecture.md) - [Scheduling rules](scheduling-rules.md)

No application features will be implemented until the documentation is approved. The phases below are
sequenced for early risk reduction and usable checkpoints, not calendar estimates.

---

## 0. Preconditions and approval gate

### Decisions to confirm

1. **Application ID:** `com.studyflow.studyflow` (approved and applied).
2. **Initialize git** in `C:\ai programs\StudyFlow` and commit the docs before code (recommended).
3. **Defaults:** 120 min/day; 50-min block; 15-min minimum; 10-min break; 14-day horizon; Standard
   revision preset (1/3/7/14 days, 25 min); automatic replanning on.
4. **Revision behavior:** flexible revisions with an earliest review date and no hard deadline (v1);
   preset changes apply only to topics learned afterward.
5. **Deadlines:** date-only, inclusive through end of day.
6. **Local-only data:** Android auto-backup disabled; no export/backup in v1; uninstalling loses data.
7. **Android setup:** run `flutter doctor --android-licenses` to clear the doctor warning.

### Environment status

| Check | Status |
|---|---|
| Flutter 3.44.7 / Dart 3.12.2 | Ready |
| Android SDK 36 / build-tools 36 / platform-tools | Ready |
| Android toolchain / Gradle 9.1 / AGP 9.0.1 | Verified with a scratch debug APK build |
| Pixel_7 emulator (Android 37.1, x86_64, WHPX) | AVD present; start before UI work |
| Android licenses | `flutter doctor` warns that some are unaccepted; build still succeeded. Clear before Phase 0. |
| Dependency set and Drift codegen | Resolved and validated in a disposable project; removed afterward |
| Chrome / Visual Studio | Missing, but not needed for the Android target |

### Phase 0 - Foundation (small)

**Goal:** a running, styled Android shell with the planned dependency and folder structure.

- Run `flutter create --org com.studyflow --project-name studyflow --platforms=android .` (adjust the
  application ID to the approved value), then `git init` if approved.
- Add the runtime and dev dependencies from the architecture document; set up `analysis_options.yaml`.
- Create the folder skeleton, Material 3 theme, app shell, and go_router routes with placeholder screens.
- Set the Android app name to "StudyFlow", adaptive launcher icon placeholder, edge-to-edge, and
  `allowBackup=false`; verify the release manifest does not request network access.
- Add the app database skeleton (`app_settings` singleton only) and a `ProviderScope` bootstrap.
- Smoke test on the Pixel 7 emulator.

**Verification:** `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --debug`,
manual launch on the emulator, back navigation works.

**Exit:** app boots to the Today placeholder with bottom navigation, theme switches with system dark
mode, no analyzer warnings.

---

## 1. Data foundation (medium)

**Goal:** all v1 entities persisted with tests, before UI depends on them.

- Implement Drift tables, constraints, enums, indexes, and the settings singleton.
- Implement DAOs and repositories for goals, subjects, topics, tasks, sessions, availability, settings.
- Enforce validation and deletion/archive rules; enforce `PRAGMA foreign_keys`.
- Implement revision-cycle groundwork: `topics.revision_cycle_started_on` plus the partial unique index on
  `(topic_id, revision_stage)`; implement session status transitions at repository level.
- Build test helpers: in-memory database, fake clock, entity builders.
- Tests: CRUD, FK restrictions, archiving, history immutability at the repository write level, settings
  persistence, unique revision stages.

**Verification:** repository/DAO test suite green; generated Drift code committed; no direct DB access
outside `data/`.

**Exit:** a developer can create and query the full hierarchy and sessions in tests; schema v1 reviewed
before any migration debt exists.

---

## 2. Core authoring UI (large)

**Goal:** a learner can model their work without scheduling yet.

- First-run availability setup (with recommended defaults, editable) and skip/return behavior.
- Goals list/detail, subjects list, topics list/detail; create/edit/archive/complete flows.
- Task form and task details: title, estimate, optional date-only deadline, priority, notes.
- Input validation, inline errors, unsaved-changes handling, empty/error states.
- Mark topic learned/unlearned; persist status, learned date, and the revision cycle marker (revision
  generation itself is deferred to Phase 6).
- Theme polish, typography, icons, dark mode; accessibility semantics for forms and lists.
- Widget tests for form validation, empty states, and large-text layouts.

**Verification:** full hierarchy creation persists across restart; TalkBack traversal of forms; no layout
overflow at 200% text on key screens; screenshots reviewed on the emulator.

**Exit:** all authoring flows are usable and tested; no scheduling logic duplicated in widgets.

---

## 3. Scheduling engine and availability (extra-large; the critical phase)

**Goal:** prove the scheduling contract before depending on it in the UI.

### 3a - Pure engine first

- Implement `LocalDate`, clock abstraction, settings validation, task ordering, day construction, locked
  intervals, allocation, and feasibility warnings exactly as specified in `docs/scheduling-rules.md`.
- Implement revision-eligibility inputs (`notBefore`) even though revision generation lands later.
- Build the deterministic golden test suite and property-style invariant tests from the rules document.
- Add a benchmark test with 300 tasks over 14 days.
- **Checkpoint:** review engine rules and failed/passing scenarios before UI integration. Any change to the
  spec is agreed here.

### 3b - Availability settings and plan UI

- Availability settings: weekly windows per day, daily limit, block length, minimum, break, horizon.
- Rebuild-plan action, Schedule screen (next 7 days + full horizon), per-day planned/capacity summary.
- Feasibility banners and task-level warning details, including beyond-horizon information; task form
  deadline preview. Deferred `notBefore` warnings are exercised by engine tests here and surfaced in the
  revision UI in Phase 6.
- Wire plan runs through `PlanService` with transaction semantics and single-flight behavior.
- Persist future sessions; expose plan streams to Today and Schedule.
- Tests: service integration with in-memory DB, widget tests for warning rendering, plan refresh after
  availability changes.

**Verification:** generated plans satisfy every hard guarantee on seeded scenarios and a manual emulator
walkthrough; an impossible deadline shows correct numbers and copy; plan warnings are reviewable in task
details.

**Exit:** engine test suite covers the test matrix; schedule generation is deterministic and visible; no
completed, missed, or learner-cancelled rows are changed by a plan run.

---

## 4. Daily use and missed-session recovery (medium-large)

**Goal:** the app handles real life.

- Today screen: capacity header, next session, chronological sessions, completed section, empty states.
- Session actions: cancel and complete with actual minutes (the timer and in-progress state arrive in
  Phase 5).
- Reconciliation service: missed detection, active-session retention, automatic replan triggers,
  app lifecycle and midnight handling.
- Auto-replan setting toggle and `plan_stale` set/clear wiring; change summary after replan; stale-plan
  banner when auto-replan is off; manual rebuild. With auto-replan off, reconcile still marks missed
  sessions and removes future rows for completed/cancelled/archived work, but does not move or create
  sessions.
- Preserve completed/missed history; remove future sessions when tasks complete/cancel/archive; handle
  estimate edits and deadline changes.
- Tests: reconciliation idempotence, partial completion math, missed history immutability, auto/manual
  replan behavior, auto-replan-off cleanup and stale-flag set/clear, lifecycle triggers.

**Verification:** scenario test/emulator demo: miss a day -> completed history intact -> remaining work
moves to valid slots; changing availability/deadline updates the plan; no overlaps or limit violations.

**Exit:** a learner can run a full day from the Today screen and recover from missed sessions without
manual arithmetic.

---

## 5. Focus timer and progress (medium-large)

**Goal:** measure real study time and report it clearly.

- Full-screen focus timer: countdown, pause/resume, finish early, persisted timestamps, restore after
  process death, exactly one active timer.
- Stale-timer resolution on start/resume: an unresolved session from an earlier day is paused and surfaced
  with finish/adjust/discard options; it stays locked and blocks new timers until resolved.
- Completion sheet with actual minutes + optional note; shared transaction path with manual completion;
  discard credits no time and marks the session cancelled.
- Timer semantics and announcements; confirm before leaving while running.
- Progress screen: today/week summary, weekly minutes chart, subject/goal progress, revision stats
  placeholder; accessible textual equivalents; empty states.
- Tests: fake-clock timer math, restart restoration, stale-timer finish/discard paths, completion updates
  task and future plan, progress aggregation reconciles with sessions, widget accessibility at 200% text.

**Verification:** force-stop and relaunch while a timer is running -> elapsed is correct; finishing early
reschedules remainder; progress totals match session logs.

**Exit:** focus timer and progress are reliable on the emulator with a fake clock test suite.

---

## 6. Revisions and release polish (medium)

**Goal:** spaced revision and a shippable-feeling v1.

- Revision service: set the per-topic cycle marker on first "learned", generate stages idempotently,
  cancel on unlearn/archive, no hard deadlines, earliest review date. Preset changes
  (Off/Light/Standard) apply only to newly learned topics; existing revision tasks and cycles are left
  untouched.
- Revision UI in topic details (next review, stage list, deferred review date), Today/Schedule badges.
- Revision stats in Progress.
- Accessibility audit: TalkBack pass, 48dp targets, contrast check light/dark, reduce motion, large text.
- Performance check: cold start, scrolling, plan rebuild benchmark on emulator.
- End-to-end integration test: fresh install -> setup -> hierarchy -> plan -> complete/miss -> revisions ->
  progress.
- Release candidate: `flutter build apk --release`, verify release manifest has no INTERNET permission,
  no debug logs, launcher icon, app label, edge-to-edge.

**Verification:** all automated tests green; manual accessibility checklist; release APK installs and runs
offline in airplane mode; impossible deadlines and missed-session recovery demoed end-to-end.

**Exit:** v1 definition of done in the PRD is met. No notifications, sync, ads, or AI features were added.

---

## 7. Hardening (small; can overlap with Phase 6)

- Fix issues found in manual testing and edge-case audits (clock changes, empty windows, missing data).
- Add migration readiness notes/schema dump; document codegen workflow.
- Update docs to reflect final behavior and add a short contributor/run guide.
- Optional (only if approved): GitHub Actions for analyze/test once a repository exists.

**Exit:** documented release candidate, no known critical defects, clean `flutter analyze` and tests.

---

## Phase summary and relative effort

| Phase | Scope | Relative effort | Depends on |
|---|---|---|---|
| 0 | Foundation, shell, theme, Android config | S | Approval |
| 1 | Database, repositories, tests | M | 0 |
| 2 | Goals/subjects/topics/tasks UI | L | 1 |
| 3a | Pure scheduling engine, golden/property tests | L-XL | 1 |
| 3b | Availability settings, plan UI, warnings | L | 2, 3a |
| 4 | Today, missed sessions, replan triggers | M-L | 2, 3b |
| 5 | Focus timer, progress | M-L | 4 |
| 6 | Revisions, accessibility, release polish | M | 4, 5 |
| 7 | Hardening | S | 6 |

Relative effort is for planning order only - no delivery dates are promised here.

---

## Verification and quality gates

### Automated, every phase

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
dart run build_runner build     # after schema/table changes
flutter build apk --debug       # at least at phase ends
```

### Manual, Android emulator

- Install/run on the Pixel 7 AVD (Start with `flutter emulators --launch Pixel_7`).
- Airplane mode check for offline behavior and absence of network prompts.
- TalkBack pass on new screens.
- Dark mode and 200% font scale check.
- Rotate/landscape sanity check on forms and dialogs.

### Review gates

1. **After documentation:** approval to scaffold the project and start Phase 0.
2. **After Phase 3a:** review the scheduler spec and golden tests before wiring the UI.
3. **After Phase 4:** demo the daily loop + missed-session recovery.
4. **Before release candidate:** accessibility/performance pass and full regression suite.

Each phase ends with a concise summary of what changed, test evidence, and known limitations. No phase
starts until the previous phase's exit criteria are met (or a scope adjustment is explicitly agreed).

---

## Risks and mitigations

| Risk | Likelihood/Impact | Mitigation |
|---|---|---|
| Scheduler edge cases (deadlines, locks, breaks) | Medium / High | Spec-first, pure engine, golden + property tests, review gate after 3a |
| Scope creep (notifications, cloud, AI, sharing) | High / High | Written non-goals; any addition goes through approval and roadmap update |
| Availability UX feels like work | Medium / Medium | Sensible defaults, editable windows, skip for now; simple day grids |
| Task/topic hierarchy too rigid | Medium / Low | Strict hierarchy is v1 scope; reassess after real usage |
| Data migrations break users later | Low in v1 / High later | Freeze schema after review; export schema; migration tests before changing it |
| Drift/codegen/build friction | Low / Medium | Workflow validated; generated files committed; documented commands |
| Emulator-only testing misses device quirks | Medium / Medium | Keep Android APIs standard; avoid permissions/background services; manual device check before release if available |
| Accessibility regressions | Medium / Medium | Semantics and large-text tests per phase; manual TalkBack audit in Phase 6 |
| Timer accuracy expectations | Medium / Medium | Timestamp-based state, clear v1 limitation: no background alert |
| Plan churn feels unstable | Medium / Medium | Only replace future sessions; stable locks; change summary; auto-replan opt-out |

---

## Out of scope for this roadmap (deferred)

- Notifications and background timer alerts.
- Data export/backup, encryption.
- Per-date availability exceptions.
- Cloud sync, accounts, collaboration.
- AI features, ads, subscriptions.
- iOS/web builds, widgets, Wear OS.
- Custom revision intervals beyond presets.

---

## Immediate next steps after approval

1. Confirm the seven decisions in Section 0.
2. Accept Android licenses (`flutter doctor --android-licenses`).
3. Initialize git and commit the docs.
4. Scaffold the app in Phase 0 with the approved application ID.
5. Start Phase 1 (data foundation), keeping the scheduler untouched until Phase 3a.
