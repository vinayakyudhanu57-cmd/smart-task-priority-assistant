# Smart Task Priority Assistant — Test Specification & Verification Matrix

This document defines the comprehensive manual and automated test cases covering deterministic priority scoring, explainable rationale generation, available-time session allocation, search and multi-filtering, CRUD workflows, and CSV persistence.

Automated invariants can be verified directly via:
```powershell
Rscript R/main.R --test
```

---

## 1. Test Execution Summary

| Test Category | Invariants Checked | Execution Status | Verification Method |
| :--- | :---: | :---: | :--- |
| **Data Persistence & CSV Schema** | 3 | **Passed** | Automated in `R/main.R` & CSV inspection |
| **Input Validation Rules** | 5 | **Passed** | Automated in `R/main.R` & Web Form UI |
| **Priority Scoring Boundaries** | 6 | **Passed** | Automated in `R/main.R` |
| **Importance Tiers (High/Med/Low)** | 3 | **Passed** | Automated in `R/main.R` |
| **Deterministic Tie-Breaking** | 3 | **Passed** | Automated in `R/main.R` |
| **Smart Next-Task Recommendations** | 4 | **Passed** | Automated in `R/main.R` & Hero Card UI |
| **Available-Time Planning & Overflow** | 5 | **Passed** | Automated in `R/main.R` & Session Planner UI |
| **Keyword Search & Multi-Filters** | 4 | **Passed** | Automated in `R/main.R` & Toolbar controls |
| **CRUD Operations & Restart Persistence** | 5 | **Passed** | Automated on temporary CSV & Live API |
| **Total Test Invariants** | **38** | **All Passed (38/38)** | Verified against R 4.6.1 runtime |

---

## 2. Detailed Test Cases

### TC-01: CSV Data Loading and Schema Preservation
- **Description**: Verify `load_tasks()` loads existing records from `data/tasks.csv` without data loss and guarantees all required columns exist.
- **Input**: `data/tasks.csv` containing 8 initial tasks.
- **Expected Outcome**: Loaded data frame contains 8 rows and all 10 columns (`id`, `title`, `description`, `category`, `deadline`, `importance`, `duration_mins`, `status`, `created_at`, `updated_at`).
- **Result**: **PASS** (Automated assertion).

### TC-02: Input Validation and Boundary Enforcement
- **Description**: Verify validation rejects blank titles, invalid importance levels, negative/zero durations, durations $> 24$ hours, and malformed dates.
- **Test Scenarios**:
  1. Empty title `""` &rarr; Rejected with `"Task title is required and cannot be blank."`
  2. Importance `"Critical"` &rarr; Rejected with allowed importance enum error (`High, Medium, Low`).
  3. Duration `0` or negative &rarr; Rejected with positive duration requirement.
  4. Date `"14/10/2026"` &rarr; Rejected with format requirement `YYYY-MM-DD`.
  5. Valid record &rarr; Returns `valid = TRUE`.
- **Result**: **PASS** (Automated assertions).

### TC-03: Overdue Task Priority Calculation
- **Description**: Verify tasks with deadlines past the reference date receive maximum urgency points and the Urgent tier.
- **Input**: Task with deadline `2026-10-12` evaluated at reference date `2026-10-14` (2 days overdue).
- **Expected Outcome**: Priority score $\ge 80$, tier `"Urgent"`, `is_overdue = TRUE`, and explanation explicitly notes `"Overdue by 2 days"`.
- **Result**: **PASS** (Automated assertion: score = 100/100, Urgent).

### TC-04: Approaching and Due-Today Deadlines
- **Description**: Verify tasks due today receive 45 urgency points, while tasks due in 1–2 days receive 35–40 urgency points.
- **Input**: Deadline matching `ref_date` (`2026-10-14`).
- **Expected Outcome**: `deadline_status = "Due Today"`, `urgency_score = 45`.
- **Result**: **PASS** (Automated assertion).

### TC-05: Tasks Without Deadlines
- **Description**: Verify tasks without deadlines receive a consistent baseline urgency (15 points) rather than an error or arbitrary zero.
- **Input**: Task with `deadline = ""`.
- **Expected Outcome**: `deadline_status = "No Deadline"`, `urgency_score = 15`, explanation includes `"No fixed deadline assigned (15/50 baseline pacing)"`.
- **Result**: **PASS** (Automated assertion).

### TC-06: Completed Task Exclusion from Active Ranking
- **Description**: Verify completed tasks receive score 0 and tier `"Completed"`, and are strictly sorted after all active tasks.
- **Input**: Task with `status = "Completed"`.
- **Expected Outcome**: Placed at the bottom of ranked tasks list, excluded from the top recommendation.
- **Result**: **PASS** (Automated assertions).

### TC-07: Importance Tier Ordering for Identical Deadlines
- **Description**: Verify High importance outranks Medium, and Medium outranks Low when deadlines and durations are identical.
- **Input**: Three tasks with deadline `2026-10-20` and duration 60 mins.
- **Expected Outcome**: $\text{Score}_{\text{High}} > \text{Score}_{\text{Medium}} > \text{Score}_{\text{Low}}$.
- **Result**: **PASS** (Automated assertion).

### TC-08: Deterministic Tie-Breaking
- **Description**: Verify that when two tasks have identical priority scores, tie-breaking strictly follows:
  1. Days remaining ascending (closer deadline first)
  2. Importance descending (High > Medium > Low)
  3. Duration ascending (shorter tasks break ties)
  4. Task ID ascending
- **Expected Outcome**: Same tasks in identical order across multiple executions.
- **Result**: **PASS** (Automated assertion).

### TC-09: Available-Time Planning and Session Overload
- **Description**: Verify that `plan_available_time()` allocates tasks sequentially without exceeding available session hours, and identifies overflow.
- **Test Scenarios**:
  1. Session 1.5 hours (90 mins): Allocates tasks $\le 90$ mins, correctly marks deferred tasks, reports overflow minutes.
  2. Session 20.0 hours (1200 mins): Allocates all active tasks, reports 0 overflow and positive unused buffer.
- **Result**: **PASS** (Automated assertions).

### TC-10: Case-Insensitive Search & Multi-Filter Combinations
- **Description**: Verify keyword search matches words in titles and descriptions regardless of letter case, and works alongside status/importance filters.
- **Input**: Query `"security"`, Filter `status = "Pending"`, `importance = "High"`.
- **Expected Outcome**: Accurate subsets returned; non-matching queries return an empty data frame without crashing.
- **Result**: **PASS** (Automated assertions).

### TC-11: Special Characters, Quotes, and Restart Persistence
- **Description**: Verify adding, updating, toggling, and deleting tasks preserves quotes (`"quotes"`), commas, and newlines in CSV storage across application restarts.
- **Verification**: Created test item with quotes and commas in temporary CSV, retrieved and verified exact string equality, toggled status, confirmed deletion.
- **Result**: **PASS** (Automated assertions).
