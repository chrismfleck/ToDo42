const fs = require("fs");
const path = require("path");

const dir = __dirname;
const css = fs.readFileSync(path.join(dir, "styles.css"), "utf8");
const logic = fs.readFileSync(path.join(dir, "logic.js"), "utf8").replaceAll("</script>", "<\\/script>");
const app = fs.readFileSync(path.join(dir, "app.js"), "utf8").replaceAll("</script>", "<\\/script>");

const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="apple-mobile-web-app-capable" content="yes" />
  <meta name="apple-mobile-web-app-status-bar-style" content="default" />
  <meta name="apple-mobile-web-app-title" content="Tasks" />
  <meta name="theme-color" content="#e8eef8" />
  <title>Tasks</title>
  <style>
${css}
  </style>
</head>
<body>
  <div class="app">
    <header class="top">
      <div>
        <h1>Tasks</h1>
        <p id="count">0 still open</p>
      </div>
      <button id="add" class="plus" type="button" aria-label="Add task">+</button>
    </header>
    <main id="list" class="list" aria-live="polite"></main>
    <p class="footnote">Saved on this phone. A task you email stays open until you mark it confirmed.</p>
  </div>

  <div id="backdrop" class="backdrop" hidden>
    <form id="sheet" class="sheet" novalidate></form>
  </div>

  <script>
${logic}
  </script>
  <script>
${app}
  </script>
</body>
</html>
`;

fs.writeFileSync(path.join(dir, "Tasks.html"), html);
console.log("wrote Tasks.html", Buffer.byteLength(html), "bytes");
