# ==============================================================================
# Smart Task Priority Assistant - Core Logic & Data Processing
# R/functions.R
# ==============================================================================

# Standard Schema Definition
TASK_COLUMNS <- c(
  "id", "title", "description", "category", "deadline",
  "importance", "duration_mins", "status", "created_at", "updated_at"
)

ALLOWED_IMPORTANCE <- c("Low", "Medium", "High")
ALLOWED_STATUS <- c("Pending", "In Progress", "Completed")

# ------------------------------------------------------------------------------
# 1. File Handling & CSV Persistence
# ------------------------------------------------------------------------------

#' Ensure an initialized CSV file exists
init_tasks_file <- function(file_path) {
  dir_name <- dirname(file_path)
  if (!dir.exists(dir_name)) {
    dir.create(dir_name, recursive = TRUE, showWarnings = FALSE)
  }
  if (!file.exists(file_path) || file.info(file_path)$size == 0) {
    empty_df <- data.frame(matrix(ncol = length(TASK_COLUMNS), nrow = 0))
    colnames(empty_df) <- TASK_COLUMNS
    write.csv(empty_df, file = file_path, row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
  }
}

#' Load all tasks from CSV safely
load_tasks <- function(file_path) {
  init_tasks_file(file_path)
  
  tryCatch({
    df <- read.csv(
      file_path,
      stringsAsFactors = FALSE,
      colClasses = "character",
      strip.white = FALSE,
      fill = TRUE,
      encoding = "UTF-8"
    )
    
    # Ensure all required columns exist
    for (col in TASK_COLUMNS) {
      if (!col %in% colnames(df)) {
        df[[col]] <- character(nrow(df))
      }
    }
    
    df <- df[, TASK_COLUMNS, drop = FALSE]
    for (col in TASK_COLUMNS) {
      df[[col]][is.na(df[[col]])] <- ""
      df[[col]] <- as.character(df[[col]])
    }
    
    # Standardize duration_mins as integer string
    for (i in seq_len(nrow(df))) {
      d_val <- suppressWarnings(as.integer(df$duration_mins[i]))
      df$duration_mins[i] <- if (!is.na(d_val) && d_val > 0) as.character(d_val) else "30"
    }
    
    return(df)
  }, error = function(e) {
    warning("Error reading tasks CSV: ", e$message, ". Returning empty collection.")
    empty_df <- data.frame(matrix(ncol = length(TASK_COLUMNS), nrow = 0))
    colnames(empty_df) <- TASK_COLUMNS
    return(empty_df)
  })
}

#' Save tasks data.frame to CSV with proper quoting
save_tasks <- function(tasks_df, file_path) {
  dir_name <- dirname(file_path)
  if (!dir.exists(dir_name)) {
    dir.create(dir_name, recursive = TRUE, showWarnings = FALSE)
  }
  
  for (col in TASK_COLUMNS) {
    if (!col %in% colnames(tasks_df)) {
      tasks_df[[col]] <- ""
    }
    tasks_df[[col]][is.na(tasks_df[[col]])] <- ""
    tasks_df[[col]] <- as.character(tasks_df[[col]])
  }
  tasks_df <- tasks_df[, TASK_COLUMNS, drop = FALSE]
  
  write.csv(
    tasks_df,
    file = file_path,
    row.names = FALSE,
    quote = TRUE,
    fileEncoding = "UTF-8"
  )
  return(TRUE)
}

# ------------------------------------------------------------------------------
# 2. Validation
# ------------------------------------------------------------------------------

#' Validate a task record
validate_task <- function(task, existing_df = NULL, is_edit = FALSE) {
  errors <- character(0)
  
  title <- trimws(as.character(if (!is.null(task$title)) task$title else ""))
  category <- trimws(as.character(if (!is.null(task$category)) task$category else ""))
  importance <- trimws(as.character(if (!is.null(task$importance)) task$importance else "Medium"))
  status <- trimws(as.character(if (!is.null(task$status)) task$status else "Pending"))
  deadline <- trimws(as.character(if (!is.null(task$deadline)) task$deadline else ""))
  id <- trimws(as.character(if (!is.null(task$id)) task$id else ""))
  
  # Title validation
  if (!nzchar(title)) {
    errors <- c(errors, "Task title is required and cannot be blank.")
  } else if (nchar(title) > 150) {
    errors <- c(errors, "Task title must be 150 characters or fewer.")
  }
  
  # Category validation
  if (!nzchar(category)) {
    errors <- c(errors, "Task category is required.")
  }
  
  # Importance validation
  if (!importance %in% ALLOWED_IMPORTANCE) {
    errors <- c(errors, paste0("Importance must be one of: ", paste(ALLOWED_IMPORTANCE, collapse = ", ")))
  }
  
  # Status validation
  if (!status %in% ALLOWED_STATUS) {
    errors <- c(errors, paste0("Status must be one of: ", paste(ALLOWED_STATUS, collapse = ", ")))
  }
  
  # Duration validation
  duration_raw <- if (!is.null(task$duration_mins)) task$duration_mins else 0
  duration_val <- suppressWarnings(as.numeric(duration_raw))
  if (is.na(duration_val) || duration_val <= 0) {
    errors <- c(errors, "Estimated duration must be a positive number of minutes (e.g., 30, 60, 120).")
  } else if (duration_val > 1440) {
    errors <- c(errors, "Estimated duration cannot exceed 1440 minutes (24 hours). Consider breaking this task down.")
  }
  
  # Deadline validation (optional, but if provided must match YYYY-MM-DD)
  if (nzchar(deadline)) {
    parsed_date <- tryCatch(as.Date(deadline, format = "%Y-%m-%d"), error = function(e) NA)
    if (is.na(parsed_date) || !grepl("^\\d{4}-\\d{2}-\\d{2}$", deadline)) {
      errors <- c(errors, "Deadline must be formatted as YYYY-MM-DD (e.g. 2026-10-25).")
    }
  }
  
  # Unique ID validation for new tasks
  if (!is_edit && !is.null(existing_df) && nrow(existing_df) > 0 && nzchar(id)) {
    if (id %in% existing_df$id) {
      errors <- c(errors, paste0("A task with ID '", id, "' already exists."))
    }
  }
  
  list(
    valid = (length(errors) == 0),
    errors = errors
  )
}

# ------------------------------------------------------------------------------
# 3. Explainable Priority Scoring Algorithm
# ------------------------------------------------------------------------------

#' Calculate deterministic priority score, category, and human-readable explanation
#'
#' Scoring model (0 - 100 points for active tasks):
#' 1. Urgency Component (0 - 50 points):
#'    - Overdue: 45 - 50 pts (critical urgency based on days overdue)
#'    - Due Today: 45 pts
#'    - Due in 1-2 days: 35 - 40 pts
#'    - Due in 3-7 days: 22 - 30 pts
#'    - Due in 8-14 days: 12 - 18 pts
#'    - Due in >14 days: 5 - 12 pts
#'    - No deadline: 15 pts baseline pacing
#' 2. Importance Component (0 - 35 points):
#'    - High: 35 pts
#'    - Medium: 22 pts
#'    - Low: 10 pts
#' 3. Duration Component (0 - 15 points):
#'    - Quick-win (<= 30 mins): 12 pts
#'    - Focus block (31 - 90 mins): 15 pts
#'    - Multi-hour (91 - 180 mins): 10 pts
#'    - Large project (> 180 mins): 6 pts
#' 4. Status Modifier:
#'    - In Progress: +5 bonus momentum points
#'    - Completed: Score = 0, Tier = "Completed"
calculate_task_priority <- function(task, ref_date = Sys.Date()) {
  ref_date <- as.Date(ref_date)
  status <- trimws(as.character(task$status))
  importance <- trimws(as.character(task$importance))
  duration_mins <- suppressWarnings(as.integer(task$duration_mins))
  if (is.na(duration_mins) || duration_mins <= 0) duration_mins <- 30
  
  deadline_str <- trimws(as.character(task$deadline))
  has_deadline <- nzchar(deadline_str)
  
  # If completed, short-circuit
  if (status == "Completed") {
    return(list(
      priority_score = 0,
      priority_tier = "Completed",
      urgency_score = 0,
      importance_score = 0,
      duration_score = 0,
      status_bonus = 0,
      days_remaining = NA_integer_,
      deadline_status = "Completed",
      is_overdue = FALSE,
      explanation = "Task has been completed."
    ))
  }
  
  # 1. Urgency calculation
  days_remaining <- NA_integer_
  urgency_score <- 15
  deadline_status <- "No Deadline"
  is_overdue <- FALSE
  urgency_phrase <- "No fixed deadline assigned (15/50 baseline pacing)"
  
  if (has_deadline) {
    deadline_date <- tryCatch(as.Date(deadline_str, format = "%Y-%m-%d"), error = function(e) NA)
    if (!is.na(deadline_date)) {
      days_remaining <- as.integer(deadline_date - ref_date)
      
      if (days_remaining < 0) {
        is_overdue <- TRUE
        overdue_days <- abs(days_remaining)
        urgency_score <- min(50, 45 + min(5, overdue_days))
        deadline_status <- "Overdue"
        urgency_phrase <- sprintf("Overdue by %d day%s (%d/50 critical urgency)", overdue_days, if (overdue_days > 1) "s" else "", urgency_score)
      } else if (days_remaining == 0) {
        urgency_score <- 45
        deadline_status <- "Due Today"
        urgency_phrase <- "Due today (45/50 immediate action required)"
      } else if (days_remaining <= 2) {
        urgency_score <- 40 - (days_remaining - 1) * 5
        deadline_status <- "Approaching"
        urgency_phrase <- sprintf("Due in %d day%s (%d/50 approaching deadline)", days_remaining, if (days_remaining > 1) "s" else "", urgency_score)
      } else if (days_remaining <= 7) {
        urgency_score <- 30 - (days_remaining - 3) * 2
        deadline_status <- "Upcoming"
        urgency_phrase <- sprintf("Due in %d days (%d/50 weekly target)", days_remaining, urgency_score)
      } else if (days_remaining <= 14) {
        urgency_score <- 18 - (days_remaining - 8) * 1
        deadline_status <- "Upcoming"
        urgency_phrase <- sprintf("Due in %d days (%d/50 comfortable runway)", days_remaining, urgency_score)
      } else {
        urgency_score <- max(5, 12 - as.integer((days_remaining - 14) / 7))
        deadline_status <- "Upcoming"
        urgency_phrase <- sprintf("Due in %d days (%d/50 long-term target)", days_remaining, urgency_score)
      }
    }
  }
  
  # 2. Importance calculation
  importance_score <- switch(
    importance,
    "High" = 35,
    "Medium" = 22,
    "Low" = 10,
    22
  )
  importance_phrase <- switch(
    importance,
    "High" = "High importance (+35 pts)",
    "Medium" = "Medium importance (+22 pts)",
    "Low" = "Low importance (+10 pts)",
    "Medium importance (+22 pts)"
  )
  
  # 3. Duration factor
  if (duration_mins <= 30) {
    duration_score <- 12
    duration_phrase <- sprintf("quick-win effort (%d mins, +12 pts)", duration_mins)
  } else if (duration_mins <= 90) {
    duration_score <- 15
    duration_phrase <- sprintf("optimal focus block (%d mins, +15 pts)", duration_mins)
  } else if (duration_mins <= 180) {
    duration_score <- 10
    duration_phrase <- sprintf("substantial workload (%d mins, +10 pts)", duration_mins)
  } else {
    duration_score <- 6
    duration_phrase <- sprintf("large project block (%d mins, +6 pts)", duration_mins)
  }
  
  # 4. Status bonus
  status_bonus <- 0
  status_phrase <- ""
  if (status == "In Progress") {
    status_bonus <- 5
    status_phrase <- "; active in-progress momentum bonus (+5 pts)"
  }
  
  # Composite Score
  raw_score <- urgency_score + importance_score + duration_score + status_bonus
  final_score <- min(100, max(1, raw_score))
  
  # Priority Tier
  priority_tier <- if (is_overdue || final_score >= 80) {
    "Urgent"
  } else if (final_score >= 65) {
    "High"
  } else if (final_score >= 45) {
    "Medium"
  } else {
    "Low"
  }
  
  # Human-readable synthesized explanation
  explanation <- sprintf(
    "%s paired with %s and %s%s, resulting in %s priority (score: %d/100).",
    urgency_phrase,
    importance_phrase,
    duration_phrase,
    status_phrase,
    priority_tier,
    final_score
  )
  
  list(
    priority_score = final_score,
    priority_tier = priority_tier,
    urgency_score = urgency_score,
    importance_score = importance_score,
    duration_score = duration_score,
    status_bonus = status_bonus,
    days_remaining = days_remaining,
    deadline_status = deadline_status,
    is_overdue = is_overdue,
    explanation = explanation
  )
}

#' Rank tasks deterministically with complete tie-breaking rules
rank_tasks <- function(tasks_df, ref_date = Sys.Date()) {
  if (is.null(tasks_df) || nrow(tasks_df) == 0) {
    return(data.frame())
  }
  
  n <- nrow(tasks_df)
  priority_scores <- integer(n)
  priority_tiers <- character(n)
  urgency_scores <- integer(n)
  importance_scores <- integer(n)
  duration_scores <- integer(n)
  days_remaining_vec <- integer(n)
  deadline_statuses <- character(n)
  is_overdue_vec <- logical(n)
  explanations <- character(n)
  
  for (i in seq_len(n)) {
    calc <- calculate_task_priority(tasks_df[i, ], ref_date = ref_date)
    priority_scores[i] <- calc$priority_score
    priority_tiers[i] <- calc$priority_tier
    urgency_scores[i] <- calc$urgency_score
    importance_scores[i] <- calc$importance_score
    duration_scores[i] <- calc$duration_score
    days_remaining_vec[i] <- if (is.na(calc$days_remaining)) 9999 else calc$days_remaining
    deadline_statuses[i] <- calc$deadline_status
    is_overdue_vec[i] <- calc$is_overdue
    explanations[i] <- calc$explanation
  }
  
  ranked_df <- tasks_df
  ranked_df$priority_score <- priority_scores
  ranked_df$priority_tier <- priority_tiers
  ranked_df$urgency_score <- urgency_scores
  ranked_df$importance_score <- importance_scores
  ranked_df$duration_score <- duration_scores
  ranked_df$days_remaining <- days_remaining_vec
  ranked_df$deadline_status <- deadline_statuses
  ranked_df$is_overdue <- is_overdue_vec
  ranked_df$explanation <- explanations
  
  # Deterministic Tie-Breaking Order:
  # 1. Active before Completed (status != "Completed" decreasing)
  # 2. Priority score decreasing
  # 3. Days remaining ascending (earliest deadline first; 9999 for no deadline placed last)
  # 4. Importance level decreasing (High > Medium > Low)
  # 5. Duration minutes ascending (shorter tasks break ties)
  # 6. ID ascending (unique determinism)
  is_active <- as.integer(ranked_df$status != "Completed")
  imp_levels <- c("High" = 3, "Medium" = 2, "Low" = 1)
  imp_rank <- unname(imp_levels[ranked_df$importance])
  imp_rank[is.na(imp_rank)] <- 0
  
  dur_num <- suppressWarnings(as.integer(ranked_df$duration_mins))
  dur_num[is.na(dur_num)] <- 0
  
  order_idx <- order(
    -is_active,
    -ranked_df$priority_score,
    ranked_df$days_remaining,
    -imp_rank,
    dur_num,
    ranked_df$id
  )
  
  ranked_df <- ranked_df[order_idx, , drop = FALSE]
  rownames(ranked_df) <- NULL
  return(ranked_df)
}

# ------------------------------------------------------------------------------
# 4. CRUD Operations
# ------------------------------------------------------------------------------

#' Add a new task
add_task <- function(new_task, file_path, ref_date = Sys.Date()) {
  df <- load_tasks(file_path)
  
  val <- validate_task(new_task, existing_df = df, is_edit = FALSE)
  if (!val$valid) {
    return(list(success = FALSE, errors = val$errors, task = NULL))
  }
  
  task_id <- trimws(as.character(if (!is.null(new_task$id) && nzchar(new_task$id)) new_task$id else ""))
  if (!nzchar(task_id)) {
    timestamp_part <- format(Sys.time(), "%Y%m%d%H%M%S")
    rand_hex <- paste(sample(c(0:9, letters[1:6]), 4, replace = TRUE), collapse = "")
    task_id <- paste0("task_", timestamp_part, "_", rand_hex)
  }
  
  today_str <- as.character(Sys.Date())
  created_at <- if (!is.null(new_task$created_at) && nzchar(new_task$created_at)) as.character(new_task$created_at) else today_str
  updated_at <- today_str
  
  duration_val <- as.integer(new_task$duration_mins)
  
  new_row <- data.frame(
    id = task_id,
    title = trimws(as.character(new_task$title)),
    description = trimws(as.character(if (!is.null(new_task$description)) new_task$description else "")),
    category = trimws(as.character(new_task$category)),
    deadline = trimws(as.character(if (!is.null(new_task$deadline)) new_task$deadline else "")),
    importance = trimws(as.character(new_task$importance)),
    duration_mins = as.character(duration_val),
    status = trimws(as.character(if (!is.null(new_task$status)) new_task$status else "Pending")),
    created_at = created_at,
    updated_at = updated_at,
    stringsAsFactors = FALSE
  )
  
  updated_df <- rbind(df, new_row)
  save_tasks(updated_df, file_path)
  
  calc <- calculate_task_priority(new_row[1, ], ref_date = ref_date)
  task_obj <- as.list(new_row[1, ])
  task_obj$priority_score <- calc$priority_score
  task_obj$priority_tier <- calc$priority_tier
  task_obj$explanation <- calc$explanation
  task_obj$deadline_status <- calc$deadline_status
  task_obj$is_overdue <- calc$is_overdue
  
  return(list(success = TRUE, errors = character(0), task = task_obj))
}

#' Update an existing task
update_task <- function(task_id, updated_fields, file_path, ref_date = Sys.Date()) {
  df <- load_tasks(file_path)
  
  if (nrow(df) == 0 || !task_id %in% df$id) {
    return(list(success = FALSE, errors = c(paste0("Task with ID '", task_id, "' not found.")), task = NULL))
  }
  
  idx <- which(df$id == task_id)
  existing <- as.list(df[idx, ])
  
  merged <- existing
  for (nm in names(updated_fields)) {
    if (nm %in% TASK_COLUMNS && nm != "id" && nm != "created_at") {
      merged[[nm]] <- updated_fields[[nm]]
    }
  }
  
  val <- validate_task(merged, existing_df = df, is_edit = TRUE)
  if (!val$valid) {
    return(list(success = FALSE, errors = val$errors, task = NULL))
  }
  
  df$title[idx] <- trimws(as.character(merged$title))
  df$description[idx] <- trimws(as.character(merged$description))
  df$category[idx] <- trimws(as.character(merged$category))
  df$deadline[idx] <- trimws(as.character(merged$deadline))
  df$importance[idx] <- trimws(as.character(merged$importance))
  df$duration_mins[idx] <- as.character(as.integer(merged$duration_mins))
  df$status[idx] <- trimws(as.character(merged$status))
  df$updated_at[idx] <- as.character(Sys.Date())
  
  save_tasks(df, file_path)
  
  calc <- calculate_task_priority(df[idx, ], ref_date = ref_date)
  task_obj <- as.list(df[idx, ])
  task_obj$priority_score <- calc$priority_score
  task_obj$priority_tier <- calc$priority_tier
  task_obj$explanation <- calc$explanation
  task_obj$deadline_status <- calc$deadline_status
  task_obj$is_overdue <- calc$is_overdue
  
  return(list(success = TRUE, errors = character(0), task = task_obj))
}

#' Toggle task completion status
toggle_task_status <- function(task_id, file_path, ref_date = Sys.Date()) {
  df <- load_tasks(file_path)
  if (nrow(df) == 0 || !task_id %in% df$id) {
    return(list(success = FALSE, errors = c(paste0("Task with ID '", task_id, "' not found."))))
  }
  
  idx <- which(df$id == task_id)
  current_status <- df$status[idx]
  new_status <- if (current_status == "Completed") "Pending" else "Completed"
  
  df$status[idx] <- new_status
  df$updated_at[idx] <- as.character(Sys.Date())
  save_tasks(df, file_path)
  
  calc <- calculate_task_priority(df[idx, ], ref_date = ref_date)
  task_obj <- as.list(df[idx, ])
  task_obj$priority_score <- calc$priority_score
  task_obj$priority_tier <- calc$priority_tier
  task_obj$explanation <- calc$explanation
  task_obj$deadline_status <- calc$deadline_status
  task_obj$is_overdue <- calc$is_overdue
  
  return(list(success = TRUE, new_status = new_status, task = task_obj))
}

#' Delete task by ID
delete_task <- function(task_id, file_path) {
  df <- load_tasks(file_path)
  if (nrow(df) == 0 || !task_id %in% df$id) {
    return(list(success = FALSE, errors = c(paste0("Task with ID '", task_id, "' not found."))))
  }
  
  updated_df <- df[df$id != task_id, , drop = FALSE]
  save_tasks(updated_df, file_path)
  return(list(success = TRUE, deleted_id = task_id))
}

# ------------------------------------------------------------------------------
# 5. Search, Filter & Sort
# ------------------------------------------------------------------------------

#' Search and filter tasks
search_and_filter_tasks <- function(
  tasks_df,
  query = "",
  status = "",
  importance = "",
  category = "",
  sort_by = "priority",
  sort_dir = "desc",
  ref_date = Sys.Date()
) {
  if (is.null(tasks_df) || nrow(tasks_df) == 0) {
    return(data.frame())
  }
  
  ranked_df <- rank_tasks(tasks_df, ref_date = ref_date)
  matches <- rep(TRUE, nrow(ranked_df))
  
  # 1. Search Query: case-insensitive keyword matching across title and description
  q_str <- trimws(as.character(query))
  if (nzchar(q_str)) {
    escaped_q <- gsub("([.\\^$*+?()[{\\\\|])", "\\\\\\1", q_str)
    title_match <- grepl(escaped_q, ranked_df$title, ignore.case = TRUE)
    desc_match <- grepl(escaped_q, ranked_df$description, ignore.case = TRUE)
    matches <- matches & (title_match | desc_match)
  }
  
  # 2. Status Filter
  s_str <- trimws(as.character(status))
  if (nzchar(s_str) && tolower(s_str) != "all") {
    matches <- matches & (tolower(trimws(ranked_df$status)) == tolower(s_str))
  }
  
  # 3. Importance Filter
  imp_str <- trimws(as.character(importance))
  if (nzchar(imp_str) && tolower(imp_str) != "all") {
    matches <- matches & (tolower(trimws(ranked_df$importance)) == tolower(imp_str))
  }
  
  # 4. Category Filter
  cat_str <- trimws(as.character(category))
  if (nzchar(cat_str) && tolower(cat_str) != "all") {
    matches <- matches & (tolower(trimws(ranked_df$category)) == tolower(cat_str))
  }
  
  filtered <- ranked_df[matches, , drop = FALSE]
  if (nrow(filtered) == 0) return(filtered)
  
  # 5. Sorting
  sort_by <- tolower(trimws(sort_by))
  sort_dir <- tolower(trimws(sort_dir))
  decreasing <- (sort_dir != "asc")
  
  if (sort_by == "deadline") {
    # Tasks with valid deadline sorted; tasks without placed last
    order_idx <- order(filtered$days_remaining, decreasing = !decreasing)
    filtered <- filtered[order_idx, , drop = FALSE]
  } else if (sort_by == "duration") {
    dur_num <- suppressWarnings(as.integer(filtered$duration_mins))
    order_idx <- order(dur_num, decreasing = decreasing)
    filtered <- filtered[order_idx, , drop = FALSE]
  } else if (sort_by == "created_at") {
    order_idx <- order(filtered$created_at, decreasing = decreasing)
    filtered <- filtered[order_idx, , drop = FALSE]
  } else if (sort_by == "title") {
    order_idx <- order(tolower(filtered$title), decreasing = decreasing)
    filtered <- filtered[order_idx, , drop = FALSE]
  }
  # Note: if sort_by == "priority", ranked_df is already ordered by priority!
  
  rownames(filtered) <- NULL
  return(filtered)
}

# ------------------------------------------------------------------------------
# 6. Smart Recommendations
# ------------------------------------------------------------------------------

#' Generate high-level smart recommendations and dashboard metrics
get_task_recommendations <- function(tasks_df, ref_date = Sys.Date()) {
  if (is.null(tasks_df) || nrow(tasks_df) == 0) {
    return(list(
      total_tasks = 0,
      active_tasks_count = 0,
      completed_tasks_count = 0,
      total_workload_mins = 0,
      total_workload_hours = "0.0 hrs",
      overdue_count = 0,
      approaching_count = 0,
      urgent_count = 0,
      top_recommendation = NULL,
      ranked_active_tasks = list(),
      category_breakdown = list()
    ))
  }
  
  ranked_all <- rank_tasks(tasks_df, ref_date = ref_date)
  active_df <- ranked_all[ranked_all$status != "Completed", , drop = FALSE]
  completed_df <- ranked_all[ranked_all$status == "Completed", , drop = FALSE]
  
  overdue_df <- active_df[active_df$is_overdue, , drop = FALSE]
  approaching_df <- active_df[active_df$deadline_status %in% c("Due Today", "Approaching"), , drop = FALSE]
  urgent_df <- active_df[active_df$priority_tier == "Urgent", , drop = FALSE]
  
  dur_vals <- suppressWarnings(as.integer(active_df$duration_mins))
  dur_vals[is.na(dur_vals)] <- 0
  total_workload_mins <- sum(dur_vals)
  total_workload_hours <- sprintf("%.1f hrs", total_workload_mins / 60)
  
  # Format top recommendation
  top_recommendation <- NULL
  if (nrow(active_df) > 0) {
    top_row <- active_df[1, ]
    
    # Generate prominent recommendation rationale
    rec_rationale <- if (top_row$is_overdue) {
      sprintf(
        "CRITICAL ACTION: This task is overdue by %d day%s with %s importance. Tackle this immediately to mitigate delivery delays.",
        abs(top_row$days_remaining),
        if (abs(top_row$days_remaining) > 1) "s" else "",
        top_row$importance
      )
    } else if (top_row$deadline_status == "Due Today") {
      sprintf(
        "IMMEDIATE FOCUS: Deadline expires today. Given its %s importance and %s min duration, this is your highest priority work item.",
        top_row$importance,
        top_row$duration_mins
      )
    } else if (top_row$deadline_status == "Approaching") {
      sprintf(
        "UPCOMING DEADLINE: Due in %d day%s with %s importance. Completing this now ensures high-quality execution without last-minute rush.",
        top_row$days_remaining,
        if (top_row$days_remaining > 1) "s" else "",
        top_row$importance
      )
    } else if (top_row$status == "In Progress") {
      sprintf(
        "MOMENTUM CONTINUATION: Already in progress with %s importance and strong priority score (%d/100). Finishing open tasks minimizes context-switching.",
        top_row$importance,
        top_row$priority_score
      )
    } else {
      sprintf(
        "RECOMMENDED NEXT: Highest combined score (%d/100) reflecting %s importance and manageable focus block.",
        top_row$priority_score,
        top_row$importance
      )
    }
    
    top_recommendation <- list(
      id = top_row$id,
      title = top_row$title,
      description = top_row$description,
      category = top_row$category,
      deadline = top_row$deadline,
      importance = top_row$importance,
      duration_mins = as.integer(top_row$duration_mins),
      status = top_row$status,
      priority_score = top_row$priority_score,
      priority_tier = top_row$priority_tier,
      deadline_status = top_row$deadline_status,
      is_overdue = top_row$is_overdue,
      explanation = top_row$explanation,
      recommendation_rationale = rec_rationale
    )
  }
  
  # Format active tasks list
  ranked_active_list <- list()
  if (nrow(active_df) > 0) {
    for (i in seq_len(nrow(active_df))) {
      ranked_active_list[[i]] <- list(
        id = active_df$id[i],
        title = active_df$title[i],
        description = active_df$description[i],
        category = active_df$category[i],
        deadline = active_df$deadline[i],
        importance = active_df$importance[i],
        duration_mins = as.integer(active_df$duration_mins[i]),
        status = active_df$status[i],
        priority_score = active_df$priority_score[i],
        priority_tier = active_df$priority_tier[i],
        deadline_status = active_df$deadline_status[i],
        is_overdue = active_df$is_overdue[i],
        explanation = active_df$explanation[i]
      )
    }
  }
  
  # Categories breakdown
  cats <- tasks_df$category[nzchar(trimws(tasks_df$category))]
  cat_counts <- as.list(table(cats))
  
  list(
    total_tasks = nrow(tasks_df),
    active_tasks_count = nrow(active_df),
    completed_tasks_count = nrow(completed_df),
    total_workload_mins = total_workload_mins,
    total_workload_hours = total_workload_hours,
    overdue_count = nrow(overdue_df),
    approaching_count = nrow(approaching_df),
    urgent_count = nrow(urgent_df),
    top_recommendation = top_recommendation,
    ranked_active_tasks = ranked_active_list,
    category_breakdown = cat_counts
  )
}

# ------------------------------------------------------------------------------
# 7. Available-Time Planning Logic
# ------------------------------------------------------------------------------

#' Allocate active tasks sequentially into user's available study/work hours
plan_available_time <- function(tasks_df, available_hours, ref_date = Sys.Date()) {
  available_hours <- suppressWarnings(as.numeric(available_hours))
  if (is.na(available_hours) || available_hours <= 0) {
    available_hours <- 3.0 # default to 3 hours if invalid
  }
  
  avail_mins <- as.integer(round(available_hours * 60))
  
  if (is.null(tasks_df) || nrow(tasks_df) == 0) {
    return(list(
      available_hours = available_hours,
      available_mins = avail_mins,
      allocated_mins = 0,
      unused_mins = avail_mins,
      total_workload_mins = 0,
      overflow_mins = 0,
      fitting_tasks = list(),
      deferred_tasks = list(),
      warning_message = "No tasks available to plan."
    ))
  }
  
  ranked_all <- rank_tasks(tasks_df, ref_date = ref_date)
  active_df <- ranked_all[ranked_all$status != "Completed", , drop = FALSE]
  
  if (nrow(active_df) == 0) {
    return(list(
      available_hours = available_hours,
      available_mins = avail_mins,
      allocated_mins = 0,
      unused_mins = avail_mins,
      total_workload_mins = 0,
      overflow_mins = 0,
      fitting_tasks = list(),
      deferred_tasks = list(),
      warning_message = "All tasks are completed! Enjoy your free time."
    ))
  }
  
  cumulative_mins <- 0
  fitting_list <- list()
  deferred_list <- list()
  
  for (i in seq_len(nrow(active_df))) {
    dur <- suppressWarnings(as.integer(active_df$duration_mins[i]))
    if (is.na(dur) || dur <= 0) dur <- 30
    
    item <- list(
      id = active_df$id[i],
      title = active_df$title[i],
      category = active_df$category[i],
      importance = active_df$importance[i],
      deadline = active_df$deadline[i],
      duration_mins = dur,
      priority_score = active_df$priority_score[i],
      priority_tier = active_df$priority_tier[i],
      deadline_status = active_df$deadline_status[i],
      is_overdue = active_df$is_overdue[i],
      explanation = active_df$explanation[i]
    )
    
    if (cumulative_mins + dur <= avail_mins) {
      cumulative_mins <- cumulative_mins + dur
      item$cumulative_mins <- cumulative_mins
      item$remaining_after_task <- avail_mins - cumulative_mins
      fitting_list[[length(fitting_list) + 1]] <- item
    } else {
      item$needed_mins <- dur
      item$available_slack <- max(0, avail_mins - cumulative_mins)
      deferred_list[[length(deferred_list) + 1]] <- item
    }
  }
  
  total_dur_vals <- suppressWarnings(as.integer(active_df$duration_mins))
  total_workload_mins <- sum(total_dur_vals[!is.na(total_dur_vals)])
  unused_mins <- max(0, avail_mins - cumulative_mins)
  overflow_mins <- max(0, total_workload_mins - avail_mins)
  
  warning_msg <- ""
  if (overflow_mins > 0) {
    warning_msg <- sprintf(
      "Total active workload (%s) exceeds your available session (%s) by %d mins. %d lower-priority task%s deferred to subsequent blocks.",
      sprintf("%.1f hrs", total_workload_mins / 60),
      sprintf("%.1f hrs", available_hours),
      overflow_mins,
      length(deferred_list),
      if (length(deferred_list) > 1) "s are" else " is"
    )
  } else if (unused_mins > 0) {
    warning_msg <- sprintf(
      "All %d active task%s fit comfortably into your available time! You have %d mins (%s) of buffer remaining.",
      nrow(active_df),
      if (nrow(active_df) > 1) "s" else "",
      unused_mins,
      sprintf("%.1f hrs", unused_mins / 60)
    )
  } else {
    warning_msg <- "Perfect schedule fit! Exactly fills your available time allocation."
  }
  
  list(
    available_hours = available_hours,
    available_mins = avail_mins,
    allocated_mins = cumulative_mins,
    unused_mins = unused_mins,
    total_workload_mins = total_workload_mins,
    overflow_mins = overflow_mins,
    fitting_tasks = fitting_list,
    deferred_tasks = deferred_list,
    warning_message = warning_msg
  )
}
