import { handleTasksRequest } from "./api.mjs";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/tasks") return handleTasksRequest(request, env);
    return env.ASSETS.fetch(request);
  },
};
