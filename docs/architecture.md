# StudyFlow - Architecture

- **Status:** Draft v0.1 - awaiting approval
- **Date:** 2026-10-29
- **Related:** [Product requirements](product-requirements.md) - [Scheduling rules](scheduling-rules.md) - [Roadmap](roadmap.md)

---

## 1. Purpose and constraints

StudyFlow is a single-user, offline-first Android app. The architecture is optimized for:

- **Trustworthy scheduling.** The planner is pure, deterministic Dart and independently testable.
- **Local data integrity.** A local SQLite database is the single source of truth; no server exists.
- **Fast iteration by a small team.** Few dependencies, minimal generated code, clear feature folders.
- **History preservation.** Completed study records are append-only in practice; replanning only
  replaces future, unstarted plan entries.
- **Accessibility and polish** on Android, without a design-system dependency.

Non-negotiable constraints from the product requirements: no account, no network calls, no ads, no
subscriptions, no AI APIs, no overlapping sessions, no exceeding daily limits, deterministic plans.

---

## 2. Verified toolchain

Environment checked on 2026-10-29:

| Item | Result |
|---|---|
| Flutter | 3.44.7 stable (Dart 3.12.2, DevTools 2.57.0) |
| Android SDK | Platform 36.0.0 / android-36.1, Build-Tools 36.0.0, platform-tools 37.0.1 |
| Android build defaults (Flutter 3.44.7) | Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20, compile/target SDK 36, min SDK 24 |
| JDK | Android Studio JBR 25.0.3 (used by Flutter); Temurin 21 also on PATH |
| Emulator | `Pixel_7` AVD, Android 37.1 (Google APIs Play Store), x86_64, 2 GB RAM; WHPX acceleration available |
| Devices now | No emulator running; Windows/Edge targets listed by Flutter but not used for this app |
| Android licenses | `flutter doctor` reports some licenses not accepted; a scratch debug APK built successfully anyway. Run `flutter doctor --android-licenses` to clear the warning. |
| Web/desktop | Chrome not installed; Visual Studio absent. Not required - the delivery target is Android. |

**Dependency validation performed:** a disposable Flutter Android project outside the workspace
resolved the planned dependency set, generated Drift code, passed `flutter analyze`, and built a debug
APK with no errors. The scratch project was deleted afterward.

---

## 3. Technology stack and dependencies

Versions were checked on pub.dev on 2026-10-29. Use caret constraints as listed.

### Runtime

| Package | Version | Role | Notes |
|---|---|---|---|
| `flutter` | 3.44.7 (SDK) | UI framework | Material 3, Android target |
| `flutter_riverpod` | ^3.4.3 | State management and DI | Manual providers/Notifiers; no generator in v1 |
| `go_router` | ^18.1.1 | Navigation | Requires Flutter >= 3.44; `StatefulShellRoute.indexedStack` |
| `drift` | ^2.35.3 | Typed SQLite access | Generated row classes and DAOs |
| `drift_flutter` | ^0.3.1 | Database initialization | `driftDatabase(name: 'studyflow', native: DriftNativeOptions(shareAcrossIsolates: true))`; packages native SQLite and path resolution |
| `uuid` | ^4.6.0 | Offline-safe IDs | Text UUIDs for all primary keys |
| `intl` | **0.20.2** (pinned) | Date/duration formatting | Flutter 3.44's `flutter_localizations` pins 0.20.2; keep it exact now to avoid a future conflict if localization is added |

### Development

| Package | Version | Role |
|---|---|---|
| `drift_dev` | ^2.35.2 | Drift code generation |
| `build_runner` | ^2.15.1 (resolved 2.15.1 in the validated dependency graph) | Codegen runner. Recent versions removed `--delete-conflicting-outputs`; use `dart run build_runner build`. Commit `pubspec.lock`; pub.dev has newer releases, so re-validate before upgrading. |
| `flutter_lints` | ^6.0.0 | Lint baseline |
| `flutter_test`, `integration_test` | SDK | Unit, widget, integration tests |

### Deliberately not used in v1

- `riverpod_generator` / `riverpod_annotation` - adds generated files without enough benefit for one
  developer. Manual providers are explicit and easy to trace.
- `freezed` / `json_serializable` - Drift already generates immutable row classes; no JSON layer.
- `get_it`, `injectable` - Riverpod is the DI container.
- Chart libraries - weekly bars are a small `CustomPainter`; avoids a heavy dependency.
- Notification, calendar, cloud, analytics, and AI packages - out of scope.
- `mocktail` - repositories are tested against in-memory SQLite; a fake clock covers time.

---

## 4. System overview

```
+---------------------------- Presentation (Flutter) ----------------------------+
| Today - Goals - Schedule - Progress - Settings - Onboarding - Focus (fullscreen) |
+---------------^-----------------------------------------------^-----------------+
                | watch streams / invoke controllers            |
+---------------+---------------- Riverpod ---------------------+-----------------+
| DB provider - repository providers - stream providers - Notifiers/controllers     |
| app lifecycle listeners - current-day provider                                    |
+---------------^-----------------------------------------------^-----------------+
                |                                               |
+---------------+------------ Application services --------------+----------------+
| PlanService - ReconciliationService - SessionService - RevisionService - Progress |
+-------+-----------------------------------------------------------^---------------+
        | Drift rows / inputs                    pure PlanResult       |
+-------v-------------------------+          +-----------------------+--------------+
| Repositories & DAOs (SQLite)    |          | core/scheduling - pure Dart           |
| AppDatabase (background isolate)|          | splitter - allocator - feasibility     |
+---------------------------------+          +---------------------------------------+
                       Clock abstraction injected everywhere time is read
```

### Dependency rule

`presentation -> application -> data` and `application -> core/scheduling`. The scheduling core has **no
Flutter, Drift, Riverpod, or `DateTime.now()` dependency**. Repositories do not depend on Riverpod.
The database is the single source of truth; UI state is derived from streams and service results.

---

## 5. Architectural decisions

### ADR-1 - Local SQLite via Drift is the only source of truth

All entities and sessions live in SQLite. There is no cache layer or server. Drift provides typed
queries, migrations, transactions, and reactive streams. `drift_flutter` opens the database using the
app's databases directory and `shareAcrossIsolates` so heavy reads/writes do not block the UI isolate.

### ADR-2 - Pure, deterministic scheduling engine

`lib/core/scheduling/` contains only Dart model types and algorithms. It receives a normalized snapshot
(now, local dates, tasks, availability, locked sessions, settings) and returns sessions plus structured
warnings. It never reads the database, never calls `DateTime.now()`, and never generates random IDs.
The service layer supplies IDs and persistence. This makes every rule unit-testable and guarantees
replayable plans.

### ADR-3 - Use Drift-generated row types as application models; separate engine inputs

Drift row classes are immutable generated data classes. Duplicating them into hand-written entities
would add mapping code without improving this single-database app. Repositories expose Drift rows to
application services and UI. The scheduling engine defines its own small value types
(`EngineTask`, `AvailabilityWindow`, `LocalDate`, etc.) to remain independent; `PlanService` maps rows
to those types. Domain rules that involve persistence (remaining-time updates, history immutability)
live in services and are covered by repository tests.

**Trade-off:** UI code is coupled to Drift's generated naming. Accepted for simplicity; the database
schema is the data model.

### ADR-4 - Riverpod 3 with explicit providers, no codegen

- `Provider` for databases, repositories, services, clock.
- `StreamProvider` for reactive queries (goals, today's sessions, progress).
- `Notifier`/`AsyncNotifier` for form controllers and commands (plan rebuild, timer).
- Overrides used in tests for database and clock.
Manual providers keep the wiring visible. Provider scope is only used where needed to prevent
unnecessary rebuilds (`ref.watch(provider.select(...))`).

### ADR-5 - go_router with a stateful shell

Four top-level destinations in a `StatefulShellRoute.indexedStack`: Today, Goals, Schedule, Progress.
Settings is a route reachable from app bars. The focus timer is a full-screen route outside the shell.
This preserves scroll/state per tab and avoids rebuilding tabs during navigation.

### ADR-6 - Local wall-clock date + minute-of-day for planning

Study windows and deadlines are local calendar concepts, not instants. A session is stored as
`session_date` (`YYYY-MM-DD` local date) plus `start_minute`/`planned_minutes`, both integers. This
makes overlap and capacity arithmetic exact and avoids timezone/DST conversion bugs. Actual events
(timer start, completion) are stored as UTC epoch milliseconds for audit. Windows cannot cross midnight.

### ADR-7 - Plan runs are transactional and replace only future planned sessions

`ReconciliationService` marks eligible past sessions as missed. `PlanService.replan()` then computes a
plan and replaces only future sessions with status `scheduled` in one transaction; it does not own missed
detection. `in_progress`, `completed`, `missed`, and learner-cancelled rows are never modified by a plan.
If plan generation fails, the transaction rolls back and the previous plan remains. A single-flight lock
prevents concurrent replans.

### ADR-8 - Warnings are derived, not persisted

Feasibility results are a pure function of current inputs. They are recomputed when the plan is rebuilt
and when a task/deadline is previewed. This avoids stale warning rows and schema noise. The session rows
represent the committed plan; warnings are explanatory UI state.

### ADR-9 - Timestamp-based timer with persisted state

The timer does not count in the background. It stores `timer_accumulated_seconds` and
`timer_resumed_at_utc` on the session; elapsed time is computed from the clock. Pausing accumulates
seconds; resuming sets the timestamp; finishing writes actual minutes. UI ticking is ephemeral and
stops when the screen is not visible. No foreground service, notification permission, or exact-alarm
access is required in v1.

### ADR-10 - Local-only privacy posture

The release build should not declare `INTERNET`; Android auto-backup is disabled
(`android:allowBackup="false"`) to match the "data stays on this device" promise. No analytics SDK,
crash reporter, account, or telemetry. The app database is unencrypted; only non-sensitive study data is
stored.

---

## 6. Proposed project structure

```
StudyFlow/
+-- android/                          # Generated Android host project (applicationId edited)
+-- docs/                             # This documentation set
+-- integration_test/
|   +-- app_flow_test.dart
+-- lib/
|   +-- main.dart                     # ProviderScope, bootstrap, runApp
|   +-- app/
|   |   +-- app.dart                  # MaterialApp.router
|   |   +-- providers.dart            # App-wide providers (clock, DB, services)
|   |   +-- lifecycle.dart            # Resume/midnight hooks for reconciliation
|   |   +-- router/
|   |   |   +-- app_router.dart
|   |   |   +-- routes.dart           # Path constants and helpers
|   |   +-- theme/
|   |       +-- app_theme.dart
|   |       +-- app_tokens.dart       # Spacing, radii, semantic colors
|   +-- application/
|   |   +-- plan_service.dart         # Replan pipeline, replace-future-sessions transaction
|   |   +-- reconciliation_service.dart
|   |   +-- session_service.dart      # Start/pause/finish/manual completion
|   |   +-- revision_service.dart     # Learned-topic -> revision tasks (idempotent)
|   |   +-- progress_service.dart     # Pure aggregation queries
|   +-- core/
|   |   +-- time/
|   |   |   +-- clock.dart            # Clock, SystemClock
|   |   |   +-- local_date.dart       # LocalDate, weekday, date-only arithmetic
|   |   +-- scheduling/
|   |   |   +-- scheduling_models.dart
|   |   |   +-- session_splitter.dart
|   |   |   +-- study_scheduler.dart
|   |   |   +-- feasibility.dart
|   |   |   +-- revision_policy.dart
|   |   +-- formatting/formatters.dart # "1h 25m", dates, minute-of-day
|   |   +-- validation.dart            # Shared input validation
|   +-- data/
|   |   +-- database/
|   |   |   +-- app_database.dart
|   |   |   +-- app_database.g.dart    # Generated (committed)
|   |   |   +-- tables.dart
|   |   |   +-- daos/
|   |   |   |   +-- goal_dao.dart
|   |   |   |   +-- subject_dao.dart
|   |   |   |   +-- topic_dao.dart
|   |   |   |   +-- task_dao.dart
|   |   |   |   +-- session_dao.dart
|   |   |   |   +-- availability_dao.dart
|   |   |   |   +-- settings_dao.dart
|   |   |   +-- migrations/            # Schema export + future migrations
|   |   +-- repositories/
|   |       +-- goal_repository.dart
|   |       +-- subject_repository.dart
|   |       +-- topic_repository.dart
|   |       +-- task_repository.dart
|   |       +-- session_repository.dart
|   |       +-- availability_repository.dart
|   |       +-- settings_repository.dart
|   +-- features/
|   |   +-- onboarding/               # Availability setup + first goal
|   |   +-- today/                    # Daily dashboard, session cards
|   |   +-- goals/                    # Goal/subject/topic browse + forms
|   |   +-- tasks/                    # Task form, details, feasibility panel
|   |   +-- schedule/                 # Week/horizon view, warnings, rebuild action
|   |   +-- focus/                    # Full-screen timer, actual-minutes sheet
|   |   +-- progress/                 # Weekly bars, subject/goal summaries
|   |   +-- settings/                 # Availability, planning, revisions, appearance
|   +-- shared/
|   |   +-- widgets/                  # App scaffolds, empty/error states, duration chips
|   |   +-- extensions/
|   +-- l10n/                         # Reserved; English strings centralized now
+-- test/
|   +-- core/scheduling/              # Hardest tests: tables of scenarios
|   +-- core/time/
|   +-- data/                         # In-memory SQLite repository tests
|   +-- application/
|   +-- features/                     # Widget tests
|   +-- helpers/                      # FakeClock, test DB, builders
+-- analysis_options.yaml
+-- pubspec.yaml
```

Feature folders contain `presentation/` (screens/widgets) and `providers/` (feature-scoped Riverpod
wiring and form controllers). Cross-feature orchestration stays in `lib/application/`; shared UI in
`lib/shared/widgets/`.

---

## 7. Database schema (v1)

All primary keys are UUID v4 strings generated on-device. All timestamps are UTC epoch milliseconds.
Booleans are integers via Drift. Enum columns use Drift `textEnum` for readable values and migrations.
Foreign keys are enabled per connection.

### `goals`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `title` | TEXT NOT NULL | 1-120 chars, trimmed |
| `description` | TEXT NULL | Optional |
| `target_date` | TEXT NULL | Local ISO date `YYYY-MM-DD`; informational |
| `color_index` | INTEGER NOT NULL | Index into a fixed accessible palette |
| `status` | TEXT NOT NULL | `active`, `completed`, `archived` |
| `created_at` | INTEGER NOT NULL | UTC ms |
| `updated_at` | INTEGER NOT NULL | UTC ms |

### `subjects`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `goal_id` | TEXT NOT NULL FK -> `goals.id` RESTRICT | |
| `title` | TEXT NOT NULL | |
| `notes` | TEXT NULL | |
| `sort_order` | INTEGER NOT NULL | |
| `status` | TEXT NOT NULL | `active`, `archived` |
| `created_at`, `updated_at` | INTEGER NOT NULL | |

Index: `(goal_id, status)`.

### `topics`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `subject_id` | TEXT NOT NULL FK -> `subjects.id` RESTRICT | |
| `title` | TEXT NOT NULL | |
| `notes` | TEXT NULL | |
| `status` | TEXT NOT NULL | `not_started`, `learning`, `learned`, `archived` |
| `learned_on` | TEXT NULL | Local ISO date; set when status becomes `learned` |
| `revision_cycle_started_on` | TEXT NULL | Set once when the topic first becomes learned; gates the single revision cycle |
| `sort_order` | INTEGER NOT NULL | |
| `created_at`, `updated_at` | INTEGER NOT NULL | |

Index: `(subject_id, status)`.

### `tasks`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `topic_id` | TEXT NOT NULL FK -> `topics.id` RESTRICT | |
| `title` | TEXT NOT NULL | |
| `notes` | TEXT NULL | |
| `kind` | TEXT NOT NULL | `study`, `revision` |
| `priority` | INTEGER NOT NULL | 0 = low, 1 = normal, 2 = high |
| `estimate_minutes` | INTEGER NOT NULL | 5-2400 |
| `remaining_minutes` | INTEGER NOT NULL | 0..estimate initially; reduced only by logged actual time or manual completion |
| `deadline_date` | TEXT NULL | Local ISO date, inclusive |
| `not_before_date` | TEXT NULL | Used by revision tasks; engine never schedules earlier |
| `revision_stage` | INTEGER NULL | 0-based stage for revision tasks; NULL for study tasks |
| `status` | TEXT NOT NULL | `open`, `completed`, `cancelled`, `archived` |
| `completed_at` | INTEGER NULL | UTC ms |
| `created_at`, `updated_at` | INTEGER NOT NULL | |

Indexes: `(status, deadline_date)`, `(topic_id)`. Revision generation is gated by
`topics.revision_cycle_started_on`: it is set atomically when a topic first becomes learned (in the same
transaction as any stages generated for that learn event), even when the preset is Off, and is never
cleared by unlearning, archiving, or restoring. A
partial unique index on `(topic_id, revision_stage)` where `revision_stage IS NOT NULL` additionally
prevents duplicate stages. The unique index alone cannot enforce one cycle per topic, because re-learning
under a wider preset could otherwise add a new stage. Revision-preset changes apply only to topics
learned afterward.

### `study_sessions`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `task_id` | TEXT NOT NULL FK -> `tasks.id` RESTRICT | |
| `session_date` | TEXT NOT NULL | Local ISO date |
| `start_minute` | INTEGER NOT NULL | Minutes since local midnight, 0-1439 |
| `planned_minutes` | INTEGER NOT NULL | > 0; `start_minute + planned_minutes <= 1440` |
| `actual_minutes` | INTEGER NULL | Set on completion, >= 1 |
| `status` | TEXT NOT NULL | `scheduled`, `in_progress`, `completed`, `missed`, `cancelled` |
| `started_at_utc` | INTEGER NULL | Timer start (UTC ms) |
| `completed_at_utc` | INTEGER NULL | Completion (UTC ms) |
| `timer_accumulated_seconds` | INTEGER NOT NULL DEFAULT 0 | Paused time accumulation |
| `timer_resumed_at_utc` | INTEGER NULL | Non-null while running |
| `note` | TEXT NULL | Optional session note |
| `created_at`, `updated_at` | INTEGER NOT NULL | |

Indexes: `(session_date, start_minute)`, `(task_id, status)`. Check constraints on minute and duration.
No overlap is expressible as a simple SQLite constraint, so it is guaranteed by the scheduler and
defended in `SessionRepository` before any session insert/update.

**Session lifecycle:** `completed` and `missed` rows are never deleted or rescheduled. Replanning deletes
only future `scheduled` rows, which are ephemeral plan projections. A learner-initiated "cancel session"
marks the row `cancelled` and keeps it for audit; completing, cancelling, or archiving a task deletes that
task's future `scheduled` rows but retains past and learner-cancelled rows. No code path deletes completed
or missed rows.

### `availability_windows`

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `weekday` | INTEGER NOT NULL | 1 = Monday ... 7 = Sunday (ISO-8601) |
| `start_minute` | INTEGER NOT NULL | |
| `end_minute` | INTEGER NOT NULL | > start, <= 1440; no cross-midnight |
| `created_at`, `updated_at` | INTEGER NOT NULL | |

Validation prevents overlapping windows on the same weekday. Index: `(weekday)`.

### `app_settings` (singleton row)

| Column | Default | Notes |
|---|---|---|
| `id` | 1 | CHECK `id = 1` |
| `daily_limit_minutes` | 120 | 15-720 |
| `block_length_minutes` | 50 | 15-120; preferred maximum session size |
| `min_session_minutes` | 15 | >= 5 and <= `block_length_minutes / 2` |
| `break_minutes` | 10 | 0-30 |
| `horizon_days` | 14 | 7-30 |
| `revision_preset` | `standard` | `off`, `light`, `standard` |
| `revision_length_minutes` | 25 | 10-60 |
| `auto_replan` | 1 | Boolean |
| `theme_mode` | `system` | `system`, `light`, `dark` |
| `dynamic_color` | 1 | Android 12+ only |
| `setup_complete` | 0 | First-run availability setup |
| `last_plan_at` | NULL | UTC ms |
| `plan_stale` | 0 | Set when plan-affecting changes occur while auto-replan is off; cleared by a successful plan run |
| `created_at`, `updated_at` | NOT NULL | |

Constraints are also enforced in repositories and mirrored in the UI to give immediate feedback.

### Schema discipline

- `schemaVersion = 1` initially. No migration is needed at launch.
- After the schema is stable, export the v1 schema (`dart run drift_dev schema dump`) and use Drift's
  migration tooling plus in-memory migration tests for every subsequent change.
- Generated `.g.dart` files are committed so a clean checkout builds without codegen, while codegen is
  required whenever tables change.
- Seed only the settings singleton and availability defaults (if the learner accepts suggested hours);
  no demo content in production builds.

---

## 8. Planning pipeline

```
App start / resume / midnight / edit / manual rebuild
        |
        v
ReconciliationService -- mark past scheduled sessions as missed (except in_progress)
        |
        v
PlanService (single-flight)
  +- Load snapshot: open tasks, settings, availability, completed rows in the horizon, and locked sessions
  +- Map rows -> pure engine inputs (LocalDate, minutes)
  +- StudyScheduler.plan(inputs) -> PlannedSession[] + warnings
  +- Transaction:
  |    delete future unlocked `scheduled` sessions
  |    insert new sessions (UUIDs attached by the service)
  |    update `last_plan_at`; clear `plan_stale`
  +- Return plan summary + warnings
        |
        v
Riverpod streams emit -> Today/Schedule/Task details update
```

- Plan generation itself is pure and synchronous; for the expected data size (hundreds of tasks over
  14 days) it is well under 100 ms. If profiling ever shows otherwise, it can be moved to an isolate
  without changing the engine.
- The service-level lock serializes plan runs. Form saves debounce only rapid UI edits; a save commits
  once and then triggers one plan.
- Auto-replan failures surface an error message and leave the previous plan intact. A manual retry is
  available.
- `ReconciliationService` also handles app resume after a long pause and midnight rollover while the
  app is open. Reconciliation is idempotent.
- Archived or completed goals, archived subjects or topics, and completed, cancelled, or archived tasks
  are excluded from planning. Their future `scheduled` rows are deleted and past records remain;
  archiving or un-learning a topic also cancels its open revision tasks.
- Revision preset changes are not retroactive in v1: they apply to topics learned after the change, and
  existing revision tasks are left untouched.

### Trigger matrix

| Event | Mark missed | Replan |
|---|---|---|
| App cold start | Yes | If auto-replan enabled |
| App resume after time away | Yes | If auto-replan enabled |
| Midnight while open | Yes | If auto-replan enabled |
| Task create/edit/deadline/priority/estimate | - | If auto-replan enabled |
| Availability or planning (limit/block/min/break/horizon) settings change | - | If auto-replan enabled |
| Revision preset or length change | - | No replan; affects only future revision generation |
| Topic marked learned | - | Start a cycle if unset; generate revisions per preset; replan if auto |
| Focus session finished (partial) | - | If auto-replan enabled; otherwise mark plan stale |
| Stale timer resolved (finish or discard) | - | Completion/cancellation path; replan if auto |
| Task manually completed | - | Remove its future `scheduled` rows; replan if auto |
| Task cancelled or archived | - | Remove its future `scheduled` rows; replan if auto |
| Goal archive/complete, subject/topic archive, or topic unlearn | - | Lifecycle removals; replan if auto |
| Auto-replan off | Yes on start/resume/midnight | No automatic plan run; lifecycle removals only; manual via "Rebuild plan" |

When auto-replan is off, any event that would trigger an automatic plan run sets `plan_stale = 1` but
never moves sessions automatically. A successful plan run clears the flag. The learner can rebuild
explicitly.

---

## 9. State management design

```
Clock (SystemClock / FakeClock)
  +- clockProvider

AppDatabase
  +- databaseProvider (owns lifecycle; closes on dispose)

Repositories (Goal, Subject, Topic, Task, Session, Availability, Settings)
  +- repository providers (depend on database)

Services (PlanService, ReconciliationService, SessionService, RevisionService)
  +- service providers (depend on repositories + clock)

Read models
  +- goalsProvider            StreamProvider<List<Goal>>
  +- todaySessionsProvider    StreamProvider<List<SessionWithTask>>
  +- upcomingSessionsProvider StreamProvider<List<...>>
  +- settingsProvider         StreamProvider<AppSettings>
  +- progressProvider         StreamProvider<ProgressSnapshot> (SQL aggregation)

Commands / ephemeral state
  +- taskFormController       AsyncNotifier (validation + save)
  +- planController           AsyncNotifier<PlanSummary> (rebuild, warnings, stale flag)
  +- sessionActionController  AsyncNotifier (complete/cancel)
  +- timerController          Notifier<TimerState> (persisted timer, UI ticker)
```

- Screens `watch` read models and call controller methods. They never use the database directly.
- Forms keep local `TextEditingController` state, validate synchronously, and save through a controller.
- One `TimerController` exists for the single active session; it restores state from the session row on
  app start and uses a 1-second `Timer.periodic` only to repaint while the timer screen is visible.
- `currentDayProvider` exposes the local date and refreshes at midnight. Date-keyed streams update Today
  and Schedule.
- `AppLifecycleListener` calls reconciliation on resume. Bootstrap reconciles after the first frame so
  the UI can paint cached data immediately.

---

## 10. Navigation

```
StatefulShellRoute.indexedStack
+-- /today
+-- /goals
|   +-- /goals/:goalId
|       +-- /goals/:goalId/subjects/:subjectId
|           +-- /goals/:goalId/subjects/:subjectId/topics/:topicId
|               +-- .../tasks/new
|               +-- .../tasks/:taskId
+-- /schedule
+-- /progress

/settings                  Settings root (outside the shell, reached from app bars)
+-- /settings/availability
+-- /settings/planning
+-- /settings/revisions
+-- /settings/appearance

/focus/:sessionId          Full-screen timer (outside the shell)
/setup                     First-run availability setup (outside the shell)
```

- Path/name constants live in `routes.dart`; navigation uses `context.go`/`context.push` with named
  routes.
- The timer route confirms before leaving while running; it does not block the Android back gesture
  silently.
- No deep links or app links in v1, but go_router keeps URLs consistent if web is added later.
- Predictive back is supported by Flutter/go_router; verify on the emulator during Phase 1.

---

## 11. Focus timer design

**Data ownership:** the `study_sessions` row is the timer's persistent state. No separate timer table.

Lifecycle:

1. **Start:** session must be today's session and not completed, missed, or cancelled. Set `in_progress`,
   `started_at_utc = now`, `timer_accumulated_seconds = 0`, `timer_resumed_at_utc = now`. Enforce at
   most one `in_progress` session globally.
2. **Pause:** add `now - timer_resumed_at_utc` to accumulated; clear resumed timestamp. Persist.
3. **Resume:** set resumed timestamp. Persist.
4. **UI tick:** compute elapsed from accumulated + running delta; display countdown from
   `planned_minutes` (can go negative and show overtime if the learner keeps going).
5. **Finish:** actual minutes = rounded elapsed (minimum 1), optionally adjusted by the learner in the
   confirmation sheet. Transaction: mark session `completed`, set actual/completed timestamp, decrement
   task remaining by actual, mark task completed and cancel its future sessions if remaining reaches 0,
   then replan when auto-replan is enabled (otherwise mark the plan stale).
6. **App restart:** elapsed is derived from stored fields; if the target has passed, show a completion
   prompt. No wall-clock notification is promised in v1.
7. **Stale timer resolution:** on app start/resume, an `in_progress` session whose date is before today
   is paused and surfaced in a prominent resolution sheet: save elapsed time and finish, adjust the
   minutes, or discard the session. A timer from today restores normally (step 6). A stale timer remains
   locked in the planner until resolved, and starting another timer is blocked until then. This
   guarantees an abandoned timer always has an exit and cannot silently consume capacity forever. The app
   never auto-credits unconfirmed time.
8. **Abandon/cancel:** marks the session `cancelled` without counting time, retains the row for audit,
   and lets the next plan reschedule the task's remaining work. Marking a scheduled session missed is a
   reconcile outcome, not a timer action. Only transitions allowed by the session state machine are
   exposed.

Manual completion without a timer uses the same transaction path with actual minutes entered by the
learner. Completing, cancelling, or archiving a task - or editing its estimate in a way that would
complete it - is blocked while one of its sessions is `in_progress`; the timer must be finished or
discarded first. Session state transitions are centralized in `SessionService`; widgets never write
directly.

---

## 12. Validation, errors, and integrity

- **Input validation:** constraints live in `core/validation.dart` and are used by forms and
  repositories. Examples: title lengths, estimate range, availability window ordering/overlap,
  min session <= half the block length, deadline/earliest-date coherence.
- **Errors:** repositories throw typed exceptions (`ValidationException`, `ConflictException`);
  controllers translate them to inline field errors or snackbars. Unexpected errors show a retry
  affordance and are never swallowed.
- **Transactions:** session completion, revision generation, and plan replacement are transactional.
  The plan writes delete + insert in one transaction; a crash cannot leave a half-built day.
- **Invariant defense:** before writing any `scheduled` session, `SessionRepository` verifies no overlap
  with other non-cancelled sessions and that the task is open. This is redundant to the engine but
  protects against future manual edits or bugs.
- **Deletion policy:** foreign keys use `RESTRICT`. Deleting an empty container is allowed via explicit
  destructive confirmation; containers with history are archived. Completed/missed sessions are never
  hard-deleted by UI actions.
- **Clock changes:** reconciliation uses the current local date; if the clock moves backwards, future
  plan rows are regenerated. Timer elapsed uses timestamps; extreme clock changes may be clamped and
  surfaced if they produce implausible values.

---

## 13. Theming, accessibility, and UX architecture

- **Theme:** Material 3 `ColorScheme.fromSeed` with a deep-teal brand seed, warm neutral surfaces,
  light/dark support, optional Android 12+ dynamic color. Design tokens in `app_tokens.dart` (spacing,
  radii, semantic success/warning/priority colors that meet contrast).
- **Typography:** system font, Material 3 scale, tabular figures for timers/durations.
- **Semantics:** all icon buttons have tooltips/semantic labels; session cards expose a combined
  semantic label; timers announce start/stop/completion, not every tick; charts have textual summaries
  and excluding semantics for decorative elements.
- **Large text:** use flexible layouts, wrap durations, and avoid fixed-height rows. Widget tests render
  core screens at 200% text scale and fail on overflow.
- **Touch targets:** minimum 48x48 dp; swipe actions always have a visible alternative.
- **Reduce motion:** read `MediaQuery.disableAnimations` and skip non-essential transitions.
- **Color independence:** priority uses icon + label; status uses labels; feasibility uses icon + text.

---

## 14. Testing strategy

| Layer | Approach |
|---|---|
| Scheduling core | Pure Dart unit tests with table-driven scenarios and golden outputs (excluding IDs). Fake clock only where the engine needs a `now` snapshot. >= 90% branch coverage. |
| Date/time | Unit tests for `LocalDate`, weekday mapping, inclusive deadlines, minute-of-day formatting, DST-insensitive math. |
| Repositories/DAOs | In-memory SQLite (`NativeDatabase.memory()`) tests for CRUD, FK restrictions, unique revision stages, transactions, missed-session marking, immutability of completed rows. |
| Application services | Tests for plan replacement, partial completion, remaining-minute math, auto-replan triggers, stale-flag set/clear, single-flight behavior. |
| Widgets | Provider overrides with test DB/fake clock; form validation; Today/Schedule states; timer UI with fake clock; 200% text; semantics. |
| Integration | One end-to-end flow on Android: setup -> goal/subject/topic/task -> plan -> complete/miss -> progress. |

- Test helpers: `FakeClock`, `createTestDatabase()`, entity builders, and a `pumpApp()` wrapper with
  `ProviderScope`.
- No network mocks are required because the app has no network layer.
- Commands: `flutter analyze`, `dart format --output=none --set-exit-if-changed .`,
  `flutter test`, `flutter test integration_test` (with the emulator running).
- CI is not required to start, but a simple workflow can be added once the repo is initialized.

---

## 15. Build, codegen, and run workflow

```bash
# after project creation
flutter pub get
dart run build_runner build          # Drift codegen; no --delete-conflicting-outputs flag
flutter analyze
flutter test
flutter emulators --launch Pixel_7
flutter run -d emulator-5554
flutter build apk --debug
```

- Codegen runs after any table/DAO change. Generated files are committed.
- Android build uses the Flutter 3.44.7 template: Gradle 9.1, AGP 9.0.1, target SDK 36, min SDK 24.
  A scratch build confirmed the toolchain and native SQLite packaging work.
- `flutter doctor --android-licenses` should be completed before Phase 0 to remove the doctor warning
  (the build currently succeeds without it).
- The emulator AVD uses Android 37.1 with Play Store; USB debugging is not needed for emulator runs.

---

## 16. Performance approach

- Indexed queries for day views, task lists, and status filters; load sessions only for the visible
  horizon.
- Drift database shared across isolates; DAO streams avoid manual refresh.
- Plan generation over a 14-day horizon with hundreds of tasks is expected to be trivial; add a
  benchmark test to catch regressions.
- Avoid replanning on every keystroke; validate locally and replan after committed edits.
- Use `const` widgets, `ListView.builder`/`SliverList`, and `select` on providers to limit rebuilds.
- Progress aggregation runs in SQL where practical; charts are lightweight custom painters.
- Startup paints from local streams; reconciliation runs after the first frame, not before `runApp`.

---

## 17. Security and privacy

- No network permission in release; no telemetry/SDKs; all data local.
- Android auto-backup disabled to align with the in-app disclosure that uninstall removes data.
- Inputs are validated; SQL is parameterized by Drift.
- No secrets or API keys exist in the app.
- The database is not encrypted in v1; the product stores study plans and notes only. Encryption and
  export/backup are future work, and the UI must not claim enterprise-grade security.
- Logging avoids dumping notes; debug logs are not shipped in release.

---

## 18. Extensibility notes

- UUID primary keys make future export/sync merge-friendly without schema replacement.
- Availability windows are rows, not a packed bitmask, so per-date exceptions can be added as another
  table later.
- `not_before_date` supports revision rules and future scheduling constraints (e.g., "start after
  date").
- The scheduler's value types can gain fields without touching the UI, as long as the service mapping
  is updated.
- Notifications, backup/export, and custom revision intervals can be added behind new services without
  changing the data flow.
- Introduce Riverpod codegen only if provider boilerplate becomes a measured maintenance cost.

---

## 19. Resolved architectural decisions

Approved on 2026-10-29. These decisions are binding for v1.

1. **Application ID:** `com.studyflow.studyflow`. Applied to the Android scaffold.
2. **Repository initialization:** done; the repository and this documentation are committed.
3. **Schema scope:** weekly availability only, with no per-date exceptions; deadlines are date-only and
   inclusive through the end of the day.
4. **Deletion policy:** archive containers when history exists; hard-delete only empty containers with
   no dependent rows or history. Cancelled tasks remain in history.
5. **Auto-replan default:** enabled, with an in-app summary of moved sessions and an opt-out setting.
6. **Android auto-backup:** disabled to honor the local-only posture; uninstalling deletes data and v1
   has no export.
7. **Revision lifecycle:** one cycle per topic; re-learning does not regenerate revisions; preset
   changes apply only to newly learned topics in v1.
