const STORAGE_KEY = "tasks.phase1.v1";
const LIST_KEY = "tasks.phase1.list";
const logic = window.TaskLogic;

const listEl = document.querySelector("#list");
const countEl = document.querySelector("#count");
const backdrop = document.querySelector("#backdrop");
const sheet = document.querySelector("#sheet");
const addButton = document.querySelector("#add");
const tabs = [...document.querySelectorAll(".tab")];

let tasks = loadTasks();
let currentList = logic.normalizeList(localStorage.getItem(LIST_KEY));

tabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    currentList = logic.normalizeList(tab.dataset.list);
    localStorage.setItem(LIST_KEY, currentList);
    render();
  });
});

addButton.addEventListener("click", () => openAdd());
backdrop.addEventListener("click", (event) => {
  if (event.target === backdrop) closeSheet();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeSheet();
});
listEl.addEventListener("click", onListClick);

if (window.visualViewport) {
  const syncViewport = () => {
    const offset = Math.max(0, window.innerHeight - visualViewport.height - visualViewport.offsetTop);
    document.documentElement.style.setProperty("--vv-offset", `${offset}px`);
  };
  visualViewport.addEventListener("resize", syncViewport);
  visualViewport.addEventListener("scroll", syncViewport);
}

render();

function loadTasks() {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (raw == null) {
    const seeded = logic.seedTasks(new Date());
    localStorage.setItem(STORAGE_KEY, JSON.stringify(seeded));
    return seeded;
  }
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    const normalized = logic.sortTasks(parsed.map((task) => logic.assignList(task)));
    localStorage.setItem(STORAGE_KEY, JSON.stringify(normalized));
    return normalized;
  } catch {
    return [];
  }
}

function saveLocal() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
}

function save() {
  saveLocal();
  scheduleSync();
}

function render() {
  const visible = logic.tasksForList(tasks, currentList);
  const open = logic.openCount(visible);
  countEl.textContent = open === 1 ? "1 still open" : `${open} still open`;
  tabs.forEach((tab) => {
    const selected = tab.dataset.list === currentList;
    tab.classList.toggle("on", selected);
    tab.setAttribute("aria-pressed", selected ? "true" : "false");
  });
  listEl.replaceChildren();
  if (visible.length === 0) {
    const empty = document.createElement("p");
    empty.className = "empty";
    empty.textContent = `No tasks in ${currentList} yet. Tap + to add one with a date.`;
    listEl.append(empty);
    return;
  }
  for (const task of visible) listEl.append(renderTask(task));
}

function renderTask(task) {
  const today = new Date();
  const article = document.createElement("article");
  article.className = task.status === "done" ? "task done" : "task";
  article.dataset.id = task.id;

  const check = document.createElement("button");
  check.type = "button";
  check.className = task.status === "done" ? "check on" : "check";
  check.dataset.action = "toggle";
  check.setAttribute("aria-pressed", task.status === "done" ? "true" : "false");
  if (task.status === "waiting") {
    check.disabled = true;
    check.setAttribute("aria-label", `Waiting on ${task.waitingOn}. Still open.`);
  } else if (task.status === "done") {
    check.setAttribute("aria-label", `Mark ${task.title} not done`);
  } else {
    check.setAttribute("aria-label", `Mark ${task.title} done`);
  }

  const main = document.createElement("button");
  main.type = "button";
  main.className = "task-main";
  main.dataset.action = "edit";

  const title = document.createElement("span");
  title.className = "title";
  title.textContent = task.title;

  const meta = document.createElement("span");
  meta.className = logic.isOverdue(task, today) ? "meta overdue" : "meta";
  meta.textContent = logic.formatDue(task.due, today);

  main.append(title, meta);

  const body = document.createElement("div");
  body.className = "task-body";
  body.append(main);

  if (task.status === "waiting" && task.waitingOn) {
    const badge = document.createElement("span");
    badge.className = "badge wait";
    badge.textContent = `Waiting on ${task.waitingOn}`;
    main.append(badge);
    const confirm = document.createElement("button");
    confirm.type = "button";
    confirm.className = "confirm";
    confirm.dataset.action = "confirm";
    confirm.textContent = "Marc confirmed";
    body.append(confirm);
  } else if (task.status === "done" && task.waitingOn) {
    const badge = document.createElement("span");
    badge.className = "badge done";
    badge.textContent = "Confirmed";
    main.append(badge);
  }

  article.append(check, body);

  if (task.status === "open") {
    const email = document.createElement("button");
    email.type = "button";
    email.className = "email";
    email.dataset.action = "email";
    email.textContent = "Email team";
    article.append(email);
  }

  return article;
}

function onListClick(event) {
  const actionEl = event.target.closest("[data-action]");
  if (!actionEl) return;
  const article = actionEl.closest(".task");
  const task = tasks.find((item) => item.id === article.dataset.id);
  if (!task) return;
  const action = actionEl.dataset.action;
  if (action === "toggle") change(logic.toggleDone(task));
  if (action === "confirm") change(logic.markConfirmed(task));
  if (action === "edit") openEdit(task);
  if (action === "email") openEmail(task);
}

function change(next) {
  if (next === tasks.find((task) => task.id === next.id)) return;
  tasks = logic.replaceTask(tasks, next);
  save();
  render();
}

function openAdd() {
  const today = logic.toISODate(new Date());
  openSheet({
    title: "Add task",
    fields: [
      field("Title", "text", "title", "", "What needs doing?"),
      field("Due date", "date", "due", today),
    ],
    submit: "Save",
    onSubmit(data) {
      const created = logic.createTask(data.title, data.due, new Date(), currentList);
      if (!created) return false;
      tasks = logic.sortTasks([...tasks, created]);
      save();
      render();
      return true;
    },
  });
}

function openEdit(task) {
  openSheet({
    title: "Edit task",
    fields: [
      field("Title", "text", "title", task.title),
      field("Due date", "date", "due", task.due || ""),
    ],
    submit: "Save",
    deleteLabel: "Delete task",
    onSubmit(data) {
      change(logic.updateTask(task, data.title, data.due));
      return true;
    },
    onDelete() {
      change(logic.deleteTask(task));
    },
  });
}

function openEmail(task) {
  openSheet({
    title: "Email team",
    hint: `${task.title} stays open until you mark it confirmed.`,
    fields: [field("Name or email", "text", "who", "", "Pat")],
    submit: "Keep open and email",
    onSubmit(data) {
      const who = data.who.trim();
      if (!who) return false;
      const waiting = logic.markWaiting(task, who);
      tasks = logic.replaceTask(tasks, waiting);
      save();
      render();
      const link = document.createElement("a");
      link.href = logic.mailHref(waiting, who, new Date());
      link.click();
      return true;
    },
  });
}

function field(label, type, name, value, placeholder) {
  return { label, type, name, value, placeholder: placeholder || "" };
}

function openSheet(options) {
  sheet.replaceChildren();
  const heading = document.createElement("h2");
  heading.textContent = options.title;
  sheet.append(heading);

  if (options.hint) {
    const hint = document.createElement("p");
    hint.className = "hint";
    hint.textContent = options.hint;
    sheet.append(hint);
  }

  for (const item of options.fields) {
    const label = document.createElement("label");
    label.className = "field";
    const span = document.createElement("span");
    span.textContent = item.label;
    const input = document.createElement("input");
    input.type = item.type;
    input.name = item.name;
    input.value = item.value;
    input.placeholder = item.placeholder;
    input.required = true;
    input.autocomplete = "off";
    label.append(span, input);
    sheet.append(label);
  }

  const actions = document.createElement("div");
  actions.className = "sheet-actions";
  const cancel = document.createElement("button");
  cancel.type = "button";
  cancel.className = "secondary";
  cancel.textContent = "Cancel";
  cancel.addEventListener("click", closeSheet);
  const submit = document.createElement("button");
  submit.type = "submit";
  submit.className = "primary";
  submit.textContent = options.submit;
  actions.append(cancel, submit);
  sheet.append(actions);

  if (options.deleteLabel) {
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "delete";
    remove.textContent = options.deleteLabel;
    remove.addEventListener("click", () => {
      options.onDelete();
      closeSheet();
    });
    sheet.append(remove);
  }

  sheet.onsubmit = (event) => {
    event.preventDefault();
    const data = Object.fromEntries(new FormData(sheet));
    if (options.onSubmit(data) !== false) closeSheet();
  };

  backdrop.hidden = false;
  document.body.classList.add("sheet-open");
  const first = sheet.querySelector("input");
  if (first) first.focus();
}

function closeSheet() {
  backdrop.hidden = true;
  document.body.classList.remove("sheet-open");
  sheet.onsubmit = null;
}

const note = document.querySelector("#save-note");
let syncTimer = 0;
let syncing = false;
let syncAgain = false;

function scheduleSync() {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => {
    syncNow();
  }, 300);
}

function setNote(message) {
  if (note) note.textContent = message;
}

async function requestTasks(method, body) {
  const response = await fetch("/api/tasks", {
    method,
    headers: { "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) throw new Error("save failed");
  const payload = await response.json();
  return Array.isArray(payload.tasks) ? payload.tasks : [];
}

async function syncNow() {
  if (syncing) {
    syncAgain = true;
    return;
  }
  if (!navigator.onLine) {
    setNote("Saved on this phone. Cloudflare could not be reached just now.");
    return;
  }
  syncing = true;
  try {
    const remote = await requestTasks("GET");
    const outgoing = logic.pendingPush(tasks, remote);
    const confirmed = outgoing.length ? await requestTasks("PUT", { tasks: outgoing }) : remote;
    tasks = logic.mergeTasks(tasks, confirmed);
    saveLocal();
    render();
    setNote("Saved on this phone and in Cloudflare.");
  } catch {
    setNote("Saved on this phone. Cloudflare could not be reached just now.");
  } finally {
    syncing = false;
    if (syncAgain) {
      syncAgain = false;
      syncNow();
    }
  }
}

localStorage.removeItem("tasks.phase1.password");
window.addEventListener("online", () => syncNow());
syncNow();
