// Background script: fetch username from local whoami HTTP service (service.py)
console.log('Background script loaded (HTTP mode via service.py)');

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  console.log('Background: Received message:', request);

  if (request && request.action === 'getADUsername') {
    const url = 'http://127.0.0.1:7777/whoami';
    console.log('Background: Fetching from', url);

    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 5000);

      fetch(url, { method: 'GET', headers: { 'Accept': 'application/json' }, signal: controller.signal })
        .then(async (resp) => {
          clearTimeout(timer);
          if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
          const data = await resp.json().catch(() => ({}));
          const active = data && data.active_console_user && data.active_console_user.username;
          const proc = data && data.process_user && data.process_user.username;
          const username = (active && String(active).trim()) || (proc && String(proc).trim()) || '';
          if (username) {
            console.log('Background: Got username from whoami service:', username);
            sendResponse({ success: true, username });
          } else {
            console.log('Background: whoami service returned no username', data);
            sendResponse({ success: false, error: 'No username from whoami service' });
          }
        })
        .catch((err) => {
          clearTimeout(timer);
          console.log('Background: HTTP error:', err && err.message ? err.message : String(err));
          sendResponse({ success: false, error: (err && err.message) || 'HTTP error' });
        });
    } catch (error) {
      console.log('Background: Exception during fetch:', error);
      sendResponse({ success: false, error: 'Exception: ' + (error && error.message ? error.message : String(error)) });
    }

    return true; // Keep message channel open for async response
  }

  console.log('Background: Unknown message action:', request && request.action);
  sendResponse({ success: false, error: 'Unknown action: ' + (request && request.action) });
});

// ------------------------------------------------------------
// Legacy native messaging implementation (commented out)
// ------------------------------------------------------------
/*
// Simple background script for native messaging only
console.log('Background script loaded and ready!');

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  console.log('Background: Received message:', request);
  
  if (request.action === 'getADUsername') {
    console.log('Background: Requesting native host...');
    
    try {
      // Add timeout for native messaging
      const timeout = setTimeout(() => {
        console.log('Background: Native host timeout');
        sendResponse({ success: false, error: 'Native host timeout after 5 seconds' });
      }, 5000);
      
      chrome.runtime.sendNativeMessage('com.company.adwhoami', { cmd: 'whoami' }, (response) => {
        clearTimeout(timeout);
        
        if (chrome.runtime.lastError) {
          console.log('Background: Native host error:', chrome.runtime.lastError.message);
          sendResponse({ success: false, error: chrome.runtime.lastError.message });
        } else if (response && response.ok && response.username) {
          console.log('Background: Native host success:', response.username);
          sendResponse({ success: true, username: response.username });
        } else {
          console.log('Background: Native host unexpected response:', response);
          sendResponse({ success: false, error: 'Invalid response from native host', response: response });
        }
      });
    } catch (error) {
      console.log('Background: Exception calling native host:', error);
      sendResponse({ success: false, error: 'Exception: ' + error.message });
    }
    
    return true; // Keep message channel open for async response
  }
  
  // Handle other messages
  console.log('Background: Unknown message action:', request.action);
  sendResponse({ success: false, error: 'Unknown action: ' + request.action });
});
*/
