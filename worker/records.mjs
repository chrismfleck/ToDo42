const LISTS = new Set(["P", "AX", "TG", "B"]);
const STATUSES = new Set(["open", "waiting", "done"]);

export function isValidTask(task) {
  return Boolean(
    task &&
      typeof task.id === "string" &&
      task.id &&
      typeof task.title === "string" &&
      task.title.trim() &&
      STATUSES.has(task.status) &&
      LISTS.has(task.list) &&
      typeof task.updatedAt === "string" &&
      task.updatedAt
  );
}

export function rowFromTask(task) {
  return {
    id: task.id,
    title: task.title.trim(),
    due: task.due || null,
    status: task.status,
    waiting_on: task.waitingOn || null,
    list: task.list,
    created_at: task.createdAt || task.updatedAt,
    updated_at: task.updatedAt,
    deleted: task.deleted ? 1 : 0,
  };
}

export function taskFromRow(row) {
  return {
    id: row.id,
    title: row.title,
    due: row.due || null,
    status: row.status,
    waitingOn: row.waiting_on || null,
    list: row.list,
    deleted: row.deleted === 1 || row.deleted === true,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
