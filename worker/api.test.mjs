import test from "node:test";
import assert from "node:assert/strict";
import { handleTasksRequest } from "./api.mjs";

function createDb(seed = []) {
  const rows = new Map(seed.map((row) => [row.id, row]));
  function statement(sql) {
    const stmt = {
      args: [],
      bind(...args) {
        stmt.args = args;
        return stmt;
      },
      async all() {
        return { results: [...rows.values()] };
      },
      async run() {
        const [id, title, due, status, waiting, list, created, updated, deleted] = stmt.args;
        const prev = rows.get(id);
        if (!prev || updated >= prev.updated_at) {
          rows.set(id, {
            id,
            title,
            due,
            status,
            waiting_on: waiting,
            list,
            created_at: created,
            updated_at: updated,
            deleted,
          });
        }
        return { success: true };
      },
    };
    return stmt;
  }
  return {
    prepare: statement,
    batch: (stmts) => Promise.all(stmts.map((stmt) => stmt.run())),
  };
}

function call(method, env, body) {
  return handleTasksRequest(
    new Request("https://tasks.example/api/tasks", {
      method,
      headers: { "content-type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    }),
    env
  );
}

const sample = {
  id: "1",
  title: "Call",
  due: "2026-10-09",
  status: "open",
  waitingOn: null,
  list: "P",
  deleted: false,
  createdAt: "2026-10-07T00:00:00.000Z",
  updatedAt: "2026-10-07T00:00:00.000Z",
};

test("tasks can be read with no password", async () => {
  const response = await call("GET", { DB: createDb() });
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).tasks, []);
});

test("a saved task comes back, and an older edit does not overwrite it", async () => {
  const env = { DB: createDb() };
  const saved = await call("PUT", env, { tasks: [sample] });
  assert.equal(saved.status, 200);
  const body = await saved.json();
  assert.equal(body.tasks[0].title, "Call");

  const older = { ...sample, title: "Old", updatedAt: "2026-10-06T00:00:00.000Z" };
  const again = await call("PUT", env, { tasks: [older] });
  const after = await again.json();
  assert.equal(after.tasks[0].title, "Call");

  const listed = await call("GET", env);
  assert.equal((await listed.json()).tasks.length, 1);
});
