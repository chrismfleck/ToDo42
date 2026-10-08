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

  const LISTS = ["P", "AX", "TG", "B"];
  const LEGACY_LISTS = { Personal: "P", A: "P", C: "TG", D: "P" };

  function normalizeList(value) {
    if (LISTS.includes(value)) return value;
    if (LEGACY_LISTS[value]) return LEGACY_LISTS[value];
    return "P";
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
    const createdAt = (now || new Date()).toISOString();
    return {
      id: createId(),
      title: trimmed,
      due: due || null,
      status: "open",
      waitingOn: null,
      list: normalizeList(list),
      deleted: false,
      createdAt,
      updatedAt: createdAt,
    };
  }

  function assignList(task) {
    return {
      ...task,
      list: normalizeList(task.list),
      deleted: Boolean(task.deleted),
      updatedAt: task.updatedAt || task.createdAt || "1970-01-01T00:00:00.000Z",
    };
  }

  function tasksForList(tasks, list) {
    const name = normalizeList(list);
    return tasks.filter((task) => !task.deleted && normalizeList(task.list) === name);
  }

  function touch(task, now) {
    return { ...task, updatedAt: (now || new Date()).toISOString() };
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
    return tasks.filter((task) => !task.deleted && task.status !== "done").length;
  }

  function usesMarcConfirm(task) {
    return normalizeList(task.list) !== "P";
  }

  function toggleDone(task, now) {
    if (task.status === "waiting") {
      if (usesMarcConfirm(task)) return task;
      return touch({ ...task, status: "done", waitingOn: null }, now);
    }
    if (task.status === "done") {
      return touch({ ...task, status: "open", waitingOn: null }, now);
    }
    return touch({ ...task, status: "done", waitingOn: null }, now);
  }

  function markWaiting(task, name, now) {
    const who = name.trim();
    if (!who || task.status === "done") return task;
    return touch({ ...task, status: "waiting", waitingOn: who }, now);
  }

  function markConfirmed(task, now) {
    if (task.status !== "waiting") return task;
    return touch({ ...task, status: "done" }, now);
  }

  function updateTask(task, title, due, now) {
    const trimmed = title.trim();
    if (!trimmed) return task;
    return touch({ ...task, title: trimmed, due: due || null }, now);
  }

  function deleteTask(task, now) {
    return touch({ ...task, deleted: true }, now);
  }

  function mergeTasks(local, remote) {
    const byId = new Map();
    for (const task of [...local, ...remote]) {
      const next = assignList(task);
      const prev = byId.get(next.id);
      if (!prev || String(next.updatedAt) > String(prev.updatedAt)) byId.set(next.id, next);
    }
    return sortTasks([...byId.values()]);
  }

  function pendingPush(local, remote) {
    const remoteById = new Map(remote.map((task) => [task.id, task]));
    return local.filter((task) => {
      const other = remoteById.get(task.id);
      return !other || String(task.updatedAt) > String(other.updatedAt);
    });
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
        list: "P",
        deleted: false,
        createdAt: stamp,
        updatedAt: stamp,
      },
      {
        id: "seed-quote",
        title: "Email the quote",
        due: toISODate(today),
        status: "waiting",
        waitingOn: "Pat",
        list: "P",
        deleted: false,
        createdAt: stamp,
        updatedAt: stamp,
      },
      {
        id: "seed-key",
        title: "Pick up the spare key",
        due: toISODate(addDays(today, -1)),
        status: "done",
        waitingOn: "Pat",
        list: "P",
        deleted: false,
        createdAt: stamp,
        updatedAt: stamp,
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
    usesMarcConfirm,
    toggleDone,
    markWaiting,
    markConfirmed,
    updateTask,
    deleteTask,
    mergeTasks,
    pendingPush,
    formatDue,
    isOverdue,
    mailHref,
    seedTasks,
    replaceTask,
  };
});
