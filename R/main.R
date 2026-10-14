# ==============================================================================
# Smart Task Priority Assistant - Main Server & CLI Verification Entrypoint
# R/main.R
# ==============================================================================

# Determine project root and source functions
script_dir <- tryCatch({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    dirname(normalizePath(sub("^--file=", "", file_arg[1])))
  } else {
    getwd()
  }
}, error = function(e) getwd())

project_root <- if (basename(script_dir) == "R") dirname(script_dir) else getwd()
setwd(project_root)

source(file.path(project_root, "R", "functions.R"))

DATA_FILE <- file.path(project_root, "data", "tasks.csv")
WEB_DIR <- file.path(project_root, "web")

# ------------------------------------------------------------------------------
# Automated Test Suite (--test)
# ------------------------------------------------------------------------------
run_tests <- function() {
  cat("\n==========================================================\n")
  cat("  Smart Task Priority Assistant - Test Suite Execution    \n")
  cat("==========================================================\n\n")
  
  passed <- 0
  failed <- 0
  
  assert <- function(condition, test_name) {
    if (condition) {
      cat(sprintf("  [PASS] %s\n", test_name))
      passed <<- passed + 1
    } else {
      cat(sprintf("  [FAIL] %s\n", test_name))
      failed <<- failed + 1
    }
  }
  
  ref_date <- as.Date("2026-10-14")
  
  # 1. Data Loading & Schema
  cat("--- 1. Data Loading & Persistence ---\n")
  df <- load_tasks(DATA_FILE)
  assert(nrow(df) >= 8, "Sample CSV loads at least 8 initial tasks")
  assert(all(TASK_COLUMNS %in% colnames(df)), "All required columns exist in loaded data frame")
  
  # 2. Validation Rules
  cat("\n--- 2. Validation Rules ---\n")
  v_empty <- validate_task(list(title = "", category = "Engineering"))
  assert(!v_empty$valid, "Empty title is rejected")
  
  v_bad_imp <- validate_task(list(title = "Task", category = "Work", importance = "Critical", duration_mins = 30))
  assert(!v_bad_imp$valid, "Invalid importance tier is rejected")
  
  v_bad_dur <- validate_task(list(title = "Task", category = "Work", importance = "High", duration_mins = 0))
  assert(!v_bad_dur$valid, "Zero or negative duration is rejected")
  
  v_bad_date <- validate_task(list(title = "Task", category = "Work", importance = "High", duration_mins = 60, deadline = "14/10/2026"))
  assert(!v_bad_date$valid, "Non-standard date format is rejected")
  
  v_good <- validate_task(list(title = "Valid Task", category = "Engineering", importance = "High", duration_mins = 45, deadline = "2026-10-20"))
  assert(v_good$valid, "Valid task passes validation")
  
  # 3. Explainable Priority Scoring
  cat("\n--- 3. Priority Scoring & Deadline Boundaries ---\n")
  # Overdue task
  t_overdue <- list(title = "Overdue", category = "A", deadline = "2026-10-12", importance = "High", duration_mins = 60, status = "Pending")
  p_overdue <- calculate_task_priority(t_overdue, ref_date = ref_date)
  assert(p_overdue$is_overdue && p_overdue$priority_score >= 80, "Overdue high-importance task receives Urgent tier (>=80 pts)")
  assert(grepl("Overdue by 2 days", p_overdue$explanation), "Overdue explanation clearly states days overdue")
  
  # Due Today task
  t_today <- list(title = "Due Today", category = "A", deadline = "2026-10-14", importance = "High", duration_mins = 60, status = "Pending")
  p_today <- calculate_task_priority(t_today, ref_date = ref_date)
  assert(p_today$deadline_status == "Due Today" && p_today$urgency_score == 45, "Due today task receives 45 urgency points")
  
  # Task without deadline
  t_no_date <- list(title = "No Deadline", category = "A", deadline = "", importance = "Medium", duration_mins = 45, status = "Pending")
  p_no_date <- calculate_task_priority(t_no_date, ref_date = ref_date)
  assert(p_no_date$deadline_status == "No Deadline" && p_no_date$urgency_score == 15, "Task without deadline receives consistent baseline urgency (15 pts)")
  assert(grepl("No fixed deadline", p_no_date$explanation), "Explanation acknowledges absence of deadline")
  
  # Completed task
  t_done <- list(title = "Done Task", category = "A", deadline = "2026-10-10", importance = "High", duration_mins = 30, status = "Completed")
  p_done <- calculate_task_priority(t_done, ref_date = ref_date)
  assert(p_done$priority_score == 0 && p_done$priority_tier == "Completed", "Completed task receives 0 score and Completed tier")
  
  # 4. Importance Levels Impact
  cat("\n--- 4. Importance Levels Comparison ---\n")
  t_high <- list(title = "H", category = "A", deadline = "2026-10-20", importance = "High", duration_mins = 60, status = "Pending")
  t_med <- list(title = "M", category = "A", deadline = "2026-10-20", importance = "Medium", duration_mins = 60, status = "Pending")
  t_low <- list(title = "L", category = "A", deadline = "2026-10-20", importance = "Low", duration_mins = 60, status = "Pending")
  p_h <- calculate_task_priority(t_high, ref_date = ref_date)
  p_m <- calculate_task_priority(t_med, ref_date = ref_date)
  p_l <- calculate_task_priority(t_low, ref_date = ref_date)
  assert(p_h$priority_score > p_m$priority_score && p_m$priority_score > p_l$priority_score, "High importance ranks above Medium, which ranks above Low for identical deadlines")
  
  # 5. Deterministic Tie-Breaking & Ranking
  cat("\n--- 5. Deterministic Ranking & Recommendations ---\n")
  ranked <- rank_tasks(df, ref_date = ref_date)
  assert(ranked$status[1] != "Completed", "Active tasks strictly precede completed tasks in ranking")
  assert(ranked$priority_score[1] >= ranked$priority_score[2], "Tasks are ordered descending by priority score")
  
  # Check that completed tasks are placed at the bottom
  completed_indices <- which(ranked$status == "Completed")
  active_indices <- which(ranked$status != "Completed")
  assert(all(completed_indices > max(active_indices)), "All completed tasks are placed after all active tasks")
  
  # 6. Smart Recommendations
  cat("\n--- 6. Smart Recommendations ---\n")
  rec <- get_task_recommendations(df, ref_date = ref_date)
  assert(!is.null(rec$top_recommendation), "Top recommendation identified successfully")
  assert(rec$top_recommendation$status != "Completed", "Top recommendation is an active task")
  assert(nzchar(rec$top_recommendation$recommendation_rationale), "Top recommendation has meaningful rationale")
  assert(rec$overdue_count >= 1, "Accurately detects overdue tasks count")
  
  # 7. Available-Time Planning
  cat("\n--- 7. Available-Time Planning Logic ---\n")
  plan_short <- plan_available_time(df, available_hours = 1.5, ref_date = ref_date) # 90 mins
  assert(plan_short$allocated_mins <= plan_short$available_mins, "Available-time planner does not exceed available time")
  assert(length(plan_short$fitting_tasks) > 0, "Selects at least one task to fit in 1.5 hours")
  assert(length(plan_short$deferred_tasks) > 0, "Identifies deferred tasks when workload overflows available time")
  assert(plan_short$overflow_mins > 0, "Calculates overflow minutes correctly")
  
  plan_large <- plan_available_time(df, available_hours = 20.0, ref_date = ref_date) # 1200 mins
  assert(plan_large$overflow_mins == 0 && plan_large$unused_mins > 0, "Large session has 0 overflow and positive unused buffer")
  assert(length(plan_large$deferred_tasks) == 0, "No tasks deferred when all fit into session")
  
  # 8. Search & Multi-Filter
  cat("\n--- 8. Search & Multi-Criteria Filtering ---\n")
  search_title <- search_and_filter_tasks(df, query = "security", ref_date = ref_date)
  assert(nrow(search_title) >= 1 && grepl("Security", search_title$title[1], ignore.case = TRUE), "Keyword search matches title case-insensitively")
  
  search_desc <- search_and_filter_tasks(df, query = "authentication", ref_date = ref_date)
  assert(nrow(search_desc) >= 1, "Keyword search matches description content")
  
  filter_multi <- search_and_filter_tasks(df, status = "Pending", importance = "High", ref_date = ref_date)
  assert(nrow(filter_multi) >= 1 && all(filter_multi$status == "Pending" & filter_multi$importance == "High"), "Multi-filter combines status and importance")
  
  empty_search <- search_and_filter_tasks(df, query = "nonexistent_task_xyz_123", ref_date = ref_date)
  assert(nrow(empty_search) == 0, "Non-matching query returns empty result without error")
  
  # 9. CRUD & Restart Persistence
  cat("\n--- 9. CRUD Operations & Persistence ---\n")
  temp_csv <- file.path(tempdir(), paste0("test_tasks_", as.numeric(Sys.time()), ".csv"))
  file.copy(DATA_FILE, temp_csv)
  
  new_item <- list(
    id = "task_test_99",
    title = 'Unit Test "Task" with Commas & Quotes',
    description = "Test description with, commas, and \"quotes\".",
    category = "Testing",
    deadline = "2026-10-25",
    importance = "High",
    duration_mins = 60,
    status = "Pending"
  )
  
  add_res <- add_task(new_item, temp_csv, ref_date = ref_date)
  assert(add_res$success, "Task added successfully to CSV")
  
  reloaded <- load_tasks(temp_csv)
  found_row <- reloaded[reloaded$id == "task_test_99", ]
  assert(nrow(found_row) == 1, "Added task retrieved after reload")
  assert(grepl("commas", found_row$description[1]), "Commas and quotes preserved safely")
  
  # Toggle status
  tog_res <- toggle_task_status("task_test_99", temp_csv, ref_date = ref_date)
  assert(tog_res$success && tog_res$new_status == "Completed", "Task status toggled to Completed")
  
  reloaded_tog <- load_tasks(temp_csv)
  assert(reloaded_tog[reloaded_tog$id == "task_test_99", "status"] == "Completed", "Toggled status persisted to CSV")
  
  # Delete task
  del_res <- delete_task("task_test_99", temp_csv)
  assert(del_res$success, "Task deleted successfully")
  
  reloaded_del <- load_tasks(temp_csv)
  assert(! "task_test_99" %in% reloaded_del$id, "Deleted task removed from CSV")
  
  unlink(temp_csv)
  
  cat("\n==========================================================\n")
  cat(sprintf("  Results: %d Passed, %d Failed\n", passed, failed))
  cat("==========================================================\n\n")
  
  if (failed > 0) quit(status = 1)
}

# ------------------------------------------------------------------------------
# Interactive Demo Mode (--demo)
# ------------------------------------------------------------------------------
run_demo <- function() {
  cat("\n==========================================================\n")
  cat("  Smart Task Priority Assistant - Interactive R Demo      \n")
  cat("==========================================================\n\n")
  
  ref_date <- as.Date("2026-10-14")
  df <- load_tasks(DATA_FILE)
  cat(sprintf("Loaded %d tasks from %s\n", nrow(df), DATA_FILE))
  cat(sprintf("Reference Evaluation Date: %s\n\n", as.character(ref_date)))
  
  cat("--- 1. High-Level Smart Recommendations ---\n")
  recs <- get_task_recommendations(df, ref_date = ref_date)
  cat(sprintf("Total Tasks: %d | Active: %d | Completed: %d\n", recs$total_tasks, recs$active_tasks_count, recs$completed_tasks_count))
  cat(sprintf("Total Active Workload: %s (%d mins)\n", recs$total_workload_hours, recs$total_workload_mins))
  cat(sprintf("Urgent Items: %d | Overdue Items: %d\n\n", recs$urgent_count, recs$overdue_count))
  
  if (!is.null(recs$top_recommendation)) {
    top <- recs$top_recommendation
    cat(">>> TOP RECOMMENDATION TO WORK ON NEXT <<<\n")
    cat(sprintf("Task: [%s] %s (%s - %s mins)\n", top$id, top$title, top$category, top$duration_mins))
    cat(sprintf("Priority: %s (Score: %d/100) | Deadline: %s (%s)\n", top$priority_tier, top$priority_score, top$deadline, top$deadline_status))
    cat(sprintf("Rationale: %s\n", top$recommendation_rationale))
    cat(sprintf("Formula Explanation: %s\n\n", top$explanation))
  }
  
  cat("--- 2. Ranked Active Task Priority List ---\n")
  for (t in recs$ranked_active_tasks) {
    cat(sprintf("  #%d [%s] %s\n", which(vapply(recs$ranked_active_tasks, function(x) x$id == t$id, logical(1))), t$priority_tier, t$title))
    cat(sprintf("      Score: %d/100 | Deadline: %s | Est: %d mins | Status: %s\n", t$priority_score, if (nzchar(t$deadline)) t$deadline else "None", t$duration_mins, t$status))
    cat(sprintf("      Why: %s\n\n", t$explanation))
  }
  
  cat("--- 3. Available-Time Planning (Session: 2.5 hours = 150 mins) ---\n")
  plan <- plan_available_time(df, available_hours = 2.5, ref_date = ref_date)
  cat(sprintf("Available: %d mins | Allocated: %d mins | Unused Buffer: %d mins\n", plan$available_mins, plan$allocated_mins, plan$unused_mins))
  cat(sprintf("Notice: %s\n\n", plan$warning_message))
  
  cat("Allocated Tasks in Sequence:\n")
  for (ft in plan$fitting_tasks) {
    cat(sprintf("  [+] [%s] %s (%d mins) -> Cumulative: %d/%d mins (Slack: %d mins)\n", ft$priority_tier, ft$title, ft$duration_mins, ft$cumulative_mins, plan$available_mins, ft$remaining_after_task))
  }
  
  if (length(plan$deferred_tasks) > 0) {
    cat("\nDeferred Tasks (Exceeds Session Window):\n")
    for (dt in plan$deferred_tasks) {
      cat(sprintf("  [-] [%s] %s (Requires %d mins, only %d mins slack remaining)\n", dt$priority_tier, dt$title, dt$duration_mins, dt$available_slack))
    }
  }
  
  cat("\nDemo completed successfully.\n\n")
}

# ------------------------------------------------------------------------------
# Plumber API Server & Static Mounting
# ------------------------------------------------------------------------------
start_server <- function(port = 8000, host = "127.0.0.1") {
  if (!requireNamespace("plumber", quietly = TRUE)) {
    stop("The 'plumber' package is required. Install it with install.packages('plumber').")
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("The 'jsonlite' package is required. Install it with install.packages('jsonlite').")
  }
  
  cat("\nInitializing Smart Task Priority Assistant Server...\n")
  cat(sprintf("Data File: %s\n", DATA_FILE))
  cat(sprintf("Web Root:  %s\n", WEB_DIR))
  
  pr <- plumber::pr()
  pr$setSerializer(plumber::serializer_unboxed_json())
  
  # CORS and Response Headers Middleware
  pr$registerHooks(list(
    preroute = function(req) {
      if (req$REQUEST_METHOD == "OPTIONS") {
        res <- req$res
        res$status <- 200
        res$setHeader("Access-Control-Allow-Origin", "*")
        res$setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept")
        return(list())
      }
    },
    postroute = function(req, res) {
      res$setHeader("Access-Control-Allow-Origin", "*")
      res$setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
      res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept")
    }
  ))
  
  parse_body <- function(req) {
    if (!is.null(req$postBody) && nzchar(req$postBody)) {
      tryCatch({
        return(jsonlite::fromJSON(req$postBody, simplifyVector = FALSE))
      }, error = function(e) list())
    }
    if (!is.null(req$body)) {
      if (is.list(req$body)) return(req$body)
      if (is.character(req$body) && nzchar(req$body)) {
        tryCatch({
          return(jsonlite::fromJSON(req$body, simplifyVector = FALSE))
        }, error = function(e) list())
      }
    }
    return(list())
  }
  
  # ---------------- API ENDPOINTS ----------------
  
  # 1. Health check
  pr$handle("GET", "/api/health", function(res) {
    df <- load_tasks(DATA_FILE)
    list(
      status = "ok",
      application = "Smart Task Priority Assistant",
      tasks_count = nrow(df),
      data_file = DATA_FILE,
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ")
    )
  })
  
  # 2. Get tasks (search, filter, sort)
  pr$handle("GET", "/api/tasks", function(
    req, res,
    q = "",
    status = "",
    importance = "",
    category = "",
    sort_by = "priority",
    sort_dir = "desc"
  ) {
    df <- load_tasks(DATA_FILE)
    filtered <- search_and_filter_tasks(
      df,
      query = q,
      status = status,
      importance = importance,
      category = category,
      sort_by = sort_by,
      sort_dir = sort_dir,
      ref_date = Sys.Date()
    )
    
    tasks_list <- list()
    if (nrow(filtered) > 0) {
      for (i in seq_len(nrow(filtered))) {
        tasks_list[[i]] <- list(
          id = filtered$id[i],
          title = filtered$title[i],
          description = filtered$description[i],
          category = filtered$category[i],
          deadline = filtered$deadline[i],
          importance = filtered$importance[i],
          duration_mins = as.integer(filtered$duration_mins[i]),
          status = filtered$status[i],
          created_at = filtered$created_at[i],
          updated_at = filtered$updated_at[i],
          priority_score = filtered$priority_score[i],
          priority_tier = filtered$priority_tier[i],
          deadline_status = filtered$deadline_status[i],
          is_overdue = filtered$is_overdue[i],
          explanation = filtered$explanation[i]
        )
      }
    }
    
    list(
      total_tasks = nrow(df),
      matched_count = nrow(filtered),
      tasks = tasks_list
    )
  })
  
  # 3. Get single task by ID
  pr$handle("GET", "/api/tasks/<id>", function(id, res) {
    df <- load_tasks(DATA_FILE)
    idx <- which(df$id == id)
    if (length(idx) == 0) {
      res$status <- 404
      return(list(error = paste0("Task '", id, "' not found.")))
    }
    
    calc <- calculate_task_priority(df[idx[1], ], ref_date = Sys.Date())
    row <- df[idx[1], ]
    
    list(
      id = row$id,
      title = row$title,
      description = row$description,
      category = row$category,
      deadline = row$deadline,
      importance = row$importance,
      duration_mins = as.integer(row$duration_mins),
      status = row$status,
      created_at = row$created_at,
      updated_at = row$updated_at,
      priority_score = calc$priority_score,
      priority_tier = calc$priority_tier,
      deadline_status = calc$deadline_status,
      is_overdue = calc$is_overdue,
      explanation = calc$explanation
    )
  })
  
  # 4. Create new task
  pr$handle("POST", "/api/tasks", function(req, res) {
    body <- parse_body(req)
    if (length(body) == 0) {
      res$status <- 400
      return(list(success = FALSE, errors = c("Request body is empty or not valid JSON.")))
    }
    
    result <- add_task(body, DATA_FILE, ref_date = Sys.Date())
    if (!result$success) {
      res$status <- 422
      return(list(success = FALSE, errors = result$errors))
    }
    
    res$status <- 201
    return(result)
  })
  
  # 5. Update task
  pr$handle("PUT", "/api/tasks/<id>", function(id, req, res) {
    body <- parse_body(req)
    if (length(body) == 0) {
      res$status <- 400
      return(list(success = FALSE, errors = c("Request body is empty or not valid JSON.")))
    }
    
    result <- update_task(id, body, DATA_FILE, ref_date = Sys.Date())
    if (!result$success) {
      res$status <- if (any(grepl("not found", result$errors))) 404 else 422
      return(list(success = FALSE, errors = result$errors))
    }
    return(result)
  })
  
  # 6. Toggle task completion
  pr$handle("POST", "/api/tasks/<id>/toggle", function(id, res) {
    result <- toggle_task_status(id, DATA_FILE, ref_date = Sys.Date())
    if (!result$success) {
      res$status <- 404
      return(list(success = FALSE, errors = result$errors))
    }
    return(result)
  })
  
  # 7. Delete task
  pr$handle("DELETE", "/api/tasks/<id>", function(id, res) {
    result <- delete_task(id, DATA_FILE)
    if (!result$success) {
      res$status <- 404
      return(list(success = FALSE, errors = result$errors))
    }
    return(result)
  })
  
  # 8. High-level recommendations
  pr$handle("GET", "/api/recommendations", function(res) {
    df <- load_tasks(DATA_FILE)
    recs <- get_task_recommendations(df, ref_date = Sys.Date())
    return(recs)
  })
  
  # 9. Available-time planning
  pr$handle("GET", "/api/plan-time", function(hours = 3.0, res) {
    df <- load_tasks(DATA_FILE)
    plan <- plan_available_time(df, available_hours = hours, ref_date = Sys.Date())
    return(plan)
  })
  
  # Static web files
  if (dir.exists(WEB_DIR)) {
    pr <- plumber::pr_static(pr, "/", WEB_DIR)
  }
  
  cat("\n==========================================================\n")
  cat("  Smart Task Priority Assistant is Ready!\n")
  cat(sprintf("  Local URL:        http://%s:%d\n", host, port))
  cat(sprintf("  API Health:       http://%s:%d/api/health\n", host, port))
  cat(sprintf("  Recommendations:  http://%s:%d/api/recommendations\n", host, port))
  cat("  Press Ctrl+C to stop the server.\n")
  cat("==========================================================\n\n")
  
  pr$run(host = host, port = as.integer(port))
}

# ------------------------------------------------------------------------------
# Entrypoint Dispatcher
# ------------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)

if ("--test" %in% args) {
  run_tests()
} else if ("--demo" %in% args) {
  run_demo()
} else {
  port <- 8000
  port_arg_idx <- which(grepl("^--port=", args))
  if (length(port_arg_idx) > 0) {
    port <- as.integer(sub("^--port=", "", args[port_arg_idx[1]]))
  } else {
    port_idx <- which(args == "-p" | args == "--port")
    if (length(port_idx) > 0 && length(args) >= port_idx + 1) {
      port <- as.integer(args[port_idx + 1])
    }
  }
  start_server(port = port)
}
