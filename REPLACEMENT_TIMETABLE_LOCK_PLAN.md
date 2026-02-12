# Replacement Class Timetable Lock - Feature Plan

## Goal
When a replacement class is scheduled for a specific date+time (e.g., Friday Feb 14, 8-10am), that slot must be **globally locked** – no other class (regular or replacement, any teacher, any form) can use it. Similarly, when a regular class is created, its recurring schedule locks those dates, and no replacement can overlap.

## ⚠️ Critical: Original Timetable Is Never Changed
- **Replacement class = one-time alternative session only.** It does NOT modify the original recurring schedule.
- Example: Maths class has regular schedule "Every Thursday 8-10pm". Teacher schedules a replacement for "Friday Feb 14 8-10am".
  - Original: Thursday 8-10pm → **unchanged**, still in place
  - Replacement: Friday Feb 14 8-10am → **additional** one-time slot
- We **never** update `classrooms`, `timetables`, or the regular schedule when creating/cancelling a replacement.
- Replacement data lives only in `replacement_classes` and `timeLocks` (for the specific date).

## Current State

### 1. `timeLocks` Collection (Firestore)
- **Doc ID**: `{yyyy-MM-dd}-{timeSlot}` e.g. `2025-02-14-08:00-10:00`
- **Fields**: `date`, `timeSlot`, `lockedBy`: `[{classId, teacherId, subjectName, timetableId, isReplacement?}]`
- Used for both: (a) regular class recurring locks, (b) replacement class one-time locks

### 2. create_subject.dart (New Class)
- **Conflict check**: Uses `_lockedSlots` from `classrooms` only, keyed by `form-day-timeStart-timeEnd`
- **Scope**: Conflict only within same form (Form 1 vs Form 2 can share same slot)
- **Does NOT check**: timeLocks (replacements, or regular locks from other forms)
- **On save**: Calls `_lockTimeSlotsForClass` → adds to timeLocks for each matching date in current+next month

### 3. teacher_timetable_change_page.dart (Replacement Class)
- **Conflict check**: Checks timeLocks – but only blocks if "locked by different teacher"
- **Bug**: Same teacher can double-book (e.g., Maths + Physics replacement same time) – should block
- **On save**: Adds to timeLocks for the specific date+time

---

## Target Behavior

| Scenario | Check Before Allow | Block If |
|----------|--------------------|----------|
| Create replacement (e.g., Fri Feb 14 8-10am) | timeLocks for that date+time | lockedBy has ANY entry (any class, any teacher) |
| Create new regular class (e.g., every Thu 8-10pm) | timeLocks for each Thu in current+next month | ANY of those dates already locked for that time |
| Create new regular class | classrooms (existing) | Same form+day+time already exists |

---

## Implementation Plan

### Phase 1: Replacement Class – Stricter Lock Check

**File**: `lib/screens/teacher/timetable/teacher_timetable_change_page.dart`

1. **Change conflict logic** (in `_submitReplacementClass`):
   - **Before**: Block only if `lockedByOther` (different teacher)
   - **After**: Block if `lockedBy.isNotEmpty` – slot is taken by anyone
   - Rationale: One teacher cannot teach two classes at the same time; no class can share a slot

2. **Optional UX**: Load timeLocks for selected date when user picks a date, disable/grey out already-locked time slots in the chip selector (similar to create_subject).

---

### Phase 2: Replacement Class – Show Locked Slots in UI

**File**: `lib/screens/teacher/timetable/teacher_timetable_change_page.dart`

1. When user selects a date via calendar:
   - Fetch `timeLocks` docs where doc ID starts with `{dateStr}-` (or query by date)
   - Actually: timeLocks doc ID is `{dateStr}-{timeSlot}`. We need all docs for that date. Firestore doesn't support prefix query on doc ID easily. Alternative: maintain a subcollection or use a query. Simpler: fetch all timeLocks for the month and filter by date in memory, or add a `date` field and query `where('date', isEqualTo: dateStr)`.
   - Simpler: when date is selected, for each time slot in `_timeSlots`, check if `timeLocks/{dateStr}-{timeSlot}` exists and has lockedBy. Store `_lockedSlotsForDate` = Set of locked time slot labels.
   
2. In `_buildTimeSlotSelector`:
   - Disable (grey out) choice chips for slots that are in `_lockedSlotsForDate`
   - Show "Taken by [className]" tooltip or label

3. Load locked slots when `_selectedDate` changes (in `_pickDate` or via a separate load after date pick).

---

### Phase 3: New Class Creation – Check timeLocks

**File**: `lib/screens/teacher/create_subject.dart`

1. **Before** calling `_lockTimeSlotsForClass` (or before the final save):
   - For the selected day+time, compute all dates we will lock (each matching weekday in current+next month)
   - For each such date, check timeLocks doc `{dateStr}-{timeSlot}` 
   - If ANY exists and has `lockedBy.isNotEmpty`, **block** creation
   - Show error: e.g. "This time slot conflicts with [date] – already used by [subject/class]"

2. **Keep** existing classrooms check (form-day-time) – that stays as the per-form conflict check for recurring classes.

---

### Phase 4: Align Locking Model (Optional Clarification)

- **Regular class**: Locks every matching weekday in timeLocks for current+next month (already done)
- **Replacement**: Locks the single date+time (already done)
- **Single source of truth**: timeLocks. Both flows read and write it.
- **Conflict rule**: A (date, timeSlot) can have at most one entry in `lockedBy` (or we treat any non-empty lockedBy as "slot taken").

---

## Data Flow Summary

```
CREATE REPLACEMENT (original timetable untouched):
  User selects: Date D, Time T (e.g. Fri Feb 14, 8-10am)
  → Check: timeLocks["D-T"] exists and lockedBy non-empty? → BLOCK
  → Else: Save to replacement_classes only, add lock to timeLocks["D-T"]
  → Original schedule (e.g. Thu 8-10pm) remains in classrooms/timetables unchanged

CREATE NEW CLASS:
  User selects: Day W (e.g. Thursday), Time T
  → Check 1: classrooms form+day+time (existing) → BLOCK if same form
  → Check 2: For each date D where D is weekday W in current+next month:
       timeLocks["D-T"] exists and lockedBy non-empty? → BLOCK
  → Else: Save class, add to timeLocks for each D
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `teacher_timetable_change_page.dart` | 1. Block if slot locked by anyone (not just other teacher) 2. Load locked slots when date selected 3. Disable locked time slots in UI |
| `create_subject.dart` | 1. Before save, check timeLocks for each recurring date 2. Block if any date is already locked |

---

## Verification: Original Timetable Never Modified
- Replacement creation: writes only to `replacement_classes` + `timeLocks`
- Replacement cancellation: updates only `replacement_classes` (status) + removes from `timeLocks`
- **Never** touch: `classrooms`, `timetables`, `baseSchedule`, or any regular recurring data

## Testing Checklist

- [ ] Replacement Fri Feb 14 8-10am → timeLocks has that entry; original Thu schedule unchanged
- [ ] Another replacement/course tries Fri Feb 14 8-10am → blocked
- [ ] New class "every Friday 8-10am" when Fri Feb 14 8-10 is already locked → blocked
- [ ] New class "every Thursday 8-10pm" when no Thu 8-10pm is locked → allowed
- [ ] Same teacher, two different classes, same replacement time → blocked
