(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.TaskLogic = factory();
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }

  function addDays(date, days) {
    const next = startOfDay(date);
    next.setDate(next.getDate() + days);
    return next;
  }

  function toISODate(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, "0");
    const d = String(date.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  function parseISODate(iso) {
    const [y, m, d] = iso.split("-").map(Number);
    return new Date(y, m - 1, d);
  }

  const LISTS = ["Personal", "AX", "TG"];
  const LEGACY_LISTS = { A: "Personal", B: "AX", C: "TG", D: "Personal" };

  function normalizeList(value) {
    if (LISTS.includes(value)) return value;
    if (LEGACY_LISTS[value]) return LEGACY_LISTS[value];
    return "Personal";
  }

  function createId() {
    if (globalThis.crypto && typeof crypto.randomUUID === "function") {
      return crypto.randomUUID();
    }
    return `task-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }

  function createTask(title, due, now, list) {
    const trimmed = title.trim();
    if (!trimmed) return null;
    return {
      id: createId(),
      title: trimmed,
      due: due || null,
      status: "open",
      waitingOn: null,
      list: normalizeList(list),
      createdAt: (now || new Date()).toISOString(),
    };
  }

  function assignList(task) {
    return { ...task, list: normalizeList(task.list) };
  }

  function tasksForList(tasks, list) {
    const name = normalizeList(list);
    return tasks.filter((task) => normalizeList(task.list) === name);
  }

  function dueTime(task) {
    return task.due ? parseISODate(task.due).getTime() : Number.POSITIVE_INFINITY;
  }

  function sortTasks(tasks) {
    return tasks.slice().sort((a, b) => {
      const aDone = a.status === "done" ? 1 : 0;
      const bDone = b.status === "done" ? 1 : 0;
      if (aDone !== bDone) return aDone - bDone;
      const byDue = dueTime(a) - dueTime(b);
      if (byDue !== 0) return byDue;
      return a.createdAt < b.createdAt ? -1 : a.createdAt > b.createdAt ? 1 : 0;
    });
  }

  function openCount(tasks) {
    return tasks.filter((task) => task.status !== "done").length;
  }

  function toggleDone(task) {
    if (task.status === "waiting") return task;
    if (task.status === "done") {
      return { ...task, status: "open", waitingOn: null };
    }
    return { ...task, status: "done", waitingOn: null };
  }

  function markWaiting(task, name) {
    const who = name.trim();
    if (!who || task.status === "done") return task;
    return { ...task, status: "waiting", waitingOn: who };
  }

  function markConfirmed(task) {
    if (task.status !== "waiting") return task;
    return { ...task, status: "done" };
  }

  function updateTask(task, title, due) {
    const trimmed = title.trim();
    if (!trimmed) return task;
    return { ...task, title: trimmed, due: due || null };
  }

  function formatDue(iso, today) {
    if (!iso) return "No date";
    const date = parseISODate(iso);
    const start = startOfDay(today);
    const diff = Math.round((date.getTime() - start.getTime()) / 86400000);
    if (diff === 0) return "Due today";
    if (diff === 1) return "Due tomorrow";
    if (diff === -1) return "Due yesterday";
    const pretty = date.toLocaleDateString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
    });
    return `Due ${pretty}`;
  }

  function isOverdue(task, today) {
    if (!task.due || task.status === "done") return false;
    return parseISODate(task.due).getTime() < startOfDay(today).getTime();
  }

  function mailHref(task, name, today) {
    const who = name.trim();
    const to = who.includes("@") ? who : "";
    const subject = `Can you finish this? ${task.title}`;
    const due = formatDue(task.due, today);
    const body = [
      task.title,
      due,
      "",
      "This stays open until it is marked confirmed.",
    ].join("\n");
    return `mailto:${encodeURIComponent(to)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  }

  function seedTasks(today) {
    const stamp = startOfDay(today).toISOString();
    return sortTasks([
      {
        id: "seed-garage",
        title: "Replace the garage sensor",
        due: toISODate(addDays(today, 2)),
        status: "open",
        waitingOn: null,
        list: "Personal",
        createdAt: stamp,
      },
      {
        id: "seed-quote",
        title: "Email the quote",
        due: toISODate(today),
        status: "waiting",
        waitingOn: "Pat",
        list: "Personal",
        createdAt: stamp,
      },
      {
        id: "seed-key",
        title: "Pick up the spare key",
        due: toISODate(addDays(today, -1)),
        status: "done",
        waitingOn: "Pat",
        list: "Personal",
        createdAt: stamp,
      },
    ]);
  }

  function replaceTask(tasks, next) {
    return sortTasks(tasks.map((task) => (task.id === next.id ? next : task)));
  }

  return {
    addDays,
    toISODate,
    parseISODate,
    LISTS,
    normalizeList,
    createTask,
    assignList,
    tasksForList,
    sortTasks,
    openCount,
    toggleDone,
    markWaiting,
    markConfirmed,
    updateTask,
    formatDue,
    isOverdue,
    mailHref,
    seedTasks,
    replaceTask,
  };
});
