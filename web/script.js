/**
 * Smart Task Priority Assistant — Interactive Frontend Controller
 * Connects with R Plumber backend, handles task CRUD, search & filtering,
 * explainable priority scoring rendering, and daily session time-allocation.
 */

// Global Application State
const state = {
  tasks: [],
  totalTasksCount: 0,
  matchedCount: 0,
  recommendations: null,
  timePlan: null,
  availableHours: 2.5,
  activeFilters: {
    q: '',
    status: '',
    importance: '',
    category: '',
    sortBy: 'priority',
    sortDir: 'desc'
  },
  selectedTask: null,
  isEditing: false,
  pendingDeleteId: null,
  backendConnected: false
};

const API_BASE = '/api';

// DOM Element References
const elements = {
  backendStatus: document.getElementById('backend-status'),
  btnToggleTimePlanner: document.getElementById('btn-toggle-time-planner'),
  timePlannerSection: document.getElementById('time-planner-section'),
  btnOpenCreateModal: document.getElementById('btn-open-create-modal'),

  // Executive Metrics Bar
  statActiveCount: document.getElementById('stat-active-count'),
  statCompletedCount: document.getElementById('stat-completed-count'),
  statTotalWorkload: document.getElementById('stat-total-workload'),
  statTotalMins: document.getElementById('stat-total-mins'),
  statUrgentCount: document.getElementById('stat-urgent-count'),
  statOverdueCount: document.getElementById('stat-overdue-count'),

  // Hero Recommendation Card
  recommendationHero: document.getElementById('recommendation-hero'),
  heroTierBadge: document.getElementById('hero-tier-badge'),
  heroStatusPill: document.getElementById('hero-status-pill'),
  heroTitle: document.getElementById('hero-title'),
  heroDesc: document.getElementById('hero-desc'),
  heroRationale: document.getElementById('hero-rationale'),
  heroFormulaText: document.getElementById('hero-formula-text'),
  heroDuration: document.getElementById('hero-duration'),
  heroDeadline: document.getElementById('hero-deadline'),
  heroCategory: document.getElementById('hero-category'),
  btnHeroToggleDone: document.getElementById('btn-hero-toggle-done'),

  // Time Planner
  inputAvailableHours: document.getElementById('input-available-hours'),
  quickHourChips: document.querySelectorAll('.btn-hour-chip'),
  planAllocatedText: document.getElementById('plan-allocated-text'),
  planSlackText: document.getElementById('plan-slack-text'),
  meterFillAllocated: document.getElementById('meter-fill-allocated'),
  meterFillOverflow: document.getElementById('meter-fill-overflow'),
  plannerWarningText: document.getElementById('planner-warning-text'),
  fittingTasksList: document.getElementById('fitting-tasks-list'),
  deferredTasksList: document.getElementById('deferred-tasks-list'),
  fittingCount: document.getElementById('fitting-count'),
  deferredCount: document.getElementById('deferred-count'),

  // Toolbar
  searchInput: document.getElementById('search-input'),
  btnClearSearch: document.getElementById('btn-clear-search'),
  filterStatus: document.getElementById('filter-status'),
  filterImportance: document.getElementById('filter-importance'),
  filterCategory: document.getElementById('filter-category'),
  filterSort: document.getElementById('filter-sort'),
  btnResetFilters: document.getElementById('btn-reset-filters'),
  resultsCountText: document.getElementById('results-count-text'),
  activeFilterChips: document.getElementById('active-filter-chips'),

  // Task List & Empty State
  tasksList: document.getElementById('tasks-list'),
  emptyState: document.getElementById('empty-state'),
  btnEmptyClear: document.getElementById('btn-empty-clear'),
  btnEmptyCreate: document.getElementById('btn-empty-create'),

  // Modals
  modalTaskForm: document.getElementById('modal-task-form'),
  formModalTitle: document.getElementById('form-modal-title'),
  taskForm: document.getElementById('task-form'),
  formTaskId: document.getElementById('form-task-id'),
  inputTaskTitle: document.getElementById('input-task-title'),
  inputTaskDesc: document.getElementById('input-task-desc'),
  inputTaskCategory: document.getElementById('input-task-category'),
  inputTaskStatus: document.getElementById('input-task-status'),
  inputTaskImportance: document.getElementById('input-task-importance'),
  inputTaskDuration: document.getElementById('input-task-duration'),
  inputTaskDeadline: document.getElementById('input-task-deadline'),
  durationHoursPreview: document.getElementById('duration-hours-preview'),
  formErrorBanner: document.getElementById('form-error-banner'),
  categoryDatalist: document.getElementById('category-datalist'),

  modalDeleteConfirm: document.getElementById('modal-delete-confirm'),
  deleteTaskTitlePreview: document.getElementById('delete-task-title-preview'),
  btnConfirmDelete: document.getElementById('btn-confirm-delete'),

  toastContainer: document.getElementById('toast-container')
};

// ==============================================================================
// 1. Initialization
// ==============================================================================

document.addEventListener('DOMContentLoaded', () => {
  initEventListeners();
  checkBackendHealth();
  refreshAllData();
});

async function checkBackendHealth() {
  try {
    const res = await fetch(`${API_BASE}/health`);
    if (res.ok) {
      const data = await res.json();
      state.backendConnected = true;
      elements.backendStatus.classList.remove('error');
      elements.backendStatus.classList.add('connected');
      elements.backendStatus.querySelector('.status-label').textContent = `R Plumber (${unwrap(data.tasks_count, 0)} tasks)`;
    } else {
      throw new Error(`HTTP ${res.status}`);
    }
  } catch (err) {
    state.backendConnected = false;
    elements.backendStatus.classList.remove('connected');
    elements.backendStatus.classList.add('error');
    elements.backendStatus.querySelector('.status-label').textContent = 'R Offline (Start R/main.R)';
    showToast('Cannot connect to R Plumber server. Ensure R/main.R is running on port 8000.', 'error');
  }
}

async function refreshAllData() {
  await Promise.all([
    fetchRecommendations(),
    fetchTasks(),
    fetchTimePlan()
  ]);
}

// ==============================================================================
// 2. Data Fetching via R API
// ==============================================================================

async function fetchRecommendations() {
  try {
    const res = await fetch(`${API_BASE}/recommendations`);
    if (!res.ok) return;
    const recs = await res.json();
    state.recommendations = recs;
    renderMetrics(recs);
    renderHeroRecommendation(recs.top_recommendation);
    populateCategoryDatalist(recs.category_breakdown);
    populateCategorySelect(recs.category_breakdown);
  } catch (err) {
    console.warn('Failed to load recommendations:', err);
  }
}

async function fetchTasks() {
  const params = new URLSearchParams();
  if (state.activeFilters.q) params.set('q', state.activeFilters.q);
  if (state.activeFilters.status) params.set('status', state.activeFilters.status);
  if (state.activeFilters.importance) params.set('importance', state.activeFilters.importance);
  if (state.activeFilters.category) params.set('category', state.activeFilters.category);
  if (state.activeFilters.sortBy) params.set('sort_by', state.activeFilters.sortBy);
  if (state.activeFilters.sortDir) params.set('sort_dir', state.activeFilters.sortDir);

  try {
    const res = await fetch(`${API_BASE}/tasks?${params.toString()}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    
    const data = await res.json();
    state.tasks = (data.tasks || []).map(normalizeTask);
    state.totalTasksCount = unwrap(data.total_tasks, 0);
    state.matchedCount = unwrap(data.matched_count, 0);

    renderTasksList();
    renderFilterMeta();
  } catch (err) {
    console.error('Failed to load tasks from R backend:', err);
    elements.resultsCountText.textContent = 'Error connecting to R backend.';
    renderTasksList();
  }
}

async function fetchTimePlan() {
  try {
    const hours = state.availableHours || 2.5;
    const res = await fetch(`${API_BASE}/plan-time?hours=${encodeURIComponent(hours)}`);
    if (!res.ok) return;
    const plan = await res.json();
    state.timePlan = plan;
    renderTimePlan(plan);
  } catch (err) {
    console.warn('Failed to plan available time:', err);
  }
}

// ==============================================================================
// 3. UI Rendering
// ==============================================================================

function renderMetrics(recs) {
  if (!recs) return;
  elements.statActiveCount.textContent = unwrap(recs.active_tasks_count, 0);
  elements.statCompletedCount.textContent = `/ ${unwrap(recs.completed_tasks_count, 0)} done`;
  elements.statTotalWorkload.textContent = unwrap(recs.total_workload_hours, '0.0 hrs');
  elements.statTotalMins.textContent = `(${unwrap(recs.total_workload_mins, 0)} mins)`;
  elements.statUrgentCount.textContent = unwrap(recs.urgent_count, 0);
  elements.statOverdueCount.textContent = unwrap(recs.overdue_count, 0);
}

function renderHeroRecommendation(top) {
  if (!top) {
    elements.recommendationHero.style.display = 'none';
    return;
  }

  elements.recommendationHero.style.display = 'block';
  top = normalizeTask(top);

  elements.heroTitle.textContent = top.title;
  elements.heroDesc.textContent = top.description || 'No description provided.';
  elements.heroRationale.textContent = top.recommendation_rationale || top.explanation;
  elements.heroFormulaText.textContent = top.explanation;
  elements.heroDuration.textContent = formatDuration(top.duration_mins);
  elements.heroCategory.textContent = top.category;

  // Deadline display
  if (top.deadline) {
    elements.heroDeadline.textContent = `${top.deadline} (${top.deadline_status})`;
    elements.heroDeadline.className = top.is_overdue ? 'hero-stat-val text-danger' : 'hero-stat-val';
  } else {
    elements.heroDeadline.textContent = 'No deadline (Paced)';
    elements.heroDeadline.className = 'hero-stat-val';
  }

  // Tier pill
  elements.heroTierBadge.textContent = `${top.priority_tier} • ${top.priority_score}/100`;
  elements.heroTierBadge.className = `tier-pill ${top.priority_tier.toLowerCase()}`;
  elements.heroStatusPill.textContent = top.status;

  elements.btnHeroToggleDone.onclick = async () => {
    await toggleTaskCompletion(top.id);
  };
}

function renderTimePlan(plan) {
  if (!plan) return;

  const availMins = unwrap(plan.available_mins, 0);
  const allocMins = unwrap(plan.allocated_mins, 0);
  const unusedMins = unwrap(plan.unused_mins, 0);
  const overflowMins = unwrap(plan.overflow_mins, 0);

  elements.planAllocatedText.textContent = `${allocMins} / ${availMins} mins`;
  elements.planSlackText.textContent = `${unusedMins} mins unused buffer`;
  elements.plannerWarningText.textContent = unwrap(plan.warning_message, '');

  // Progress Bar
  const allocPct = availMins > 0 ? Math.min(100, (allocMins / availMins) * 100) : 0;
  elements.meterFillAllocated.style.width = `${allocPct}%`;

  if (overflowMins > 0) {
    const overflowPct = availMins > 0 ? Math.min(30, (overflowMins / availMins) * 20) : 0;
    elements.meterFillOverflow.style.width = `${overflowPct}%`;
  } else {
    elements.meterFillOverflow.style.width = '0%';
  }

  // Fitting Tasks
  elements.fittingTasksList.innerHTML = '';
  const fitting = (plan.fitting_tasks || []).map(normalizeTask);
  elements.fittingCount.textContent = fitting.length;

  if (fitting.length === 0) {
    elements.fittingTasksList.innerHTML = '<div class="text-muted" style="padding: 12px; font-size: 0.8rem;">No active tasks fit into this duration.</div>';
  } else {
    fitting.forEach(t => {
      const row = document.createElement('div');
      row.className = 'planner-item-row';
      row.innerHTML = `
        <div class="planner-item-info">
          <span class="planner-item-title">${escapeHtml(t.title)}</span>
          <span class="planner-item-sub">${escapeHtml(t.category)} &bull; Cumulative: ${t.cumulative_mins || t.duration_mins} mins</span>
        </div>
        <span class="planner-item-dur">${t.duration_mins}m</span>
      `;
      elements.fittingTasksList.appendChild(row);
    });
  }

  // Deferred Tasks
  elements.deferredTasksList.innerHTML = '';
  const deferred = (plan.deferred_tasks || []).map(normalizeTask);
  elements.deferredCount.textContent = deferred.length;

  if (deferred.length === 0) {
    elements.deferredTasksList.innerHTML = '<div class="text-muted" style="padding: 12px; font-size: 0.8rem;">All active tasks fit into today\'s session!</div>';
  } else {
    deferred.forEach(t => {
      const row = document.createElement('div');
      row.className = 'planner-item-row';
      row.innerHTML = `
        <div class="planner-item-info">
          <span class="planner-item-title">${escapeHtml(t.title)}</span>
          <span class="planner-item-sub">Needs ${t.duration_mins} mins &bull; Exceeds session window</span>
        </div>
        <span class="planner-item-dur" style="background:#fee2e2; color:#b91c1c;">+${t.duration_mins}m</span>
      `;
      elements.deferredTasksList.appendChild(row);
    });
  }
}

function renderTasksList() {
  elements.tasksList.innerHTML = '';

  if (state.tasks.length === 0) {
    elements.emptyState.style.display = 'block';
    elements.tasksList.style.display = 'none';
    return;
  }

  elements.emptyState.style.display = 'none';
  elements.tasksList.style.display = 'flex';

  state.tasks.forEach((task, index) => {
    const card = createTaskCard(task, index + 1);
    elements.tasksList.appendChild(card);
  });
}

function createTaskCard(task, rankIndex) {
  const card = document.createElement('article');
  card.className = `task-card ${task.status === 'Completed' ? 'completed' : ''}`;
  card.dataset.id = task.id;

  const isCompleted = task.status === 'Completed';

  // Deadline Badge Styling
  let deadlineHtml = '';
  if (task.deadline) {
    let badgeClass = 'deadline-badge';
    if (task.is_overdue) badgeClass += ' overdue';
    else if (task.deadline_status === 'Due Today') badgeClass += ' due-today';
    deadlineHtml = `<span class="${badgeClass}">Due ${escapeHtml(task.deadline)} (${escapeHtml(task.deadline_status)})</span>`;
  } else {
    deadlineHtml = `<span class="deadline-badge">No Deadline</span>`;
  }

  // Priority Tier
  const tierClass = task.priority_tier.toLowerCase();
  const tierHtml = `<span class="tier-pill ${tierClass}">${escapeHtml(task.priority_tier)} &bull; ${task.priority_score}/100</span>`;

  card.innerHTML = `
    <div class="task-card-header">
      <div class="task-header-left">
        <span class="rank-badge">#${rankIndex}</span>
        <span class="task-category-pill">${escapeHtml(task.category)}</span>
      </div>
      <div class="task-header-right">
        ${deadlineHtml}
        ${tierHtml}
      </div>
    </div>

    <div class="task-card-main">
      <div class="task-checkbox-wrapper">
        <input
          type="checkbox"
          class="task-checkbox"
          ${isCompleted ? 'checked' : ''}
          aria-label="Toggle task completion"
        >
      </div>
      <div class="task-content-wrapper">
        <h3 class="task-title-text">${escapeHtml(task.title)}</h3>
        ${task.description ? `<p class="task-desc-text">${escapeHtml(task.description)}</p>` : ''}

        <div class="task-explanation-box">
          <span class="explanation-tag">Why ranked here:</span>
          <span>${escapeHtml(task.explanation)}</span>
        </div>
      </div>
    </div>

    <div class="task-card-footer">
      <div class="footer-meta-left">
        <span class="duration-pill">&bull; ${formatDuration(task.duration_mins)}</span>
        <span class="status-badge">&bull; Status: ${escapeHtml(task.status)}</span>
        <span class="updated-time">&bull; Updated: ${escapeHtml(task.updated_at)}</span>
      </div>
      <div class="footer-actions">
        <button class="btn-icon-action btn-edit" type="button" title="Edit task" aria-label="Edit task">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 20h9"></path>
            <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path>
          </svg>
        </button>
        <button class="btn-icon-action delete btn-delete" type="button" title="Delete task" aria-label="Delete task">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="3 6 5 6 21 6"></polyline>
            <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
          </svg>
        </button>
      </div>
    </div>
  `;

  // Attach card events
  const checkbox = card.querySelector('.task-checkbox');
  checkbox.addEventListener('change', async () => {
    await toggleTaskCompletion(task.id);
  });

  const btnEdit = card.querySelector('.btn-edit');
  btnEdit.addEventListener('click', () => {
    openEditModal(task);
  });

  const btnDelete = card.querySelector('.btn-delete');
  btnDelete.addEventListener('click', () => {
    promptDelete(task);
  });

  return card;
}

function renderFilterMeta() {
  const total = state.totalTasksCount;
  const matched = state.matchedCount;

  if (total === 0) {
    elements.resultsCountText.textContent = 'No tasks recorded yet.';
  } else if (hasActiveFilters()) {
    elements.resultsCountText.innerHTML = `Showing <strong>${matched}</strong> of <strong>${total}</strong> tasks matching filters.`;
  } else {
    elements.resultsCountText.innerHTML = `Showing all <strong>${total}</strong> tasks ordered by priority.`;
  }

  // Active chips
  elements.activeFilterChips.innerHTML = '';
  const f = state.activeFilters;

  if (f.q) {
    addActiveChip(`Search: "${f.q}"`, () => {
      state.activeFilters.q = '';
      elements.searchInput.value = '';
      elements.btnClearSearch.style.display = 'none';
      fetchTasks();
    });
  }
  if (f.status) {
    addActiveChip(`Status: ${f.status}`, () => {
      state.activeFilters.status = '';
      elements.filterStatus.value = '';
      fetchTasks();
    });
  }
  if (f.importance) {
    addActiveChip(`Importance: ${f.importance}`, () => {
      state.activeFilters.importance = '';
      elements.filterImportance.value = '';
      fetchTasks();
    });
  }
  if (f.category) {
    addActiveChip(`Category: ${f.category}`, () => {
      state.activeFilters.category = '';
      elements.filterCategory.value = '';
      fetchTasks();
    });
  }
}

function addActiveChip(label, onRemove) {
  const chip = document.createElement('span');
  chip.className = 'active-chip';
  chip.innerHTML = `${escapeHtml(label)} <button type="button" aria-label="Remove filter">&times;</button>`;
  chip.querySelector('button').addEventListener('click', onRemove);
  elements.activeFilterChips.appendChild(chip);
}

function hasActiveFilters() {
  const f = state.activeFilters;
  return Boolean(f.q || f.status || f.importance || f.category);
}

function populateCategoryDatalist(catBreakdown) {
  if (!catBreakdown) return;
  elements.categoryDatalist.innerHTML = '';
  Object.keys(catBreakdown).forEach(cat => {
    const opt = document.createElement('option');
    opt.value = cat;
    elements.categoryDatalist.appendChild(opt);
  });
}

function populateCategorySelect(catBreakdown) {
  if (!catBreakdown) return;
  const current = state.activeFilters.category;
  elements.filterCategory.innerHTML = '<option value="">All Categories</option>';
  Object.keys(catBreakdown).sort().forEach(cat => {
    const opt = document.createElement('option');
    opt.value = cat;
    opt.textContent = `${cat} (${catBreakdown[cat]})`;
    if (cat === current) opt.selected = true;
    elements.filterCategory.appendChild(opt);
  });
}

// ==============================================================================
// 4. CRUD Operations & Status Toggling
// ==============================================================================

function openCreateModal() {
  state.isEditing = false;
  elements.formModalTitle.textContent = 'New Task';
  elements.formTaskId.value = '';
  elements.taskForm.reset();
  elements.inputTaskStatus.value = 'Pending';
  elements.inputTaskImportance.value = 'Medium';
  elements.inputTaskDuration.value = '45';
  updateDurationPreview();
  elements.formErrorBanner.style.display = 'none';

  openModal(elements.modalTaskForm);
  setTimeout(() => elements.inputTaskTitle.focus(), 100);
}

function openEditModal(task) {
  state.isEditing = true;
  elements.formModalTitle.textContent = 'Edit Task';
  elements.formTaskId.value = task.id;
  elements.inputTaskTitle.value = task.title;
  elements.inputTaskDesc.value = task.description || '';
  elements.inputTaskCategory.value = task.category;
  elements.inputTaskStatus.value = task.status;
  elements.inputTaskImportance.value = task.importance;
  elements.inputTaskDuration.value = task.duration_mins;
  elements.inputTaskDeadline.value = task.deadline || '';
  updateDurationPreview();
  elements.formErrorBanner.style.display = 'none';

  openModal(elements.modalTaskForm);
  setTimeout(() => elements.inputTaskTitle.focus(), 100);
}

elements.inputTaskDuration.addEventListener('input', updateDurationPreview);

function updateDurationPreview() {
  const mins = parseInt(elements.inputTaskDuration.value, 10);
  if (!isNaN(mins) && mins > 0) {
    const hrs = (mins / 60).toFixed(1);
    elements.durationHoursPreview.textContent = `${hrs} hrs (${mins} mins)`;
  } else {
    elements.durationHoursPreview.textContent = '--';
  }
}

elements.taskForm.addEventListener('submit', async (e) => {
  e.preventDefault();

  const title = elements.inputTaskTitle.value.trim();
  const description = elements.inputTaskDesc.value.trim();
  const category = elements.inputTaskCategory.value.trim();
  const status = elements.inputTaskStatus.value.trim();
  const importance = elements.inputTaskImportance.value.trim();
  const duration_mins = parseInt(elements.inputTaskDuration.value, 10);
  const deadline = elements.inputTaskDeadline.value.trim();
  const taskId = elements.formTaskId.value.trim();

  // Basic Validation
  const errors = [];
  if (!title) errors.push('Task title is required.');
  if (title.length > 150) errors.push('Title must be 150 characters or fewer.');
  if (!category) errors.push('Category is required.');
  if (isNaN(duration_mins) || duration_mins <= 0) errors.push('Estimated duration must be positive.');
  if (duration_mins > 1440) errors.push('Duration cannot exceed 24 hours (1440 mins).');

  if (errors.length > 0) {
    elements.formErrorBanner.textContent = errors.join(' ');
    elements.formErrorBanner.style.display = 'block';
    return;
  }

  elements.formErrorBanner.style.display = 'none';

  const payload = {
    title,
    description,
    category,
    status,
    importance,
    duration_mins,
    deadline
  };

  const isEdit = state.isEditing && Boolean(taskId);
  const endpoint = isEdit ? `${API_BASE}/tasks/${encodeURIComponent(taskId)}` : `${API_BASE}/tasks`;
  const method = isEdit ? 'PUT' : 'POST';

  try {
    const res = await fetch(endpoint, {
      method,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await res.json();
    if (!res.ok || !data.success) {
      const msg = (data.errors && data.errors.join(' ')) || 'Failed to save task.';
      elements.formErrorBanner.textContent = msg;
      elements.formErrorBanner.style.display = 'block';
      return;
    }

    closeModal(elements.modalTaskForm);
    showToast(isEdit ? 'Task updated successfully.' : 'New task added and ranked.', 'success');
    await refreshAllData();
  } catch (err) {
    console.error('Error saving task:', err);
    elements.formErrorBanner.textContent = 'Server connection error. Ensure R/main.R is running.';
    elements.formErrorBanner.style.display = 'block';
  }
});

async function toggleTaskCompletion(taskId) {
  try {
    const res = await fetch(`${API_BASE}/tasks/${encodeURIComponent(taskId)}/toggle`, {
      method: 'POST'
    });
    const data = await res.json();
    if (res.ok && data.success) {
      showToast(`Task marked as ${data.new_status}.`, 'success');
      await refreshAllData();
    } else {
      showToast('Failed to toggle status.', 'error');
    }
  } catch (err) {
    console.error('Toggle status error:', err);
    showToast('Failed to connect to R server.', 'error');
  }
}

function promptDelete(task) {
  state.pendingDeleteId = task.id;
  elements.deleteTaskTitlePreview.textContent = `"${task.title}" (${task.category})`;
  openModal(elements.modalDeleteConfirm);
}

elements.btnConfirmDelete.addEventListener('click', async () => {
  if (!state.pendingDeleteId) return;

  const id = state.pendingDeleteId;
  try {
    const res = await fetch(`${API_BASE}/tasks/${encodeURIComponent(id)}`, {
      method: 'DELETE'
    });
    const data = await res.json();
    if (res.ok && data.success) {
      closeModal(elements.modalDeleteConfirm);
      showToast('Task removed from CSV.', 'success');
      state.pendingDeleteId = null;
      await refreshAllData();
    } else {
      throw new Error((data.errors && data.errors.join(' ')) || 'Delete failed');
    }
  } catch (err) {
    console.error('Delete error:', err);
    showToast(`Error deleting task: ${err.message}`, 'error');
  }
});

// ==============================================================================
// 5. Event Listeners & Filter Controls
// ==============================================================================

function initEventListeners() {
  // Search input debounced
  let debounceTimer = null;
  elements.searchInput.addEventListener('input', (e) => {
    const val = e.target.value;
    elements.btnClearSearch.style.display = val.length > 0 ? 'block' : 'none';

    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      state.activeFilters.q = val.trim();
      fetchTasks();
    }, 250);
  });

  elements.btnClearSearch.addEventListener('click', () => {
    elements.searchInput.value = '';
    elements.btnClearSearch.style.display = 'none';
    state.activeFilters.q = '';
    fetchTasks();
    elements.searchInput.focus();
  });

  // Filter selects
  elements.filterStatus.addEventListener('change', (e) => {
    state.activeFilters.status = e.target.value;
    fetchTasks();
  });

  elements.filterImportance.addEventListener('change', (e) => {
    state.activeFilters.importance = e.target.value;
    fetchTasks();
  });

  elements.filterCategory.addEventListener('change', (e) => {
    state.activeFilters.category = e.target.value;
    fetchTasks();
  });

  elements.filterSort.addEventListener('change', (e) => {
    const [sortBy, sortDir] = e.target.value.split(':');
    state.activeFilters.sortBy = sortBy;
    state.activeFilters.sortDir = sortDir;
    fetchTasks();
  });

  // Reset filters
  elements.btnResetFilters.addEventListener('click', resetAllFilters);
  elements.btnEmptyClear.addEventListener('click', resetAllFilters);

  // New task buttons
  elements.btnOpenCreateModal.addEventListener('click', openCreateModal);
  elements.btnEmptyCreate.addEventListener('click', openCreateModal);

  // Toggle Time Planner Card
  elements.btnToggleTimePlanner.addEventListener('click', () => {
    const isCollapsed = elements.timePlannerSection.classList.toggle('collapsed');
    elements.btnToggleTimePlanner.setAttribute('aria-expanded', !isCollapsed);
  });

  // Available hours input
  elements.inputAvailableHours.addEventListener('change', (e) => {
    const val = parseFloat(e.target.value);
    if (!isNaN(val) && val > 0) {
      state.availableHours = val;
      updateHourChipActive(val);
      fetchTimePlan();
    }
  });

  // Quick hours chips
  elements.quickHourChips.forEach(chip => {
    chip.addEventListener('click', () => {
      const hrs = parseFloat(chip.dataset.hours);
      state.availableHours = hrs;
      elements.inputAvailableHours.value = hrs;
      updateHourChipActive(hrs);
      fetchTimePlan();
    });
  });

  // Modal dismiss buttons
  document.querySelectorAll('[data-close-modal]').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const modal = e.target.closest('.modal-backdrop');
      if (modal) closeModal(modal);
    });
  });

  document.querySelectorAll('.modal-backdrop').forEach(modal => {
    modal.addEventListener('click', (e) => {
      if (e.target === modal) closeModal(modal);
    });
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      const activeModal = document.querySelector('.modal-backdrop.active');
      if (activeModal) closeModal(activeModal);
    }
  });
}

function updateHourChipActive(hrs) {
  elements.quickHourChips.forEach(chip => {
    if (parseFloat(chip.dataset.hours) === hrs) {
      chip.classList.add('active');
    } else {
      chip.classList.remove('active');
    }
  });
}

function resetAllFilters() {
  state.activeFilters.q = '';
  state.activeFilters.status = '';
  state.activeFilters.importance = '';
  state.activeFilters.category = '';
  state.activeFilters.sortBy = 'priority';
  state.activeFilters.sortDir = 'desc';

  elements.searchInput.value = '';
  elements.btnClearSearch.style.display = 'none';
  elements.filterStatus.value = '';
  elements.filterImportance.value = '';
  elements.filterCategory.value = '';
  elements.filterSort.value = 'priority:desc';

  fetchTasks();
}

// ==============================================================================
// 6. Helpers & Utilities
// ==============================================================================

function normalizeTask(raw) {
  if (!raw) return null;
  return {
    id: unwrap(raw.id),
    title: unwrap(raw.title),
    description: unwrap(raw.description),
    category: unwrap(raw.category, 'General'),
    deadline: unwrap(raw.deadline),
    importance: unwrap(raw.importance, 'Medium'),
    duration_mins: parseInt(unwrap(raw.duration_mins, 30), 10) || 30,
    status: unwrap(raw.status, 'Pending'),
    created_at: unwrap(raw.created_at),
    updated_at: unwrap(raw.updated_at),
    priority_score: parseInt(unwrap(raw.priority_score, 0), 10) || 0,
    priority_tier: unwrap(raw.priority_tier, 'Medium'),
    deadline_status: unwrap(raw.deadline_status, 'Upcoming'),
    is_overdue: Boolean(unwrap(raw.is_overdue, false)),
    explanation: unwrap(raw.explanation, ''),
    recommendation_rationale: unwrap(raw.recommendation_rationale, ''),
    cumulative_mins: parseInt(unwrap(raw.cumulative_mins, 0), 10),
    remaining_after_task: parseInt(unwrap(raw.remaining_after_task, 0), 10),
    available_slack: parseInt(unwrap(raw.available_slack, 0), 10)
  };
}

function unwrap(val, fallback = '') {
  if (val === null || val === undefined) return fallback;
  if (Array.isArray(val)) return val.length > 0 ? val[0] : fallback;
  return val;
}

function formatDuration(mins) {
  mins = parseInt(mins, 10);
  if (isNaN(mins) || mins <= 0) return '0 mins';
  const hrs = (mins / 60).toFixed(1);
  return `${mins} mins (${hrs} hr${parseFloat(hrs) === 1.0 ? '' : 's'})`;
}

function openModal(modalEl) {
  modalEl.classList.add('active');
  modalEl.setAttribute('aria-hidden', 'false');
  document.body.style.overflow = 'hidden';
}

function closeModal(modalEl) {
  modalEl.classList.remove('active');
  modalEl.setAttribute('aria-hidden', 'true');
  document.body.style.overflow = '';
}

function showToast(message, type = 'info') {
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.textContent = message;
  elements.toastContainer.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(6px)';
    toast.style.transition = 'all 200ms ease';
    setTimeout(() => toast.remove(), 200);
  }, 3200);
}

function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
