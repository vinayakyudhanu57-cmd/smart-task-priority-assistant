# Smart Task Priority Assistant

A functional, explainable task prioritization and daily session planning application built with an **R backend** and an interactive, modern **HTML/CSS/vanilla JavaScript frontend**. It helps students, professionals, and teams organize tasks, calculate deterministic priorities, plan available study or work hours, and understand exactly why each task is recommended.

Its key distinguishing feature is **Explainable Task Prioritization**: every task receives a transparent priority score (0–100), an urgency tier (`Urgent`, `High`, `Medium`, `Low`, `Completed`), and a natural-language explanation of why it occupies its current ranking position.

---

## 1. Main Features

- **Full Task Lifecycle Management**: Add, view, edit, delete, and toggle completion of tasks with titles, descriptions, categories, importance levels, durations, and deadlines.
- **Explainable Priority Scoring**: Deterministic multi-factor scoring combining deadline proximity (urgency), user importance, task duration, and active progress status.
- **Smart Focus Recommendations**: Prominent next-task recommendation card displaying the top-ranked task with a clear actionable rationale.
- **Available-Time Session Planner**: Allocates active tasks into a user's available daily hours (e.g., 2.5 hours), visualizes allocation and slack, warns when workload exceeds capacity, and defers overflow tasks cleanly.
- **Search, Multi-Filtering & Sorting**: Real-time keyword search across titles and descriptions combined with filters for Status, Importance, Category, and multi-factor Sorting.
- **Reliable CSV Persistence**: Automatic read/write persistence in `data/tasks.csv` with RFC 4180 escaping for quotes, commas, and multiline descriptions.
- **Clean Executive Light Theme**: Professional sky-blue and muted navy palette with high-contrast slate text, responsive cards, and clean typography.

---

## 2. Technology Stack & R Concepts Used

- **R (>= 4.0.0)**:
  - **Data Frames & Lists**: Structured tabular representation of task attributes.
  - **Date Calculations & Formatting**: Accurate deadline arithmetic using `as.Date()` and integer day differences (`difftime`).
  - **Vectorized String Operations**: Regex sanitization and keyword matching (`grepl`, `trimws`, `gsub`).
  - **Multi-Factor Sorting**: Deterministic tie-breaking using base R `order()` across status, score, deadline, importance, duration, and ID.
  - **CSV File I/O**: Safe persistence via `read.csv()` and `write.csv()` with strict column typing.
- **Plumber & jsonlite**: Minimal HTTP REST API endpoints and unboxed JSON serialization.
- **HTML5 / CSS3 / Vanilla JavaScript**: Semantic markup, responsive card grids, accessible modals, and asynchronous client communication without bloated frontend frameworks.

---

## 3. Priority Scoring & Explanation Model

The prioritization engine is **deterministic, rule-based, and explainable** (it does not use artificial intelligence, black-box embeddings, or external APIs):

### Composite Score Formula (0 to 100 points for active tasks)
$$\text{Priority Score} = \min\big(100, \max(1, \text{Urgency} + \text{Importance} + \text{Duration} + \text{Status Bonus})\big)$$

1. **Urgency Component (0 to 50 points)**:
   - **Overdue ($D < 0$)**: $45 + \min(5, |D|)$ points (46–50 pts). Critical urgency.
   - **Due Today ($D = 0$)**: 45 points. Immediate action required.
   - **Approaching ($1 \le D \le 2$)**: $40 - (D - 1) \times 5$ points (35–40 pts).
   - **Upcoming ($3 \le D \le 7$)**: $30 - (D - 3) \times 2$ points (22–30 pts).
   - **Comfortable Runway ($8 \le D \le 14$)**: $18 - (D - 8) \times 1$ points (12–18 pts).
   - **Long-Term ($D > 14$)**: $\max(5, 12 - \lfloor(D - 14) / 7\rfloor)$ points (5–12 pts).
   - **No Deadline**: 15 points (consistent baseline pacing).

2. **Importance Component (10 to 35 points)**:
   - **High**: 35 points
   - **Medium**: 22 points
   - **Low**: 10 points

3. **Duration / Efficiency Component (6 to 15 points)**:
   - **Quick-Win ($\le 30$ mins)**: 12 points (high agility)
   - **Optimal Focus Block ($31 - 90$ mins)**: 15 points (standard high-leverage block)
   - **Substantial Effort ($91 - 180$ mins)**: 10 points
   - **Large Project ($> 180$ mins)**: 6 points (encourages progressive breakdown)

4. **Status Modifier**:
   - **In Progress**: +5 points (active momentum bonus)
   - **Completed**: Score = 0, Tier = `"Completed"` (strictly sorted after all active tasks)

5. **Deterministic Tie-Breaking**:
   When priority scores match, ties are broken deterministically:
   1. Active tasks precede Completed tasks.
   2. Priority score descending.
   3. Days remaining ascending (earliest deadline first; tasks with deadlines precede tasks without).
   4. Importance descending (High > Medium > Low).
   5. Duration ascending (shorter tasks break ties).
   6. Task ID ascending (unique identifier).

---

## 4. Available-Time Planning Logic

1. **Input**: User inputs available work or study hours $H$ (e.g. 2.5 hours = 150 minutes).
2. **Sequential Packing**: Active tasks (pre-sorted by priority score) are allocated sequentially.
3. **Capacity Invariant**: A task is allocated if and only if $\text{Cumulative Minutes} + \text{Duration} \le \text{Available Minutes}$.
4. **Deferred Queue**: Tasks that would exceed the available window are marked as deferred with the required minutes and remaining session slack.
5. **No Truncation**: Tasks are never partially cut or falsely marked as completed.

---

## 5. Folder Structure

```text
smart-task-priority-assistant/
├── .gitignore          # Ignored R session, cache, and temporary files
├── README.md           # Documentation, scoring formulas, and run guide
├── R/
│   ├── functions.R     # Core logic, date math, scoring, planning, CSV handling
│   └── main.R          # Plumber API server, CLI test runner, and demo
├── data/
│   └── tasks.csv       # Persistent CSV storage (8 sample tasks)
├── screenshots/        # Application screenshots
├── tests/
│   └── test-cases.md   # 38-point comprehensive test verification matrix
└── web/
    ├── index.html      # Responsive dashboard with next-task hero & modals
    ├── style.css       # Sky-blue, muted navy, and charcoal light theme
    └── script.js       # Vanilla JS controller and R API client
```

---

## 6. Windows Setup and Run Commands

### Prerequisites
- **R (version 4.0 or higher)** installed on Windows.
- Required R packages: `plumber` and `jsonlite`.

To install the packages, open Windows Command Prompt or PowerShell:
```powershell
Rscript -e "install.packages(c('plumber', 'jsonlite'), repos='https://cloud.r-project.org')"
```

### Starting the Web Application
Navigate to the project folder and launch the R server:
```powershell
cd C:\Users\DELL\Desktop\r_projects\smart-task-priority-assistant
Rscript R/main.R
```

Open your web browser at:
```text
http://127.0.0.1:8000
```

To stop the server, press `Ctrl + C` in your terminal.

---

## 7. Automated Testing & CLI Demo

### Running the Automated Test Suite
To run the automated verification suite covering data loading, validation, scoring boundaries, tie-breaking, recommendations, time-planning, and persistence:
```powershell
Rscript R/main.R --test
```
*(All 38 test assertions will execute and report status.)*

### Running the Interactive Terminal Demo
To preview the top recommendation, ranked tasks, and available-time allocation directly in your terminal:
```powershell
Rscript R/main.R --demo
```

---
