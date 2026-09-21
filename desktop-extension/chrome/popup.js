const API = "https://api.save4two.com/v1";

async function main() {
  const status = document.getElementById("status");
  const button = document.getElementById("send");
  const { deviceToken } = await chrome.storage.sync.get(["deviceToken"]);
  if (!deviceToken) {
    status.textContent = "Link this browser first (Options).";
    status.classList.add("err");
    button.disabled = true;
    return;
  }

  async function send() {
    button.disabled = true;
    status.textContent = "Sending…";
    status.classList.remove("err");
    try {
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      const url = tab?.url || "";
      if (!/^https?:\/\//i.test(url)) {
        throw new Error("Open a normal web page first.");
      }
      const res = await fetch(`${API}/inbox`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          deviceToken,
          url,
          title: tab.title || "",
          source: "chrome",
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || "send_failed");
      status.textContent = "Sent — open From desktop in Save 4 Two on iPhone.";
    } catch (err) {
      status.textContent = String(err.message || err);
      status.classList.add("err");
      button.disabled = false;
    }
  }

  button.addEventListener("click", send);
  status.textContent = "Ready — tap Save to send this page.";
}

main();
