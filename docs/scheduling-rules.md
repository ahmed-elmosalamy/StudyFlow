# StudyFlow - Scheduling Rules

- **Status:** Draft v0.1 - awaiting approval
- **Date:** 2026-10-29
- **Related:** [Product requirements](product-requirements.md) - [Architecture](architecture.md) - [Roadmap](roadmap.md)
- **Engine location:** `lib/core/scheduling/` (pure Dart)

This document is the contract for the deterministic scheduler. Implementation and tests must follow it.
When a rule changes, update this document first.

---

## 1. Guarantees

### Hard guarantees

| ID | Guarantee |
|---|---|
| **HC-1** | No two session blocks overlap on the same local date: new sessions never intersect planned, active, or in-progress blocks, and are never placed inside a completed session's recorded interval. Actual study beyond a plan is learner-controlled; the planner never creates planned overlaps and treats `max(planned, actual)` as occupied when replanning. |
| **HC-2** | Every generated session lies entirely inside one availability window on its date. No session crosses midnight. |
| **HC-3** | For each day: `logged minutes + active/in-progress reserved minutes + newly planned minutes <= daily study limit`. Deliberate learner overtime can exceed the limit after the fact; the planner never schedules beyond it. |
| **HC-4** | New planned minutes + active/in-progress committed minutes for a task never exceed that task's remaining minutes. |
| **HC-5** | No session is planned before `now` (rounded up to the next 5-minute mark; an already-aligned minute is unchanged) or before an eligibility date (`not_before_date`). |
| **HC-6** | For a task whose deadline is today or in the future, no new session is planned after the deadline date (inclusive through 23:59 local time). |
| **HC-7** | Generated sessions start at the beginning of a free slot and never before the rounded "now". Consecutive sessions within the same merged availability window are separated by at least the configured break. |
| **HC-8** | Completed and missed sessions are never modified or deleted by planning. Replanning only replaces future `scheduled` rows; learner-cancelled rows are retained but never planned. |
| **HC-9** | The same inputs (including the same injected "now") always produce the same session dates, start minutes, and durations. IDs are assigned afterward and do not affect the layout. |
| **HC-10** | A task with a future deadline inside the planning horizon either receives all its schedulable remaining time before the deadline or produces a structured feasibility warning. Unplanned work is never silently dropped. |

### What the engine deliberately does *not* do

- No randomness, scoring, machine learning, or external service.
- No automatic overtime prevention. If a learner keeps a timer running, actual time can exceed the plan.
- No time-of-day preference beyond "earliest available slot inside the user's windows."
- No cross-task optimization beyond deterministic priority order. Earlier tasks can consume capacity that a
  later task might have wanted; the feasibility report makes this visible.
- No per-date availability exceptions in v1 (weekly windows only).
- No hard deadlines are generated for revisions in v1; a learner may add one manually (see Section 10).

---

## 2. Units, dates, and time

- **Local date:** `LocalDate` (`year`, `month`, `day`) representing a calendar date on the device. Stored
  as `YYYY-MM-DD`. All scheduling uses local dates; no UTC conversion for planning.
- **Minute of day:** integer `0..1440`, where `0` is 00:00. An end minute may be `1440` (midnight at the
  end of that date); a start minute must be `< 1440`.
- **Weekday:** ISO-8601: Monday = 1 ... Sunday = 7.
- **Units:** all durations are whole minutes. All comparisons use integers to avoid floating-point drift.
- **Deadlines:** date-only and inclusive. A deadline of 2026-10-31 means work must end by 23:59 on
  October 31, local time. There are no time-of-day deadlines in v1.
- **Eligibility date:** `not_before_date` is a local date. A task cannot be scheduled earlier than it.
- **"Now":** supplied by the injected `Clock` as a local date plus minute of day. The engine never calls
  `DateTime.now()`. For today, the earliest start is `ceilTo5(nowMinute) = 5 x ceil(nowMinute / 5)`; an
  already-aligned minute is unchanged. If the result is 1440, today has no remaining planning capacity.
  Planning works at minute granularity: a session may begin at the current minute while the clock is
  partway through it. Timers record seconds separately, and learners start sessions explicitly.
- **Time zones / DST:** sessions are defined in local wall-clock terms. DST transitions do not alter
  stored dates or start minutes. Actual timer timestamps are stored in UTC. Changing the device time zone
  between plan runs can shift when a local date "happens"; v1 treats the current local date as the truth
  and replans.
- **No cross-midnight windows:** availability windows must satisfy `0 <= start < end <= 1440`. A learner
  who studies past midnight defines a separate window on the next day.

---

## 3. Inputs and outputs

### 3.1 Scheduling input snapshot

```
SchedulingInput
  today: LocalDate
  nowMinuteOfDay: int
  horizonDays: int                     // 7..30, includes today
  settings:
    dailyLimitMinutes
    blockLengthMinutes
    minSessionMinutes
    breakMinutes
  availability: List<AvailabilityWindow>  // weekday, startMinute, endMinute
  tasks: List<EngineTask>
  lockedSessions: List<LockedSession>     // completed, in-progress, active-today scheduled
```

`EngineTask`:

```
id: String                     // used only for deterministic tie-breaking
kind: study | revision
priority: 0 low | 1 normal | 2 high
remainingMinutes: int          // > 0
deadline: LocalDate?           // null for no deadline and for flexible revisions
notBefore: LocalDate?          // never schedule earlier
createdAt: UTC epoch millis
```

`LockedSession`:

```
taskId
date: LocalDate
startMinute
plannedMinutes
status: completed | inProgress | activeScheduledToday
actualMinutes?                 // required for completed
elapsedMinutes?                // optional current elapsed for in-progress
```

Repository/service mapping filters out cancelled, missed, and future `scheduled` sessions (those are
replaced) and retains active today's scheduled sessions. Every completed or in-progress row is passed as a
lock, including an in-progress session from an earlier date (a stale timer); completed rows on dates
outside the horizon may be omitted because they cannot affect future placement.

### 3.2 Plan output

```
PlanResult
  sessions: List<PlannedSession>      // date, startMinute, plannedMinutes, taskId
  allocations: List<TaskAllocation>   // taskId, newly planned minutes, reserved active minutes, unscheduled
  daySummaries: List<DaySummary>      // planned minutes, remaining capacity
  issues: List<SchedulingIssue>       // structured warnings, ordered
```

No session IDs are generated by the engine. `PlanService` assigns UUIDs and persists rows after
successful computation. Sessions are returned sorted by `(date, startMinute)`.

---

## 4. Locked time and capacity accounting

### 4.1 What is locked

A session is locked for planning if its status is one of:

1. **Completed** - on any date within the horizon.
2. **In progress** - always locked, including a stale timer whose date is before today; there is at most
   one globally.
3. **Active scheduled today** - status `scheduled`, date is today, and
   `startMinute <= nowMinute < endMinute`. The learner has not started it, but the time block has begun;
   it is kept stable rather than deleted by a replan.

Missed and cancelled sessions are history but never affect future capacity. Future `scheduled` sessions
are replaced by the plan and are not locks. `in_progress` sessions are never removed or altered by a
replan.

A stale in-progress session (date before today) consumes no future capacity because its date is past, but
it reserves the task's minutes (Section 4.4) and blocks a second timer until the learner resolves it. Resolution
is a learner action in the app: finish with confirmed actual minutes, adjust them, or discard the session
(which marks it cancelled with no time credited). A stale timer is never auto-completed or auto-marked
missed.

### 4.2 Occupied interval and break

- Completed: occupied end = `start + max(plannedMinutes, actualMinutes)` (conservative for overtime),
  clipped to the day end.
- In progress: occupied end = `start + max(plannedMinutes, elapsedMinutes ?? 0)`.
- Active scheduled: occupied end = `start + plannedMinutes`.
- A break of `breakMinutes` is reserved after each occupied interval before another session may start in
  the same availability window. Breaks are not part of the daily study-minute limit.

### 4.3 Consumption of the daily limit

| Locked status | Minutes counted against the daily limit |
|---|---|
| Completed | `actualMinutes` |
| In progress | `max(plannedMinutes, elapsedMinutes ?? 0)` |
| Active scheduled today | `plannedMinutes` |

New planned sessions add their full duration. If consumed minutes already meet or exceed the limit, the
day has no further planning capacity. Negative remaining capacity is clamped to zero.

### 4.4 Reserved task minutes

In-progress and active-scheduled sessions are commitments toward the task's remaining work, even though
remaining minutes are only reduced when time is actually logged. For allocation and feasibility:

```
reservedMinutes(task) = sum plannedMinutes of locked sessions for task
                        with status inProgress or activeScheduledToday
schedulableRemaining(task) = max(0, task.remainingMinutes - reservedMinutes(task))
```

New plan allocations may not exceed `schedulableRemaining`. Completed sessions are not reserved because
their actual time has already been deducted from remaining minutes.

---

## 5. Task ordering

Only tasks that are open, have `remainingMinutes > 0`, and belong to an active goal, subject, and topic
participate. The service filters ineligible tasks before building the engine snapshot.

### 5.1 Effective deadline

```
if deadline == null            -> null
if deadline < today            -> today        // overdue work is treated as due today
otherwise                      -> deadline
```

An overdue task is still flagged separately, but for ordering it competes with work due today rather than
automatically preempting everything.

### 5.2 Sort order (stable and total)

1. Tasks with a non-null effective deadline come before tasks with no deadline.
2. Earlier effective deadline first.
3. Higher priority first (`high > normal > low`).
4. Earlier `createdAt` first.
5. Lexicographically smaller `id` first (final tie-breaker).

For tasks **without** an effective deadline (including revisions):

1. Revision tasks before study tasks.
2. Higher priority first.
3. Earlier `createdAt` first.
4. Lexicographically smaller `id` first.

**Rationale:** This is earliest-deadline-first with explicit tie-breakers, plus a deliberate preference
for revision once its eligibility date arrives. It is explainable and deterministic. A high-priority task
with a far deadline still yields to a lower-priority task with a nearer deadline.

### 5.3 Consequences

- Allocation is **sequential**: a task earlier in the order receives capacity before later tasks. This can
  make a later task infeasible; the warning must report it. There is no fairness rotation in v1.
- A large overdue or near-deadline task can consume all available capacity. This is intentional and
  visible; the learner can split the task, change priorities, or extend deadlines.
- Revision tasks without deadlines are sorted ahead of undated study tasks but cannot be placed before
  their eligibility date.

---

## 6. Allocation algorithm

### 6.1 Day construction

For each date from `today` through `today + horizonDays - 1`:

1. Collect that weekday's availability windows. Overlapping input is rejected upstream at validation;
   adjacent windows are merged so break rules apply across the continuous block.
2. For today, clip the available time to start at `ceilTo5(nowMinute)`; discard portions before that.
3. Remove locked occupied intervals and the required breaks (Section 4).
4. Remaining free intervals are ordered by start minute.
5. `day.remainingCapacity = max(0, dailyLimit - consumedMinutes)`.

Windows separated by a gap are independent availability periods; the configured break applies between
sessions within the same merged window. The gap between windows is whatever the learner defined.

### 6.2 Task loop

`horizonEnd = today + horizonDays - 1` is the last planned date. For each task in the order from Section 5:

```
searchStartDay = max(today, task.notBefore ?? today)
if task.deadline != null and task.deadline < today:
    mode = overdue
    searchEndDay = horizonEnd
else if task.deadline != null and task.deadline <= horizonEnd:
    mode = hardDeadline
    searchEndDay = task.deadline
else if task.deadline != null:
    mode = farDeadline           // deadline > horizonEnd
    searchEndDay = horizonEnd
else:
    mode = noDeadline            // includes flexible revisions
    searchEndDay = horizonEnd

remaining = schedulableRemaining(task)
if searchStartDay > searchEndDay:
    mode = deferred              // eligible only after the horizon
    record task as deferred; continue

while remaining > 0:
    placed = false
    for day in searchStartDay..searchEndDay:
        if day.remainingCapacity <= 0: continue
        for freeInterval in day.freeIntervals (ordered):
            desired = min(blockLengthMinutes, remaining)
            available = min(freeInterval.length, day.remainingCapacity)
            size = min(desired, available)
            if size <= 0: continue

            // Do not create a new non-final fragment shorter than the minimum.
            if size < minSessionMinutes and remaining > size:
                continue

            place session at freeInterval.start, duration size
            remaining -= size
            day.remainingCapacity -= size
            shrink freeInterval: next start = start + size + breakMinutes
            (or split/remove the interval)
            placed = true
            break            // re-scan from searchStartDay for the next portion
        if placed: break
    if not placed:
        break                // record unscheduled remaining for this task
```

Notes:

- The scan restarts from `searchStartDay` after each placement. An implementation may use a cursor while
  producing identical output.
- Session begins at the start of the free interval. There is no arbitrary gap or preferred time.
- A session may be shorter than the block length when the gap or remaining work is smaller.
- A session shorter than `minSessionMinutes` is allowed **only when it completes the entire remaining
  work of the task** (e.g., final 10 minutes of a 60-minute task with a 15-minute minimum). Whole tasks
  estimated below the minimum are scheduled normally.
- If a task cannot place any further session, its remaining work becomes unscheduled and is reported.
- A far-deadline task is searched only to `horizonEnd`; its leftover work is informational, not an
  impossible deadline.
- A task whose `notBefore` is after `horizonEnd` is deferred: no sessions this run and an informational
  issue, not a backlog or deadline failure.
- Overdue and no-deadline tasks also stop at `horizonEnd`.

### 6.3 Deadline modes

| Mode | Condition | Placement behavior | Reporting |
|---|---|---|---|
| **Hard deadline** | `deadline >= today` and `deadline <= horizonEnd` | Only days up to the deadline. Never schedules after it. | If leftover: impossible-deadline issue with numbers. |
| **Far deadline** | `deadline > horizonEnd` | Only days within the horizon. | Leftover is `BeyondHorizon` information; not called impossible. |
| **Overdue** | `deadline < today` | Earliest available days through the horizon, deadline ignored for placement. | Overdue issue; work scheduled best-effort ASAP. |
| **No deadline** | `deadline == null` (includes revisions) | Through the horizon, starting no earlier than `notBefore`. | `HorizonBacklog` if work remains at horizon end. |
| **Deferred** | `notBefore > horizonEnd` | No placement this run. | Informational `DeferredBeyondHorizon`; not backlog or impossible. |

Work is **not** planned after a future hard deadline. Once that deadline passes (on a later run), the task
becomes overdue and may be scheduled best-effort. This prevents silently pretending a missed deadline was
met while still allowing recovery.

### 6.4 Termination and safety

Every iteration either places at least one minute of work or terminates the task. Total scheduled minutes
per task are bounded by `remainingMinutes`. A defensive iteration limit (e.g., `remainingMinutes + 1`) must
throw an internal error rather than loop forever if invariants are violated.

---

## 7. Feasibility warnings

Warnings are structured data; the UI owns the wording. The engine must not emit "impossible" for a task
whose deadline lies beyond the planning horizon or for a revision with no deadline.

### 7.1 Issue types

**`NoAvailability`** - no usable study windows exist across the horizon (or daily limit is zero/too small
for any session). Global; usually prompts availability setup.

**`ImpossibleDeadline`** - a task with a hard deadline inside the horizon still has unscheduled work
after allocation. Fields:

```
taskId
deadline
remainingMinutes                    // total remaining before planning
reservedActiveMinutes               // active/in-progress commitments counted toward remaining
scheduledBeforeDeadlineMinutes      // newly planned + reserved active sessions on/before deadline
deficitMinutes                      // remaining - scheduled (bounded below by 0)
availableCapacityBeforeDeadline     // capacity from now to deadline after locking, before new allocation
otherMinutesBeforeDeadline          // newly planned sessions for other tasks in that range
daysAvailableBeforeDeadline         // days from max(today, notBefore)..deadline with any capacity
suggestedExtraMinutesPerDay         // ceilTo5(ceil(deficit / daysAvailable)), or null if no days
```

**`OverdueTask`** - deadline < today and work remains (whether or not it could now be scheduled). Fields:
`taskId`, `deadline`, `remainingMinutes`, `scheduledMinutes` (new + reserved), `unscheduledMinutes`,
`daysOverdue`.

**`HorizonBacklog`** - a no-deadline task (including a revision) still has unscheduled work when the
horizon ends. Fields: `taskId`, `remainingMinutes`, `scheduledMinutes`, `unscheduledMinutes`.

**`BeyondHorizon`** - informational variant for a far deadline beyond the horizon with leftover work; it
must not be presented as an impossible deadline. Fields mirror backlog plus the deadline.

**`DeferredBeyondHorizon`** - the task is not eligible within the horizon because `notBefore` is after
`horizonEnd`. Informational only; it is neither backlog nor an impossible deadline. Fields: `taskId`,
`notBefore`, `remainingMinutes`.

### 7.2 Ordering and labels

1. Global issues (no availability) first.
2. Task issues in the task order from Section 5.
3. Issues of the same task ordered by severity: impossible deadline, overdue, backlog, deferred or other
   informational issues.

Every unplanned minute must be represented by a visible warning or informational state; no unscheduled
work is silent.

### 7.3 Explanation requirements

For an impossible deadline, the UI must state, using the structured fields:

- What is needed and by when.
- How much the plan could fit.
- The deficit.
- The number of days and capacity available before the deadline (and how much goes to other work).
- At least these options: add `suggestedExtraMinutesPerDay` minutes per day; extend the deadline; reduce
  the estimate by the deficit.

The suggested extra is an advisory lower bound rounded up to 5 minutes. If it would exceed the daily
limit or available window capacity, the UI must also suggest extending availability or the deadline.

Example copy:

> **This deadline doesn't fit.** "Async patterns" needs **3h 10m** before Fri, Oct 31. This plan fits
> **1h 30m**; you are **1h 40m** short. There are **4h** of capacity left before the deadline, and
> **2h 30m** of it goes to other tasks. Add **35 min/day**, extend the deadline, or reduce the estimate by
> **1h 40m**.

Tone: factual and supportive, never blaming the learner.

---

## 8. Missed sessions and replanning

### 8.1 Missed detection

A session is **missed** when all of the following hold:

- status is `scheduled`;
- its occupied interval has ended: for today, `startMinute + max(plannedMinutes, 0) <= nowMinute` with end
  <= 1440, or its date is before today;
- it is not in progress (no timer running).

A session whose start has passed but whose end has not is **active** on today and is retained and locked.
It becomes missed on a later run if still not completed.

When marked missed:

- The row is kept with status `missed`; `planned_minutes` remains for history; no actual time is credited.
- The task's `remaining_minutes` is unchanged (future plan time was never deducted).
- The task stays open.
- The session is excluded from future plan views.

### 8.2 Replan sequence

1. Mark eligible sessions missed (idempotent).
2. Keep `in_progress` sessions and active-today scheduled sessions.
3. Load open tasks, settings, availability, and locked sessions.
4. Compute a new plan.
5. In one transaction: remove future `scheduled` rows (active-today and in-progress rows are locks and
   are not removed); insert the new sessions; update `last_plan_at`; clear `plan_stale`.
6. Present a change summary (sessions moved, warnings).

Lifecycle removals for completed, cancelled, or archived entities (Section 9) happen before the task snapshot
is loaded and are independent of the auto-replan setting.

Steps 2-6 constitute a plan run and execute automatically only when auto-replan is enabled, or when the
learner taps "Rebuild plan". Step 1 (missed detection) runs on every reconcile regardless. When
auto-replan is off, a reconcile also applies lifecycle removals for completed/cancelled/archived entities
and marks the plan stale, but leaves all other future `scheduled` rows untouched.

Completed, missed, cancelled, and in-progress rows are never rewritten by this sequence. Cancelled rows
are retained for audit, excluded from capacity and future views, and never deleted by a plan run.

### 8.3 Triggers

- **Automatic plan runs (only when auto-replan is enabled):** app start after first frame; app resume;
  midnight rollover while open; task, topic, availability, or planning-setting changes; partial session
  completion; task completion, cancellation, or archiving after that task's future rows are removed.
- **Always on reconcile, independent of the setting:** missed detection; lifecycle removal of future
  `scheduled` rows for completed/cancelled/archived tasks and topics; stale-plan marking; stale-timer
  prompt.
- **Always available:** "Rebuild plan", which runs the full sequence on demand.

If auto-replan is disabled, the UI shows that the plan is stale and offers a rebuild. No sessions are
moved or newly planned automatically; only rows belonging to completed, cancelled, or archived work are
removed, and the learner decides when to rebuild.

Resolving a stale in-progress timer (finish, adjust, or discard) follows the normal completion or
cancellation paths above and then the usual auto/manual replan policy.

### 8.4 Completed work is permanent

- Completing a session writes actual minutes and completion timestamps; those fields are never changed by
  later planning.
- If completing a session leaves work remaining, the remainder is planned later when auto-replan is
  enabled, or on the next rebuild.
- If completion brings remaining to zero, the task is completed and its future sessions are cancelled.
- A missed session stays in history even after its work is successfully completed via later sessions.

### 8.5 Clock changes

Plans are snapshots. If the device clock jumps forward, past-due sessions become missed on the next
reconcile. If it jumps backward, already missed/completed records are **not** unmarked; future planning
uses the new "now". History is not rewritten. Timer elapsed values that become implausible (e.g.,
negative) are clamped and logged in debug builds.

---

## 9. Task lifecycle effects on scheduling

- **Log actual minutes on a session:** reduce task `remaining_minutes` by actual minutes, clamped at zero.
  If zero, complete the task and cancel its future scheduled sessions. If remainder > 0, replan when
  auto-replan is enabled; otherwise mark the plan stale.
- **Manual task completion:** set status `completed`, remaining 0, completed timestamp; cancel future
  scheduled sessions; preserve all past sessions. Does not invent actual study minutes. Replan other work
  when auto-replan is enabled.
- **Cancel task:** status `cancelled`; remove future scheduled sessions; retain history; exclude from
  planning. Replan other work when auto-replan is enabled.
- **Archive task:** status `archived`; remove future scheduled sessions; retain history; exclude from
  planning. Replan other work when auto-replan is enabled. An archived revision is not regenerated.
- **Archive topic:** dependent study and revision tasks become ineligible; open revision tasks are
  cancelled; future scheduled sessions are removed; history is retained. Replan when auto-replan is
  enabled.
- **Unlearn topic:** cancel its open revision tasks and their future sessions; completed revision history
  remains. Replan when auto-replan is enabled.
- **Archive/complete goal or archive subject:** dependent tasks, including revisions, become ineligible;
  future scheduled sessions are removed; past history remains. Replan when auto-replan is enabled.
- **Edit estimate:** for an open task, recompute
  `remaining = max(0, newEstimate - totalLoggedActualMinutes)`. If the result is 0, complete the task and
  cancel future sessions (notify the learner). If > 0, replan when auto-replan is enabled; otherwise mark
  the plan stale.
- **Edit deadline/priority:** replan when auto-replan is enabled; otherwise mark the plan stale. Moving a
  deadline into the past makes the task overdue on the next plan. Moving it beyond the horizon changes
  the warning to informational.
- **Cancel a scheduled session:** status `cancelled`; retain the row for audit; exclude it from capacity
  and future views. The task keeps its remaining work and may be rescheduled by the next replan unless the
  task itself is cancelled/completed. Cancelling a revision session does not regenerate it.
- **One active timer:** at most one session may be `in_progress` globally. Starting a second is rejected.
  A stale in-progress session from an earlier date blocks a new timer and reserves its task's minutes
  until the learner finishes, adjusts, or discards it.
- **While a timer runs:** completing, cancelling, or archiving its task - or editing its estimate in a way
  that would complete the task - is blocked until the in-progress session is finished or discarded, so
  actual time cannot be double-counted or orphaned.

When auto-replan is off, any lifecycle event that would have triggered a plan run sets the persisted
stale flag instead; the UI offers "Rebuild plan".

---

## 10. Revision rules

### 10.1 Presets

| Preset | Review dates after the learned date | Sessions per review |
|---|---|---|
| Off | None | - |
| Light | +1, +3, +7 days | 25 min each |
| Standard (default) | +1, +3, +7, +14 days | 25 min each |

The learned date is the local date on which the topic is marked learned. Review dates are calendar-day
offsets; they do not skip weekends. Each revision uses `revisionLengthMinutes` (25 minutes by default,
configurable 10-60).

### 10.2 Generated tasks

For each review date, create one task:

- `kind = revision`
- `title = "Revise: <topic title>"`
- `revision_stage` = 0-based stage index for the preset; the UI labels stages from 1
- `estimate_minutes = revisionLengthMinutes`
- `not_before_date = review date`
- `deadline_date = null` (revisions are flexible in v1 and never produce an impossible-deadline warning)
- `priority = normal`
- `status = open`

Revision tasks are normal scheduled work: they respect availability, breaks, daily limits, and ordering.
Because they have no deadline, they sort in the undated group with revisions ahead of study tasks. The
review date is shown in the UI as "Review from <date>"; because the task has no deadline, it may be
scheduled on the first available slot on or after that date. This avoids false deadline failures when a
review date falls on a weekend or a full day.

### 10.3 Idempotency and lifecycle

- Generated at most once per topic: `topics.revision_cycle_started_on` is set atomically when a topic
  first becomes learned, in the same transaction as any stages generated for that learn event, even when
  the preset is Off; it survives unlearn/archive. A unique partial index on
  `(topic_id, revision_stage)` additionally prevents duplicate stages.
- Marking an already-learned topic learned again does not generate duplicates (v1 supports one revision
  cycle per topic).
- Unlearning or archiving a topic cancels its open revision tasks and their future scheduled sessions.
  Completed revision sessions remain in history. Restoring an archived topic does not recreate revisions
  that were cancelled by the archive.
- Changing the preset applies only to topics learned after the change. Existing revision tasks are not
  created, cancelled, or regenerated by the change; **Off** stops future generation but does not cancel
  existing revisions. Their future sessions may still move on the next normal replan like any other
  scheduled work. The learner can cancel individual revision tasks or sessions manually.
- A topic learned while the preset is Off receives no revision cycle; enabling a preset later does not
  generate one retroactively.
- Changing `revisionLengthMinutes` affects newly generated revisions only; existing revision tasks keep
  their estimate and may be edited individually.
- Completing or cancelling a revision does not spawn a replacement; revisions are generated only when a
  topic is marked learned.
- Editing a revision's estimate, deadline, or priority is allowed like any task; the engine treats it
  accordingly. Changing the estimate does not create a new stage.

---

## 11. Determinism and idempotence

Guaranteed by:

- No randomness, `DateTime.now()`, locale-dependent comparisons, or unordered iteration. All collections
  are explicitly sorted before allocation.
- Integer minute arithmetic only.
- Task ordering is total (Section 5); availability windows are sorted by `(weekday, startMinute)`.
- Engine output excludes generated IDs; session UUIDs are assigned in the service layer and never feed
  back into layout.
- The engine accepts the clock snapshot explicitly.
- Re-running the engine with the same snapshot produces exactly the same sessions. Replanning twice with
  the same database state produces the same slot layout (row IDs may differ because replaced rows get new
  UUIDs).

**Versioning:** the scheduling algorithm is versioned with the app. If a future version changes rules,
plans may change after update; this is expected and must be noted in release notes. Warnings are derived,
so no stale warning rows exist.

---

## 12. Validation rules

Inputs that violate these are rejected before the engine (UI + repository); the engine also asserts them.

### Settings

| Setting | Range / rule |
|---|---|
| `dailyLimitMinutes` | 15-720 |
| `blockLengthMinutes` | 15-120 |
| `minSessionMinutes` | 5 ... `floor(blockLengthMinutes / 2)` |
| `breakMinutes` | 0-30 |
| `horizonDays` | 7-30 |
| `revisionLengthMinutes` | 10-60 |

The `minSession <= block / 2` rule guarantees that splitting a task into block-sized pieces cannot force
non-final fragments below the minimum.

### Availability

- `weekday` 1-7.
- `0 <= startMinute < endMinute <= 1440`.
- Windows on the same weekday must not overlap; overlapping input is rejected (adjacent windows are
  merged by the engine).
- At least one window is required to generate useful sessions; otherwise `NoAvailability` is returned.

### Tasks

- `estimateMinutes` 5-2400 (in 5-minute steps at the UI level).
- `remainingMinutes` 0..estimate (0 means no scheduling; service normally completes such tasks).
- `priority` in {0, 1, 2}.
- `notBefore <= deadline` when both are present.
- Revision stage >= 0; unique per topic.
- A task's `notBefore` beyond the horizon is allowed; it receives no sessions this run and is reported as
  deferred, not as backlog.

### Sessions / locks

- `startMinute + plannedMinutes <= 1440`.
- `actualMinutes` >= 1 when status is completed and <= 1440.
- At most one `in_progress` session globally.
- Locked data must belong to open tasks except for historical completed/missed records.

---

## 13. Worked examples

Assumptions for all examples: weekend has no windows; block 50, minimum 15, break 10, daily limit 120.

### Example A - feasible plan with gap filling

**Now:** Thursday 2026-10-29, 17:00. **Windows:** Thursday and Friday 18:00-21:00.

**Tasks**

| Task | Due | Priority | Remaining |
|---|---|---|---|
| A | Fri 2026-10-30 | High | 120 |
| B | - | Normal | 60 |

**Sorting:** A (hard deadline) before B (no deadline).

**A allocation (Thursday):** 18:00-18:50, 19:00-19:50, 20:00-20:20 (total 120; daily limit reached).
**B allocation (Friday):** 18:00-18:50, 19:00-19:10 (final 10-minute remainder is allowed to be short;
total 60).

No overlaps; breaks respected; neither day exceeds 120 minutes.

### Example B - impossible deadline

Same windows. **Task A:** due Friday, remaining 300. Thursday capacity 120, Friday capacity 120.

- Planned before deadline: 240 (Thu 120 + Fri 120), deficit 60.
- Structural result: `ImpossibleDeadline`, 300 needed, 240 scheduled, 60 short, 2 days available,
  suggested 30 extra minutes/day.
- No sessions are planned after Friday for A. A remains open with 60 minutes unscheduled until the
  learner extends the deadline (then it becomes overdue and is scheduled best-effort) or reduces the
  estimate.
- If another task C existed after A in the sort order, A would consume the available capacity first and C
  could also become infeasible. This is visible in C's own warning.

### Example C - missed sessions

Same as Example A on Thursday. The learner completes only the 18:00 session (actual 50) and misses the
other two. On Friday at 10:00, before any replan, only 70 minutes remain.

1. Thursday 19:00 and 20:00 sessions are marked missed and retained.
2. The completed 18:00 session keeps actual 50 and its history.
3. Replan: A (70 minutes left) gets Friday 18:00-18:50 and 19:00-19:20, using 70 of Friday's 120
   available minutes.
4. B can then receive 50 of its 60 minutes (Friday 19:30-20:20), bringing the day to the 120-minute
   limit; its final 10 minutes are a horizon backlog.
5. No missed or completed row is altered.

### Example D - revision generation and placement

Topic learned Thursday 2026-10-29 with the Standard preset (+1, +3, +7, +14 days):

| Stage | Earliest review | Scheduled? |
|---|---|---|
| 1 | Fri 2026-10-30 | Friday at the first eligible free slot (subject to other work) |
| 2 | Sun 2026-11-01 | First eligible window after that date (Monday, since weekends have none) |
| 3 | Thu 2026-11-05 | On/after Nov 5 |
| 4 | Thu 2026-11-12 | On/after Nov 12 (may be beyond a 14-day horizon depending on today) |

Revision tasks are generated without a deadline, so no impossible-deadline warning is generated if a
review date falls on a day with no availability. If the horizon ends before a review date, the task is
reported as deferred rather than backlog.

---

## 14. Edge cases

| Situation | Expected behavior |
|---|---|
| No availability windows | `NoAvailability`; no sessions; UI prompts setup. |
| Daily limit smaller than min session | No sessions can be placed; warning/guidance to adjust settings. |
| Windows all shorter than min session | No sessions; no-availability or backlog warnings. |
| Availability windows overlap | Rejected at validation; adjacent windows merged by the engine. |
| Task estimate below minimum | Whole task is scheduled as one short session. |
| Final task remainder below minimum | Allowed as a final short session. |
| Task `remaining == 0` | Ineligible; service normally marks it complete. |
| Deadline today, window already past | No sessions; impossible deadline with zero days available. |
| Deadline changed to a past date | Next run treats it as overdue and schedules ASAP. |
| Overdue task with huge remaining | Consumes capacity first by effective-today ordering; warning remains until complete. |
| Deadline beyond horizon | Sessions within horizon; leftover is informational, not impossible. |
| Auto-replan disabled | Missed sessions are still marked on resume; lifecycle removals still apply; plan marked stale; manual rebuild available. |
| Timer running while replanning | In-progress session stays locked; its task's remaining is reserved; other work is planned around it. |
| Stale in-progress timer (earlier date) | Remains locked and reserves task minutes; consumes no future capacity; blocks a new timer until the learner finishes, adjusts, or discards it; never auto-completed or auto-missed. |
| Completed session ran past plan | Occupied interval uses max(planned, actual) to avoid overlap; cap counts actual. |
| Clock moved backward | No history is un-marked; future sessions regenerate from the new now. |
| Clock moved forward | Ended scheduled sessions become missed; plan repairs. |
| Two sessions would touch at a window edge | Break rule applies within merged windows; windows are separate availability periods. |
| Revision preset turned off | No new cycles are generated; existing revision tasks remain unless cancelled manually; completed revisions remain. |
| Revision preset changed | Existing revision tasks are untouched; the new preset applies only to topics learned afterward. |
| Topic unlearned | Open revision tasks/sessions cancelled; completed revisions remain. |
| Topic archived | Its tasks become ineligible; open revisions cancelled; future sessions removed; history retained. Restoring the topic does not recreate the cancelled revisions. |
| Task archived | Excluded from planning; future sessions removed; history retained. |
| Task `notBefore` beyond horizon | No sessions this run; `DeferredBeyondHorizon` information, not backlog. |
| Learner changes estimate below logged time | Remaining becomes 0; task completes; future sessions cancelled (learner notified). |
| Task manually completed | Remaining 0; future sessions cancelled; prior actual history remains. |
| Session cancelled by learner | Row marked `cancelled` and retained; excluded from capacity; work remains and may be rescheduled on next replan; a cancelled revision is not regenerated. |
| Task completed/cancelled/archived while timer runs | Blocked until the in-progress session is finished or discarded. |

---

## 15. Test matrix

The engine test suite must cover at least:

### Deterministic golden scenarios

1. Empty task list and no windows.
2. Single task, single window, fits exactly.
3. Session split by block length and gap filling.
4. Minimum-session guard and final short remainder.
5. Daily limit reached mid-task; continuation on the next day.
6. Completed minutes already consume part of today's limit.
7. In-progress session locks a slot and reserves task minutes.
8. Active-today session is retained and not double-planned.
9. Break enforcement within a window.
10. No overlap across sessions from different tasks.
11. Hard deadline exactly fits / one minute short.
12. Impossible deadline: partial allocation, no post-deadline sessions, correct warning fields.
13. Overdue task: scheduled ASAP, warning numbers.
14. Deadline beyond horizon: informational, not impossible.
15. No-deadline backlog at horizon end.
16. `notBefore` blocks early placement and shifts to the next eligible day.
17. Revision tasks sort ahead of undated study tasks but not before eligible dates.
18. Multiple tasks with identical deadlines/priorities sorted by `createdAt` then `id`.
19. Task ordering by priority within the same deadline.
20. Adjacent availability windows merge; overlapping input is rejected upstream.
21. Windows on different weekdays only place sessions on those weekdays.
22. Horizon boundaries: today included, last day included, day after excluded.
23. Rounding of "now" to the next 5-minute boundary, including near midnight.
24. Deadline today with remaining capacity and an active session.
25. In-progress session with elapsed > planned.
26. Task with `notBefore` after the horizon: no sessions, `DeferredBeyondHorizon`, no backlog.
27. Stale in-progress session from a previous date: remains locked, reserves task minutes, consumes no
    future capacity.
28. Completed session with actual > planned occupies the longer interval when replanning.
29. Suggested extra minutes rounded up to 5 (`ceilTo5`).
30. `ceilTo5` leaves an already-aligned now unchanged.

### Property-style tests (deterministic seeds in tests)

For generated valid snapshots, assert:

- no overlaps, including against completed occupied intervals;
- every session inside a window and within the day;
- daily limit respected;
- per-task allocation (new + reserved) <= remaining;
- no hard-deadline violations;
- no session before `notBefore` or before the rounded now;
- sessions >= min unless they are the final task remainder;
- identical replay produces identical session slots;
- warning coverage: for every task, scheduled + unscheduled = schedulable remaining (within rounding
  rules), and every unscheduled portion has an issue.

### Idempotence and persistence tests (service/repository level)

- Replan twice -> same slot layout; completed/missed/in-progress rows unchanged.
- Missed marking is idempotent.
- Completed actual updates remaining exactly once.
- Revision generation is idempotent and unique.
- A failed plan transaction leaves the previous plan intact.
- Cancelled session rows are retained, excluded from capacity, and never deleted or rewritten by a replan.
- Archived tasks/topics are excluded; their future rows are removed and past history is intact.
- Auto-replan off: missed marking and lifecycle removals occur, other future rows are unchanged, and the
  plan is marked stale; an explicit rebuild replaces the plan.
- A revision preset change leaves existing revision tasks untouched and generates no new stages for
  existing cycles.
- Re-learning or restoring a topic does not regenerate cancelled revision tasks.
- Stale timer resolution: finishing credits confirmed minutes once; discarding marks the session cancelled
  with no time credited.
- Task completion/cancellation/archival is rejected while any of its sessions is `in_progress`.

---

## 16. Open decisions specific to scheduling

1. Revision tasks have no hard deadline in v1 (recommended to avoid false warnings). Confirm.
2. Overdue work competes as "due today" rather than always first. Confirm.
3. Sequential priority allocation (no fairness rotation) is accepted; warnings expose starvation.
4. Breaks apply within a merged availability window; separate windows are treated as independent
   availability periods. Confirm.
5. A final fragment below the minimum is allowed to finish a task.
6. Auto-replan defaults to on, with a summary of moved sessions.
