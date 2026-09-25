const API = "https://api.save4two.com/v1";

async function refreshStatus() {
  const status = document.getElementById("status");
  const { deviceToken, pairLabel } = await chrome.storage.sync.get(["deviceToken", "pairLabel"]);
  if (deviceToken) {
    status.textContent = `Linked${pairLabel ? ` to ${pairLabel}` : ""}.`;
    status.classList.remove("err");
  } else {
    status.textContent = "Not linked yet.";
  }
}

document.getElementById("link").addEventListener("click", async () => {
  const status = document.getElementById("status");
  const code = document.getElementById("code").value.replace(/\D/g, "");
  status.classList.remove("err");
  if (code.length !== 6) {
    status.textContent = "Enter the 6-digit code from the phone.";
    status.classList.add("err");
    return;
  }
  status.textContent = "Linking…";
  try {
    const res = await fetch(`${API}/link/complete`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        code,
        clientLabel: "Chrome",
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || "link_failed");
    await chrome.storage.sync.set({
      deviceToken: data.deviceToken,
      pairLabel: data.pairLabel || "",
    });
    document.getElementById("code").value = "";
    await refreshStatus();
  } catch (err) {
    status.textContent = String(err.message || err);
    status.classList.add("err");
  }
});

document.getElementById("unlink").addEventListener("click", async () => {
  const { deviceToken } = await chrome.storage.sync.get(["deviceToken"]);
  if (deviceToken) {
    try {
      await fetch(`${API}/unlink`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ deviceToken }),
      });
    } catch (_) {}
  }
  await chrome.storage.sync.remove(["deviceToken", "pairLabel"]);
  await refreshStatus();
});

refreshStatus();
