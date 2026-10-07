import { isValidTask, rowFromTask, taskFromRow } from "./records.mjs";

const HEADERS = { "content-type": "application/json; charset=utf-8" };
const SELECT_TASKS =
  "SELECT id, title, due, status, waiting_on, list, created_at, updated_at, deleted FROM tasks";
const UPSERT_TASK = `INSERT INTO tasks
  (id, title, due, status, waiting_on, list, created_at, updated_at, deleted)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ON CONFLICT(id) DO UPDATE SET
    title = excluded.title,
    due = excluded.due,
    status = excluded.status,
    waiting_on = excluded.waiting_on,
    list = excluded.list,
    updated_at = excluded.updated_at,
    deleted = excluded.deleted
  WHERE excluded.updated_at >= tasks.updated_at`;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: HEADERS });
}

async function readTasks(env) {
  const { results } = await env.DB.prepare(SELECT_TASKS).all();
  return (results || []).map(taskFromRow);
}

export async function handleTasksRequest(request, env) {
  if (request.method === "GET") return json({ tasks: await readTasks(env) });
  if (request.method !== "PUT") return json({ error: "method" }, 405);

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid" }, 400);
  }
  const incoming = Array.isArray(body.tasks) ? body.tasks.slice(0, 2000) : [];
  const statements = [];
  for (const task of incoming) {
    if (!isValidTask(task)) continue;
    const row = rowFromTask(task);
    statements.push(
      env.DB.prepare(UPSERT_TASK).bind(
        row.id,
        row.title,
        row.due,
        row.status,
        row.waiting_on,
        row.list,
        row.created_at,
        row.updated_at,
        row.deleted
      )
    );
  }
  if (statements.length) await env.DB.batch(statements);
  return json({ tasks: await readTasks(env) });
}
