(async function () {
  console.log('[Jira AD Autofill] Starting simple version');
  
  const defaults = {
    fieldId: "customfield_12345",
    fieldLabel: "AD Username", 
    manualUsername: "",
    debug: false,
    tries: 40,
    intervalMs: 700
  };
  
  let cfg = defaults;
  try {
    const stored = await chrome.storage.sync.get(Object.keys(defaults));
    cfg = Object.assign({}, defaults, stored);
  } catch (e) {
    console.log('[Jira AD Autofill] Storage error, using defaults');
  }
  
  const log = (...a) => { if (cfg.debug) console.log("[Jira AD Autofill]", ...a); };
  
  function findAllFields() {
    const fields = [];
    
    // 1. Try by ID first
    if (cfg.fieldId) {
      const selectors = [
        `[name="${cfg.fieldId}"]`,
        `#${CSS.escape(cfg.fieldId)}`,
        `#${CSS.escape(cfg.fieldId)}-field`,
        `[data-testid="${cfg.fieldId}"]`
      ];
      for (const s of selectors) {
        const el = document.querySelector(s);
        if (el) {
          log('Found field by ID:', s);
          fields.push({ element: el, method: 'ID: ' + s });
        }
      }
    }
    
    // 2. Try by label
    if (cfg.fieldLabel) {
      const labelText = cfg.fieldLabel.toLowerCase();
      const labels = Array.from(document.querySelectorAll('label,[role="label"]'));
      for (const hit of labels) {
        if ((hit.textContent || "").trim().toLowerCase().includes(labelText)) {
          let field = null;
          if (hit.htmlFor) {
            field = document.getElementById(hit.htmlFor);
          }
          if (!field) {
            const scope = hit.closest('div, section, li') || hit.parentElement || document;
            field = scope.querySelector('input, textarea');
          }
          if (field && !fields.some(f => f.element === field)) {
            log('Found field by label:', hit.textContent);
            fields.push({ element: field, method: 'Label: ' + hit.textContent });
          }
        }
      }
    }
    
    // 3. Try fallback patterns
    const fallbackSelectors = [
      'input[placeholder*="username" i]',
      'input[placeholder*="ad" i]',
      'input[id*="username" i]',
      'input[name*="username" i]'
    ];
    
    for (const sel of fallbackSelectors) {
      const elements = document.querySelectorAll(sel);
      elements.forEach(el => {
        if (!fields.some(f => f.element === el)) {
          log('Found field by fallback:', sel);
          fields.push({ element: el, method: 'Fallback: ' + sel });
        }
      });
    }
    
    return fields;
  }
  
  function findField() {
    const fields = findAllFields();
    return fields.length > 0 ? fields[0].element : null;
  }
  
  function fillField(field, username) {
    if (!field || !username) return false;
    try {
      // Skip disabled/readonly fields
      if (field.disabled || field.readOnly) {
        log('Field is disabled/readonly, skipping');
        return false;
      }
      const isEditable = field.hasAttribute("contenteditable") || field.getAttribute("contenteditable") === "true";
      const current = isEditable ? (field.textContent || "") : (field.value || "");
      // Don't overwrite existing values
      if (current && current.trim()) {
        log('Field already has value, skipping');
        return false; // return false to indicate no change performed
      }
      // Fill the field
      field.focus();
      if (isEditable) {
        field.textContent = username;
      } else {
        field.value = username;
      }
      // Trigger events
      field.dispatchEvent(new Event("input", { bubbles: true }));
      field.dispatchEvent(new Event("change", { bubbles: true }));
      log('Field filled with:', username);
      return true; // changed
    } catch (e) {
      log('Fill error:', e);
      return false;
    }
  }
  
  function fillAllFields(username) {
    if (!username) return false;
    const fields = findAllFields();
    log('Found', fields.length, 'potential fields');
    let changed = 0;
    let already = 0;
    fields.forEach((fieldInfo, index) => {
      const { element, method } = fieldInfo;
      const isEditable = element.hasAttribute && (element.hasAttribute("contenteditable") || element.getAttribute("contenteditable") === "true");
      const beforeVal = isEditable ? (element.textContent || "") : (element.value || "");
      const hadValue = !!(beforeVal && beforeVal.trim());
      log(`Attempting to fill field ${index + 1} (${method}):`, element.id || element.name || 'unnamed');
      const didChange = fillField(element, username);
      if (didChange) {
        changed++;
        // Highlight only when we actually changed the value
        element.style.backgroundColor = '#ffffcc';
        setTimeout(() => { element.style.backgroundColor = ''; }, 2000);
      } else if (hadValue) {
        already++;
      }
    });
    log(`Changed ${changed} field(s), ${already} already had value, out of ${fields.length}`);
    // Consider success if we either filled something or it was already filled
    return changed > 0 || already > 0;
  }
  
  async function getUsername() {
    // 1. Check manual username first (highest priority)
    if (cfg.manualUsername && cfg.manualUsername.trim()) {
      log('Using manual username (override):', cfg.manualUsername);
      return cfg.manualUsername.trim();
    }
    
    // 2. Try cached username
    if (cfg.cachedUsername && cfg.cachedUsername.trim()) {
      log('Using cached username:', cfg.cachedUsername);
      return cfg.cachedUsername;
    }
    
    // 3. Ask background to get AD username from local HTTP service
    try {
      log('Requesting AD username from local service (127.0.0.1:7777)...');
      const response = await new Promise(resolve => {
        chrome.runtime.sendMessage({ action: 'getADUsername' }, resolve);
      });
      
      if (response && response.success && response.username) {
        log('Got AD username:', response.username);
        // Cache it for future use
        try {
          await chrome.storage.sync.set({ 
            cachedUsername: response.username,
            cachedAt: Date.now()
          });
        } catch (e) {
          log('Cache save error:', e);
        }
        return response.username;
      } else {
        log('Local HTTP service failed:', response ? response.error : 'No response');
      }
    } catch (e) {
      log('Local HTTP service error:', e);
    }
    
    // 4. No username available
    log('No username available - checked manual:', cfg.manualUsername);
    log('Full config:', cfg);
    return null;
  }
  
  async function tryFill() {
    const fields = findAllFields();
    if (fields.length === 0) {
      log('No fields found');
      return false;
    }
    
    const username = await getUsername();
    if (!username) {
      log('No username available');
      return false;
    }
    
    return fillAllFields(username);
  }
  
  // Try immediately
  log('Initial try');
  tryFill().then(success => {
    if (success) {
      log('Success on first try');
    } else {
      // Retry with intervals
      let tries = 0;
      const maxTries = cfg.tries || 40;
      const interval = cfg.intervalMs || 700;
      
      const tick = async () => {
        tries++;
        log(`Try ${tries}/${maxTries}`);
        
        const success = await tryFill();
        if (success || tries >= maxTries) {
          log(tries >= maxTries ? 'Max tries reached' : 'Fill successful');
          return;
        }
        
        setTimeout(tick, interval);
      };
      
      setTimeout(tick, interval);
    }
  });
  
  // Watch for DOM changes
  const observer = new MutationObserver(() => {
    tryFill(); // This will be async but that's OK for observer
  });
  observer.observe(document.body, { childList: true, subtree: true });
  
  log('Setup complete');
})();
