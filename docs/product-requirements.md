# StudyFlow — Product Requirements Document

- **Status:** Draft v0.1 — awaiting approval
- **Date:** 2026-10-29
- **Platform:** Android (Flutter), offline-only
- **Product type:** Local-first study planner for independent learners
- **Related:** [Architecture](architecture.md) · [Scheduling rules](scheduling-rules.md) · [Roadmap](roadmap.md)

---

## 1. Summary

StudyFlow turns learning goals into a realistic daily study plan. An independent learner defines what
they want to learn (goals, subjects, topics) and the work required (tasks with estimates, deadlines,
and priorities), tells the app when they can study, and StudyFlow builds a non-overlapping schedule
that respects their capacity. When sessions are missed, the plan is repaired without deleting study
history. A built-in focus timer records actual time, and spaced revision sessions keep learned
material fresh.

The scheduling engine is deterministic, explainable, and fully on-device. There is no account, no
cloud, no AI API, no advertising, and no subscription.

---

## 2. Problem

Independent learners — self-taught developers, language learners, exam candidates, career switchers —
study from online courses, books, and tutorials without an imposed timetable. Their common failure
modes:

1. **Optimistic plans.** A course "looks like" 2 weeks of work, but available hours per week are never
   compared with the work remaining.
2. **No daily translation.** A goal such as "learn Flutter" does not say what to study tonight.
3. **Missed sessions derail the plan.** After a missed day, learners either abandon the plan or
   compress everything unrealistically.
4. **Progress is invisible.** Notes and bookmarks do not answer "am I on track?" or "what did I finish
   this week?".
5. **Learned material decays.** Without scheduled revision, completed topics are forgotten.

Existing tools are either generic task managers without capacity planning, calendar apps without
learning structure, or online platforms that require accounts and treat study plans as opaque black
boxes.

## 3. Goals and non-goals

### Goals (v1)

- Let one learner model goals, subjects, topics, and study tasks without an account.
- Generate a realistic daily schedule from that model and the learner's available study windows.
- Never schedule overlapping sessions and never exceed the learner's daily study limit.
- Explain impossible deadlines in plain language with concrete options.
- Automatically recover missed sessions while preserving completed history and unfinished work.
- Provide a focus timer that records actual study time, including across app restarts.
- Track progress against estimates and time studied.
- Schedule spaced revision sessions for learned topics.
- Deliver a polished, accessible, Android-first Material 3 experience.

### Non-goals (v1)

- User accounts, authentication, cloud sync, or multi-device use.
- Subscriptions, ads, in-app payments, or paid AI services.
- AI-generated plans or natural-language assistants. Scheduling must remain deterministic.
- Social features, leaderboards, sharing, or third-party calendar integration.
- Importing course content, PDFs, videos, or notes from external services.
- Background reminders/notifications and home-screen widgets. Deferred until after v1 (see §13).
- iOS release, web release, or tablet-specific layouts beyond a responsive phone UI.
- Data export/backup and encrypted storage. The database is local and unencrypted in v1.

---

## 4. Target users and representative journeys

**Primary persona — the self-directed learner.** Studies 30–90 minutes on weekdays and more on
weekends, uses one or two courses/books at a time, wants a clear answer to "what should I study
tonight?". Values privacy and offline use.

**Representative journeys**

- *Set up:* installs the app, sets weekday/weekend study windows and a daily cap, creates one goal and
  two subjects, adds a few topics and tasks with deadlines.
- *Plan:* generates a plan and sees sessions placed only in their free windows, with a warning if a
  deadline does not fit.
- *Study:* opens Today, starts a focus timer, pauses once, finishes the session, and sees actual time
  credited to the task.
- *Miss a day:* returns after a skipped day, sees a short "plan repaired" summary, and finds remaining
  work moved forward without losing yesterday's completed sessions.
- *Review:* marks a topic learned, receives revision sessions at increasing intervals, and views weekly
  study minutes by subject.
- *Recover from drift:* edits a deadline after realizing the plan is impossible and gets a new, honest
  schedule.

---

## 5. Product principles

1. **Deterministic, not magical.** The same inputs always produce the same plan. Every rule is
   documented and testable; the app never relies on an external model.
2. **Honest capacity.** StudyFlow never invents time. When demand exceeds availability, it says so
   clearly and offers options instead of silently overloading days.
3. **Repair, don't punish.** Missing a session is normal. Plans adapt; completed history is never
   rewritten; no streak guilt or manipulative gamification.
4. **Local and private.** All data lives in a local SQLite database. No account, network, analytics, or
   ads.
5. **Calm, focused UX.** One clear next action at a time; low-friction logging; accessible by default.
6. **Show the work.** Priorities, deadlines, and capacity are visible, so the plan feels earned rather
   than opaque.

---

## 6. Domain model and terminology

The hierarchy is strict in v1: **Goal → Subject → Topic → Task**. Each child has exactly one parent.

| Concept | Definition | Key fields |
|---|---|---|
| **Goal** | The outcome the learner is working toward. | Title, optional description, optional target date, status (active/completed/archived) |
| **Subject** | A course, book, or learning area under a goal. | Title, notes, sort order |
| **Topic** | A unit of learning inside a subject. | Title, notes, learning status (not started/learning/learned/archived), learned date |
| **Task** | A unit of study or revision work belonging to a topic. | Title, estimate, remaining minutes, optional deadline (date), priority, kind (study/revision) |
| **Session** | A scheduled block for a task on a specific day. | Date, start/end minute-of-day, planned minutes, status, actual minutes |
| **Availability** | When the learner is able to study. | Weekly windows per weekday, daily study limit, break length |
| **Plan** | The generated set of future sessions plus feasibility warnings. | Sessions, per-task allocation, warnings |

**Example:** Goal *"Become job-ready in Flutter"* → Subject *"Riverpod & state management"* → Topic
*"AsyncNotifier patterns"* → Task *"Work through the async examples"*, estimate 90 minutes, deadline
2026-11-08, priority High.

### Key task semantics

- A **task estimate** is the total work required. A **session** is a portion of it placed on the
  calendar. Tasks may span several sessions and several days.
- **Remaining minutes** decrease only when actual study time is logged or when the learner completes
  the task manually. Generating a plan does not consume remaining work.
- **Completed sessions are immutable.** Replanning only replaces future, not-yet-started sessions.
- A task's **deadline is a local calendar date** (inclusive, end of day). Time-of-day deadlines are out
  of scope for v1.
- **Priorities** are High, Normal, and Low. Normal is the default.
- Learned topics spawn **revision tasks** at configured intervals; these are ordinary tasks of kind
  `revision` with an earliest review date.

---

## 7. Functional requirements

Each requirement includes acceptance criteria that will be verified by automated tests, manual
checks on an Android emulator, or both.

### FR-1 — First-run setup without an account

On first launch, the app explains its local-only nature and asks for study availability (weekdays and
weekends) with editable suggested defaults: Mon–Fri 18:00–21:00, Sat–Sun 10:00–12:00, with a
120-minute daily limit. Setup can be skipped, but scheduling is unavailable until at least one study
window exists. No sign-up, email, profile, or network call is required.

**Acceptance:** Fresh install works in airplane mode; closing setup and returning resumes the app in a
usable state; attempting to generate a plan with no availability shows a setup prompt, not a crash.

### FR-2 — Goals

Learners can create, edit, archive, restore, and complete goals. A completed goal is read-only for
planning. Goals may have an optional target date (informational only in v1; scheduling is driven by
task deadlines). Goal colors are chosen from a fixed accessible palette.

**Acceptance:** Goal CRUD persists across restarts; archiving removes the goal’s tasks and revisions
from future plans, hides it from active lists, and keeps its history; a goal with dependent data cannot
be hard-deleted.

### FR-3 — Subjects

Learners can add subjects under a goal, edit titles/notes, reorder them, and archive them.

**Acceptance:** Subjects appear under the correct goal; deleting a subject with topics is blocked in
favor of archiving; archiving removes its tasks’ future sessions while retaining history; ordering
persists.

### FR-4 — Topics and learning status

Learners can add topics under a subject, edit notes, and set status: not started, learning, learned,
archived. Marking a topic learned records the learned date and triggers revision planning (FR-12).
Marking it un-learned or archiving it cancels future revision tasks and sessions while retaining
completed revision history; restoring an archived topic does not recreate cancelled revisions. V1
supports one revision cycle per topic: re-learning does not generate a second set of revision tasks.

**Acceptance:** Status transitions persist; learned topics show revision information; no duplicate
revision tasks are generated for the same topic and interval; archiving a topic removes its open tasks
and revisions from future plans without deleting history.

### FR-5 — Study tasks

Learners can create tasks under a topic with:

- Title (defaults to the topic title)
- Optional notes
- Estimated duration (5 minutes to 40 hours, in 5-minute steps)
- Optional deadline date
- Priority: High / Normal / Low
- Kind: study (user-created) or revision (generated)

Tasks can be edited, completed manually, cancelled, or archived. Completed and cancelled tasks remain
in history. Archiving a task removes it from future plans while retaining its history. A task's
remaining time is visible; editing its estimate recomputes remaining time as
`max(0, newEstimate − loggedActualMinutes)` for open tasks. Deadline and priority changes trigger plan
regeneration (if automatic replanning is enabled).

**Acceptance:** Invalid values are rejected with inline guidance; completed tasks are excluded from
future scheduling; changing a deadline updates the plan when automatic replanning is enabled (otherwise
the plan is marked stale); manual completion zeroes remaining time and cancels future sessions for that
task.

### FR-6 — Availability and limits

Learners define, per weekday, one or more study windows (start/end times) and a daily study limit in
minutes. They also set a preferred session block length, minimum session length, and break length
within validated ranges. Windows cannot overlap, cross midnight, or be empty. The effective daily
capacity is the smaller of the daily limit and the sum of that day's window lengths. This capacity is
an upper bound: breaks, minimum session sizes, and active/in-progress reservations can reduce the
minutes actually available for new sessions, and the schedule displays planned use honestly.

**Acceptance:** Overlapping windows are rejected with inline guidance (adjacent windows are treated as
continuous availability); the plan never starts a session outside a window; the sum of planned study
minutes on a day never exceeds the daily limit; changing availability regenerates the plan when automatic
replanning is enabled (otherwise it is marked stale until a manual rebuild).

### FR-7 — Automatic daily schedule generation

The app generates sessions for all eligible open tasks across a configurable planning horizon
(default 14 days). It respects deadlines, priorities, task order, availability, breaks, session length,
daily limits, and revision earliest dates. The plan is accessible from Today and Schedule screens,
grouped by day, and shows planned minutes versus capacity.

**Acceptance:** No two sessions overlap; no session exceeds its daily limit; sessions appear only in
available windows; the same inputs and clock produce the same plan; regeneration does not remove
completed or in-progress sessions.

### FR-8 — Today and upcoming schedule

The Today screen shows today's sessions in chronological order, the next actionable session, planned
versus completed minutes, and quick access to the focus timer or manual completion. The Schedule
screen shows the next 7 days (with an option to view the full planning horizon). Empty and fully
completed states are handled explicitly.

**Acceptance:** Today reflects database changes immediately; past sessions are not shown as actionable;
completed sessions display actual minutes; navigation to the focus timer works for today's sessions.

### FR-9 — Missed sessions and automatic recovery

When a scheduled session ends without completion, it is marked missed. When automatic replanning is
enabled, the plan is repaired on the next app launch, resume, or explicit refresh. The unfinished work is
rescheduled into future availability; future plan time was never deducted from the task's remaining
minutes. A concise change summary explains what moved. Automatic replanning can be disabled, leaving a
visible "Rebuild plan" action when the plan is stale.

**Acceptance:** A missed session is recorded as missed (history preserved) and is never shown as
upcoming; regenerated sessions do not overlap or exceed limits; completed sessions and their actual
minutes are unchanged; disabling automatic replanning still allows manual recovery.

### FR-10 — Focus timer and session logging

From today's session, learners can start a focus timer. It supports pause/resume, persists across app
backgrounding and process death using timestamps, and completes early or at the planned duration. On
finish, the learner confirms actual minutes (prefilled from the timer) and an optional note. Sessions
can also be completed without the timer by entering actual minutes. Actual minutes update the task's
remaining estimate and progress stats. If a timer is still open from an earlier day, the app surfaces a
resolution prompt on launch (finish, adjust, or discard); time is never auto-credited, and the stale
timer blocks a second timer until resolved.

**Acceptance:** Only one timer can run at a time; elapsed time remains correct after restarting the
app; a stale timer can be finished or discarded without silent time credit; finishing early reschedules
the remaining work when automatic replanning is on; manually completing a session reduces remaining
time by the entered amount; a session cannot be completed with 0 or invalid minutes.

### FR-11 — Progress tracking

Progress includes:

- Today: planned and completed minutes, sessions done.
- This week: study minutes per day, sessions completed, tasks completed, active days.
- By goal/subject/topic: actual logged minutes vs estimated study minutes, task completion, learned
  topics.
- Revision completion vs revision planned.

Charts and summaries must be readable by screen readers and must not rely on color alone.

**Acceptance:** Numbers reconcile with session history; data is deterministic from stored records; the
screen is usable with TalkBack and at 200% text scale.

### FR-12 — Revision sessions

When a topic is marked learned, StudyFlow generates revision tasks according to a preset:

- Off — no revision tasks.
- Light — 1, 3, and 7 days after learning.
- Standard (default) — 1, 3, 7, and 14 days after learning.

Each revision task uses the revision length setting (25 minutes by default, configurable 10–60). Its
target review date is an **earliest start date**: it is scheduled at the first realistic opportunity on
or after that date and has no hard deadline in v1, so a busy week or a weekend without study windows
does not produce a false "impossible deadline" warning. Revision tasks participate in normal scheduling
and daily limits. Learners can complete or cancel revisions like any task, or cancel individual
sessions; a cancelled revision is not regenerated automatically. Changing the revision preset applies to
topics learned after the change; existing revision tasks are left untouched in v1, and a topic learned
while Off does not receive revisions retroactively. Changing the revision length affects newly generated
revisions only.

**Acceptance:** Revision tasks are generated once per topic and interval; they never precede their
earliest date; un-learning or archiving a topic stops future revision sessions; completed revision
history is preserved; changing the preset does not duplicate or silently resurrect tasks for existing
topics.

### FR-13 — Deadline feasibility explanations

For every task with a deadline inside the planning horizon that cannot be fully scheduled before it, the
app must explain:

- Minutes remaining and minutes the plan can fit before the deadline.
- The deficit.
- Available capacity before the deadline (days and minutes).
- Concrete options: add a given number of minutes per day, extend the deadline, or reduce the estimate.
- When the deadline is already past, that it is overdue and how it is being handled.

Deadlines beyond the horizon produce an informational “beyond current plan” state, never an impossible
warning. Tasks whose earliest eligibility date is beyond the horizon show a deferred state.

Explanations appear in task details and as a summary banner on Schedule/Today. The app must not
silently schedule work after a hard deadline; see the scheduling rules.

**Acceptance:** An impossible in-horizon deadline always produces a structured warning with numbers; a
feasible deadline produces no warning; a far deadline is informational, not impossible; changing
availability or a deadline clears or updates the warning on the next plan (or marks the plan stale when
automatic replanning is off).

### FR-14 — History preservation and destructive actions

Completed sessions, cancelled/completed tasks, learned-topic dates, and revision history are preserved
across replans and edits. Deleting a goal/subject/topic/task with dependent history is blocked; archive
is offered instead. Destructive actions that are allowed (for empty containers, cancelling an open task)
require confirmation and explain the consequence.

**Acceptance:** After any replan, completed sessions remain byte-for-byte unchanged in status, actual
minutes, and timestamps; archived data can be restored; no orphan records exist after any operation.

### FR-15 — Settings

Settings cover availability, session/break lengths and horizon, revision preset and length, automatic
replanning, appearance (system/light/dark, dynamic color), and an about section stating local-only data
handling. A "Rebuild plan" action is always available. Revision preset changes apply to newly learned
topics, not to existing revision tasks.

**Acceptance:** Settings persist and apply immediately where safe; changing settings that affect the
plan triggers regeneration when automatic replanning is enabled (otherwise the plan is marked stale);
no network permission is required for settings.

### FR-16 — Accessibility and design quality

The app targets WCAG 2.2 AA for text contrast and non-text contrast, supports system font scaling up to
200% without clipping critical controls, provides TalkBack labels for all interactive elements, does not
convey priority or status by color alone, respects reduce-motion, and uses touch targets of at least
48×48 dp. Timer updates must not spam screen-reader announcements. The app supports edge-to-edge
Android and predictive back where supported.

**Acceptance:** Manual accessibility audit on the Pixel 7 emulator passes; widget tests catch layout
overflow at 200% text for key screens; no critical action is hover-only or color-only.

---

## 8. Scheduling contract (summary)

These are product-level promises; the exact algorithm lives in `docs/scheduling-rules.md`.

1. **No overlap.** No two planned session blocks occupy the same minute on the same day; new sessions are
   never placed inside a completed session's recorded interval. Actual timer overruns are learner-controlled
   and recorded honestly (item 9 below).
2. **Respect availability.** Sessions start and end inside a configured study window and never cross
   midnight.
3. **Respect daily limits.** Planned study minutes + active/in-progress reservations + already logged
   minutes on a day never exceed the daily limit. A learner can deliberately study overtime; that actual
   time is recorded honestly and may exceed the limit after the fact, but the planner never schedules
   beyond it.
4. **Respect work remaining.** No task receives more scheduled time than its remaining minutes.
5. **Respect deadlines.** Work is not planned after a task's deadline unless the deadline was already
   past when the plan was built (overdue best-effort). Impossible future deadlines are reported rather
   than silently violated.
6. **Deterministic ordering.** Dated tasks come before undated tasks; earliest effective deadline
   (overdue treated as due today), then higher priority, then older tasks, then a stable ID tie-breaker.
   Undated revision tasks come before undated study tasks. See the full rules.
7. **Stable history.** Completed/in-progress sessions are never modified by replanning. Missed sessions
   become history and their remaining work is rescheduled.
8. **Explainability.** Every unscheduled chunk has a reason: deadline impossible, beyond-horizon
   deadline, overdue best-effort, horizon backlog, deferred eligibility, or no availability.
9. **Overlap refers to the schedule.** Generated and retained session blocks never overlap. Actual timer
   overruns are learner-controlled and are recorded honestly rather than predicted by the planner.

**Impossible deadline copy (example):**

> **This deadline doesn't fit.** "*Async patterns*" needs **3h 10m** before Fri, Oct 31, but your plan can
> fit **1h 30m**. You need **1h 40m** more. Add about **35 min/day** to Wed–Fri (rounded up to 5 min),
> move the deadline later, or reduce the estimate by **1h 40m**.

---

## 9. UX flows

### First run

1. Branded splash → short privacy statement ("Everything stays on this device").
2. Availability setup (weekday/weekend windows, daily limit) → optional "Create your first goal".
3. Empty Today screen with one primary action: create a goal, or finish availability setup.

### Create work

Goal form → subject form → topic form → task form. Each form validates inline, preserves input on
error, and is reachable from empty states. Task creation shows an immediate feasibility preview when a
deadline is selected.

### Daily loop

Today shows: capacity header, next session card, chronological session list, and a completed section.
Tapping "Start focus" opens the timer; tapping "Done" opens the actual-minutes sheet. Completing a
session updates progress and, if work remains, the plan.

### Missing a day

On return, a dismissible summary card appears: "2 sessions were missed; 1h 15m moved to Thu and Fri."
A link opens Schedule. If capacity cannot absorb the work, the feasibility banner is shown.

### Revision

Marking a topic learned shows the revision plan inline ("Next revision: tomorrow, 25 min"). Revisions
appear in Today/Schedule like any session, tagged "Revision".

---

## 10. Design requirements

- **Visual language:** calm, focused, study-oriented. Material 3 with a deep-teal seed color and warm
  neutral surfaces; low elevation cards; generous whitespace; clear hierarchy. Light and dark themes.
- **Type:** system font, Material 3 type scale, tabular figures for timers and durations. No bundled
  font assets in v1.
- **Components:** bottom navigation (Today, Goals, Schedule, Progress) on phones; navigation rail on
  ≥600dp. Full-screen timer routes hide navigation. Large, thumb-friendly primary actions.
- **Motion:** 150–250ms standard transitions; no gratuitous animation; honor reduced motion.
- **Data display:** durations formatted as `1h 25m`; dates localized with `intl`; progress shown with
  bars plus textual values.
- **Android specifics:** Material 3, edge-to-edge, adaptive launcher icon, Android 13+ themed icon,
  predictive back, no permission requests in v1.
- **States:** loading (skeletons, not spinners where possible), empty (explanation + action), error
  (plain language + retry), offline (no special state — the app is always offline).

---

## 11. Non-functional requirements

| Area | Requirement |
|---|---|
| **Privacy / offline** | No network calls, accounts, analytics, ads, or telemetry. Release build should not require the `INTERNET` permission. All data local. |
| **Determinism** | Scheduler is pure Dart with an injected clock; identical inputs produce identical plans. |
| **Performance** | Cold start ≤ 2s on the Pixel 7 emulator; schedule rebuild ≤ 100ms for 300 tasks over 14 days; 60fps scrolling; DB queries indexed. |
| **Reliability** | All schedule mutation occurs in DB transactions; a crash or force-stop must not corrupt sessions; timer state survives process death. |
| **Data integrity** | Foreign keys enforced; no overlapping sessions by construction; completed history immutable; missed sessions retained. |
| **Testing** | ≥ 90% branch coverage on the scheduling engine; repository tests against in-memory SQLite; widget tests for core flows; one end-to-end integration test. |
| **Accessibility** | WCAG 2.2 AA contrast, 48dp targets, TalkBack, 200% text, reduce motion, no color-only status. |
| **Compatibility** | Android 7.0 (API 24) minimum, target/compile SDK 36, phone-first; landscape and ≥600dp layouts usable. |
| **Localization** | English-only UI in v1, strings centralized for later localization. |
| **Tone** | Supportive, factual, non-judgmental; no shaming language around missed sessions. |

---

## 12. Definition of done for v1

- A fresh install works in airplane mode and never asks for an account.
- A learner can create a goal hierarchy and tasks, set availability, and receive a valid plan.
- The scheduling engine satisfies every hard constraint in §8 and in `docs/scheduling-rules.md`, proven
  by automated tests.
- Impossible deadlines always produce a clear, numeric explanation.
- Missing sessions triggers recovery that preserves completed history.
- Focus timer logging and manual logging both reduce remaining work correctly and survive restart.
- Revision sessions are generated and scheduled according to the selected preset.
- Progress screens reconcile with stored session history.
- `flutter analyze` is clean; unit, widget, and integration tests pass; accessibility checks pass on the
  emulator; a debug and a release APK build successfully.

---

## 13. Deferred backlog (explicitly not v1)

- Local notifications and background focus-timer alerts (requires permissions and a foreground-service
  decision).
- Data export/import and local backup (important future work; v1 warns that uninstalling loses data).
- Per-date availability exceptions and time-off.
- Calendar integration, widgets, and Wear OS.
- Multi-device sync and accounts.
- AI assistance (e.g., estimating tasks); scheduling remains deterministic and local regardless.
- Custom revision intervals beyond presets.
- Encryption at rest.
- Study notes/journaling beyond task/topic notes.

---

## 14. Assumptions and decisions needing approval

| # | Assumption / decision | Proposed default |
|---|---|---|
| A1 | Android application ID | `com.studyflow.app` (must be confirmed before first release; painful to change later) |
| A2 | Deadlines are date-only, inclusive through 23:59 local time | Yes |
| A3 | Priority levels | High / Normal / Low |
| A4 | Availability model | Per-weekday windows + daily minute cap; no date exceptions in v1 |
| A5 | Default session block / minimum / break | 50 / 15 / 10 minutes |
| A6 | Default daily limit | 120 minutes |
| A7 | Default planning horizon | 14 days |
| A8 | Revision preset | Standard: 1, 3, 7, 14 days, 25 minutes each |
| A9 | Automatic replanning | On by default; can be disabled |
| A10 | Initialization repository | The directory is empty; `git init` is recommended before code exists |
| A11 | Focus timer notifications | Deferred; timer is accurate across restarts but does not alert in background |
| A12 | Local-only data | No backup/export in v1; uninstalling deletes data |
| A13 | Suggested first-run availability | Mon–Fri 18:00–21:00; Sat–Sun 10:00–12:00; fully editable |
| A14 | Revision lifecycle | One cycle per topic; preset changes apply only to topics learned afterward |

---

## 15. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Scheduler complexity creates edge-case bugs | High | Pure engine, exhaustive table-driven tests, documented rules, worked examples |
| Scope creep into notifications/cloud/AI | High | Explicit non-goals and deferred backlog; no new features without approval |
| Drift/schema changes after data exists | Medium | Migrations from v1; schema review before coding; in-memory migration tests |
| Android build/toolchain drift | Medium | Toolchain verified in a scratch build; Gradle/AGP pinned by Flutter template; emulator tested each phase |
| Accessibility regressions | Medium | Semantics tests, manual TalkBack checks, large-text layout tests |
| Data loss on uninstall | Medium | Clear in-app disclosure in v1; export/backup prioritized post-v1 |
| Timer accuracy across process death | Medium | Timestamp-based elapsed calculation; repository tests with fake clock |
| Ambiguous deadline behavior | Medium | Date-only deadlines; overdue policy documented; feasibility warnings |

---

## 16. Success criteria

- The app answers "what should I study today, and does my plan fit my time?" without manual arithmetic.
- Every hard scheduling promise holds under randomized and hand-written test scenarios.
- A learner who misses a day can return without re-planning by hand and without losing progress.
- The experience is fully usable offline, with TalkBack, and at large text sizes.
- No account, ads, subscriptions, cloud calls, or AI dependencies are present.
