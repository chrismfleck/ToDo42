const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createTask,
  assignList,
  tasksForList,
  normalizeList,
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
  toISODate,
} = require("./logic");

const today = new Date(2026, 9, 7);

test("seed shows an open task, a waiting task, and a confirmed task", () => {
  const tasks = seedTasks(today);
  assert.deepEqual(
    tasks.map((task) => [task.title, task.status]),
    [
      ["Email the quote", "waiting"],
      ["Replace the garage sensor", "open"],
      ["Pick up the spare key", "done"],
    ]
  );
  assert.equal(openCount(tasks), 2);
});

test("adding a task keeps done items at the bottom", () => {
  const created = createTask("Call the plumber", "2026-10-08", today);
  assert.equal(created.status, "open");
  const tasks = sortTasks([...seedTasks(today), created]);
  assert.equal(tasks.at(-1).status, "done");
  assert.equal(tasks[0].title, "Email the quote");
});

test("a blank title is not saved", () => {
  assert.equal(createTask("   ", "2026-10-08", today), null);
});

test("checking an open task finishes it, and checking again reopens it", () => {
  const open = createTask("Call the plumber", "2026-10-08", today);
  const done = toggleDone(open);
  assert.equal(done.status, "done");
  assert.equal(toggleDone(done).status, "open");
});

test("a waiting task stays open until it is confirmed", () => {
  const open = createTask("Email the quote", "2026-10-07", today);
  const waiting = markWaiting(open, " Pat ");
  assert.equal(waiting.status, "waiting");
  assert.equal(waiting.waitingOn, "Pat");
  assert.equal(toggleDone(waiting).status, "waiting");
  const confirmed = markConfirmed(waiting);
  assert.equal(confirmed.status, "done");
  assert.equal(confirmed.waitingOn, "Pat");
  assert.equal(markConfirmed(open).status, "open");
});

test("dates read as today, tomorrow, yesterday, or a weekday", () => {
  assert.equal(formatDue("2026-10-07", today), "Due today");
  assert.equal(formatDue("2026-10-08", today), "Due tomorrow");
  assert.equal(formatDue("2026-10-06", today), "Due yesterday");
  assert.equal(formatDue("2026-10-09", today), "Due Fri, Oct 9");
  assert.equal(formatDue(null, today), "No date");
});

test("only unfinished tasks with a past date are overdue", () => {
  const open = { due: "2026-10-06", status: "open" };
  const done = { due: "2026-10-06", status: "done" };
  const later = { due: toISODate(today), status: "waiting" };
  assert.equal(isOverdue(open, today), true);
  assert.equal(isOverdue(done, today), false);
  assert.equal(isOverdue(later, today), false);
});

test("each list keeps its own tasks, and older tasks land in P", () => {
  const seeded = seedTasks(today);
  assert.ok(seeded.every((task) => task.list === "P"));
  assert.equal(tasksForList(seeded, "B").length, 0);
  const inB = createTask("Call the plumber", "2026-10-08", today, "B");
  assert.equal(inB.list, "B");
  const saved = [
    ...seeded,
    inB,
    assignList({ title: "From Personal", list: "Personal" }),
    assignList({ title: "From C", list: "C" }),
    assignList({ title: "Old task", list: "nope" }),
  ];
  assert.equal(tasksForList(saved, "P").length, 5);
  assert.deepEqual(
    tasksForList(saved, "B").map((task) => task.title),
    ["Call the plumber"]
  );
  assert.deepEqual(
    tasksForList(saved, "TG").map((task) => task.title),
    ["From C"]
  );
  assert.equal(normalizeList("AX"), "AX");
  assert.equal(normalizeList("Personal"), "P");
  assert.equal(normalizeList(""), "P");
});

test("edit keeps the title and date, and mail uses an address when one is given", () => {
  const task = createTask("Email the quote", "2026-10-07", today);
  const edited = updateTask(task, " Send the quote ", "2026-10-10");
  assert.equal(edited.title, "Send the quote");
  assert.equal(edited.due, "2026-10-10");
  assert.equal(updateTask(task, "  ", "2026-10-10").title, "Email the quote");
  const href = mailHref(task, "pat@example.com", today);
  assert.ok(href.startsWith("mailto:pat%40example.com?"));
  assert.ok(href.includes(encodeURIComponent("Email the quote")));
});
