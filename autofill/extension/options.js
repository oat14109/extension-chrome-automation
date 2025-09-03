const defaults = { 
  fieldId: "customfield_12345", 
  fieldLabel: "AD Username", 
  manualUsername: "", 
  debug: true, 
  tries: 40, 
  intervalMs: 700,
  cachedUsername: "",
  cachedAt: 0
};

async function load(){
  const cur = Object.assign({}, defaults, await chrome.storage.sync.get(Object.keys(defaults)));
  for (const k of Object.keys(defaults)) {
    const el = document.getElementById(k);
    if (!el) continue;
    if (el.type === "checkbox") el.checked = !!cur[k]; else el.value = cur[k];
  }
  const extIdEl = document.getElementById("extId");
  if (extIdEl) extIdEl.value = chrome.runtime.id || "";
}

async function save(){
  const data = {};
  for (const k of Object.keys(defaults)) {
    const el = document.getElementById(k);
    if (!el) continue;
    if (el.type === "number") data[k] = Number(el.value);
    else if (el.type === "checkbox") data[k] = !!el.checked;
    else data[k] = el.value ?? defaults[k];
  }
  await chrome.storage.sync.set(data);
  const s = document.getElementById("status"); 
  s.textContent = "Saved"; 
  setTimeout(()=>s.textContent="", 1200);
}

document.getElementById("save").addEventListener("click", save);

document.getElementById("testHost").addEventListener("click", async () => {
  const s = document.getElementById("status");
  s.textContent = "Testing HTTP service (http://127.0.0.1:7777/whoami)...";
  try {
    const response = await new Promise(resolve => {
      chrome.runtime.sendMessage({ action: 'getADUsername' }, resolve);
    });
    if (response && response.success && response.username) {
      s.textContent = `HTTP OK: ${response.username}`;
      // Update manual field with AD username
      const manualField = document.getElementById("manualUsername");
      if (manualField) manualField.value = response.username;
    } else {
      s.textContent = "HTTP failed: " + (response ? response.error : "No response");
    }
  } catch (e) {
    s.textContent = "HTTP error: " + e.message;
  }
  setTimeout(()=>s.textContent="", 3000);
});

document.getElementById("testManual").addEventListener("click", async () => {
  const s = document.getElementById("status");
  const manualField = document.getElementById("manualUsername");
  
  if (!manualField || !manualField.value.trim()) {
    s.textContent = "Please enter a manual username first";
    setTimeout(()=>s.textContent="", 2000);
    return;
  }
  
  s.textContent = "Testing manual username...";
  
  // Save current settings first
  await save();
  
  // Test the configuration
  try {
    const stored = await chrome.storage.sync.get(['manualUsername']);
    if (stored.manualUsername && stored.manualUsername.trim()) {
      s.textContent = `Manual username saved: ${stored.manualUsername}`;
    } else {
      s.textContent = "Error: Manual username not saved properly";
    }
  } catch (e) {
    s.textContent = "Error testing manual username: " + e.message;
  }
  
  setTimeout(()=>s.textContent="", 3000);
});

document.getElementById("clearCache").addEventListener("click", async () => {
  const s = document.getElementById("status");
  s.textContent = "Clearing cache...";
  
  try {
    await chrome.storage.sync.set({ 
      cachedUsername: "",
      cachedAt: 0
    });
    s.textContent = "Cache cleared";
  } catch (e) {
    s.textContent = "Error clearing cache: " + e.message;
  }
  
  setTimeout(()=>s.textContent="", 2000);
});

document.getElementById("testSimple").addEventListener("click", async () => {
  const s = document.getElementById("status");
  s.textContent = "Testing simple fill...";
  
  // Reload current tab to trigger content script
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab && tab.id) {
      await chrome.tabs.reload(tab.id);
      s.textContent = "Tab reloaded - check for autofill";
    } else {
      s.textContent = "No active tab";
    }
  } catch (e) {
    s.textContent = "Reload failed: " + e.message;
  }
  
  setTimeout(()=>s.textContent="", 3000);
});

load();
