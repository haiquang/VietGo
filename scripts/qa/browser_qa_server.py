import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

RESULTS = []
LOCK = threading.Lock()

HTML_PAGE = r"""<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8" />
  <title>VietGo Browser QA Lab</title>
  <style>
    :root {
      color-scheme: dark light;
      --bg: #111318;
      --card: #1a1d24;
      --border: #2c3240;
      --text: #eef1f7;
      --muted: #9aa4b8;
      --accent: #3b82f6;
      --pass: #22c55e;
      --fail: #ef4444;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 20px;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.45;
    }
    h1 { font-size: 20px; margin: 0 0 6px; }
    .subtitle { color: var(--muted); font-size: 13px; margin-bottom: 16px; }
    .grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
      margin-bottom: 18px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 12px 14px;
      position: relative;
    }
    .card-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 8px;
    }
    .card-title { font-size: 13px; font-weight: 600; }
    .badge {
      font-size: 11px;
      padding: 2px 7px;
      border-radius: 999px;
      background: #252b37;
      color: var(--muted);
    }
    input[type="text"], textarea, [contenteditable="true"] {
      width: 100%;
      background: #0d0f13;
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 7px;
      padding: 8px 10px;
      font-size: 14px;
      font-family: inherit;
      outline: none;
    }
    input[type="text"]:focus, textarea:focus, [contenteditable="true"]:focus {
      border-color: var(--accent);
    }
    textarea { min-height: 84px; resize: vertical; }
    #rich-editor, #mention-popup-editor, #formatted-editor {
      min-height: 84px;
      white-space: pre-wrap;
      overflow-y: auto;
    }
    .form-row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
    }
    #formatted-editor b { color: #fde68a; }
    #formatted-editor code {
      background: #1e293b;
      color: #7dd3fc;
      padding: 1px 5px;
      border-radius: 4px;
      font-size: 12px;
    }
    #mention-popup {
      display: none;
      margin-top: 6px;
      padding: 6px 8px;
      background: #141923;
      border: 1px solid #334155;
      border-radius: 6px;
      font-size: 12px;
      color: #93c5fd;
    }
    #chat-messages {
      min-height: 56px;
      max-height: 110px;
      overflow-y: auto;
      display: flex;
      flex-direction: column;
      gap: 4px;
      margin-bottom: 8px;
      padding: 6px;
      background: #0d0f13;
      border: 1px solid var(--border);
      border-radius: 7px;
    }
    .chat-bubble {
      background: #1f293d;
      padding: 4px 8px;
      border-radius: 6px;
      font-size: 13px;
      align-self: flex-start;
    }
    .panel-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 10px;
    }
    button {
      background: #252b37;
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 5px 10px;
      font-size: 12px;
      cursor: pointer;
    }
    button:hover { border-color: var(--accent); }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
    }
    th, td {
      border-bottom: 1px solid var(--border);
      text-align: left;
      padding: 6px 8px;
      vertical-align: top;
    }
    th { color: var(--muted); font-weight: 600; }
    .status-PASS { color: var(--pass); font-weight: 700; }
    .status-FAIL { color: var(--fail); font-weight: 700; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 11px; }
  </style>
</head>
<body>
  <h1>VietGo Browser QA Lab</h1>
  <div class="subtitle">Multi-surface Vietnamese IME &amp; cumulative regression verification across 8 web surfaces.</div>

  <div class="grid">
    <div class="card">
      <div class="card-header">
        <span class="card-title">1. Browser Omnibox (Inline Autocomplete)</span>
        <span class="badge" id="omnibox-badge">suggestion: none</span>
      </div>
      <input id="omnibox-input" type="text" autocomplete="off" spellcheck="false" placeholder="Gõ thử: ddaf nawngx, thuwr nghieemj..." />
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">2. Chat Box (Enter Submit)</span>
        <span class="badge" id="chat-count">0 msgs</span>
      </div>
      <div id="chat-messages"></div>
      <input id="chat-input" type="text" autocomplete="off" spellcheck="false" placeholder="Nhập tin nhắn rồi nhấn Enter..." />
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">3. Markdown / Prose Textarea</span>
        <span class="badge" id="textarea-count">0 chars</span>
      </div>
      <textarea id="markdown-textarea" spellcheck="false" placeholder="Đoạn văn báo chí, tài chính, code / đường dẫn..."></textarea>
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">4. ContentEditable Rich Editor</span>
        <span class="badge" id="rich-events">events: 0</span>
      </div>
      <div id="rich-editor" contenteditable="true" spellcheck="false"></div>
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">5. React-Style Controlled Input</span>
        <span class="badge" id="react-renders">renders: 0</span>
      </div>
      <input id="react-controlled-input" type="text" autocomplete="off" spellcheck="false" placeholder="Controlled state sync on every keystroke..." />
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">6. Mention / Emoji Popup Editor</span>
        <span class="badge" id="mention-badge">popup: hidden</span>
      </div>
      <div id="mention-popup-editor" contenteditable="true" spellcheck="false"></div>
      <div id="mention-popup">Gợi ý: @nguoi_dung • :tada: • :check:</div>
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">7. Multi-Field Tab Form</span>
        <span class="badge" id="form-badge">tab: ready</span>
      </div>
      <div class="form-row">
        <input id="form-field-1" type="text" autocomplete="off" spellcheck="false" placeholder="Field 1 (gõ rồi Tab)..." />
        <input id="form-field-2" type="text" autocomplete="off" spellcheck="false" placeholder="Field 2 (sau Tab)..." />
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <span class="card-title">8. Formatted Inline ContentEditable</span>
        <span class="badge" id="formatted-badge">tags: b + code</span>
      </div>
      <div id="formatted-editor" contenteditable="true" spellcheck="false"><b>[Bold]</b> <code>inline_code</code> </div>
    </div>
  </div>

  <div class="card" id="qa-results-panel">
    <div class="panel-header">
      <span class="card-title">QA Execution Results (<span id="qa-summary">0 cases</span>)</span>
      <div style="display:flex;gap:8px;">
        <button id="refresh-results-btn" onclick="loadResults()">Refresh Results</button>
        <button id="clear-results-btn" onclick="clearResults()">Clear</button>
      </div>
    </div>
    <table>
      <thead>
        <tr>
          <th>Case</th>
          <th>Selector</th>
          <th>Speed</th>
          <th>WPM</th>
          <th>Duration</th>
          <th>Status</th>
          <th>Actual Output</th>
        </tr>
      </thead>
      <tbody id="qa-results-body"></tbody>
    </table>
  </div>

  <script>
    const suggestions = [
      "đà nẵng việt nam",
      "đánh giá sản phẩm",
      "thử nghiệm hệ thống",
      "người dùng mới nhất",
      "của bạn tại đây nhé",
      "làm việc từ xa"
    ];

    const omnibox = document.getElementById("omnibox-input");
    const omniboxBadge = document.getElementById("omnibox-badge");
    omnibox.addEventListener("input", (e) => {
      const val = omnibox.value;
      if (e.inputType === "deleteContentBackward" || e.inputType === "deleteContentForward") {
        omniboxBadge.textContent = "suggestion: deleted";
        return;
      }
      if (val.includes("\u202F") || val.endsWith(" ") || val.length < 2) {
        omniboxBadge.textContent = "suggestion: none";
        return;
      }
      const atEnd = omnibox.selectionStart === val.length && omnibox.selectionEnd === val.length;
      if (!atEnd) return;
      const match = suggestions.find((s) => s.startsWith(val) && s.length > val.length);
      if (match) {
        omnibox.value = match;
        omnibox.setSelectionRange(val.length, match.length);
        omniboxBadge.textContent = "suggestion: " + match;
      } else {
        omniboxBadge.textContent = "suggestion: none";
      }
    });

    const textarea = document.getElementById("markdown-textarea");
    const textareaCount = document.getElementById("textarea-count");
    textarea.addEventListener("input", () => {
      textareaCount.textContent = textarea.value.length + " chars";
    });

    const richEditor = document.getElementById("rich-editor");
    const richBadge = document.getElementById("rich-events");
    let richEventCounter = 0;
    richEditor.addEventListener("input", () => {
      richEventCounter += 1;
      richBadge.textContent = "events: " + richEventCounter + " | len: " + richEditor.textContent.length;
    });

    const reactInput = document.getElementById("react-controlled-input");
    const reactBadge = document.getElementById("react-renders");
    let stateText = "";
    let reactRenderCount = 0;
    reactInput.addEventListener("input", () => {
      stateText = reactInput.value;
      reactRenderCount += 1;
      const s = reactInput.selectionStart;
      const e = reactInput.selectionEnd;
      reactInput.value = stateText;
      try { reactInput.setSelectionRange(s, e); } catch (_) {}
      reactBadge.textContent = "renders: " + reactRenderCount;
    });

    const mentionEditor = document.getElementById("mention-popup-editor");
    const mentionPopup = document.getElementById("mention-popup");
    const mentionBadge = document.getElementById("mention-badge");
    function updateMentionPopup() {
      const txt = mentionEditor.textContent || "";
      const activeMatch = txt.match(/(?:^|\s)([@:][\w\u00C0-\u1EF9]*)$/);
      if (activeMatch) {
        mentionPopup.style.display = "block";
        mentionPopup.textContent = "Gợi ý cho " + activeMatch[1] + ": @người_dùng • :tada: • :check:";
        mentionBadge.textContent = "popup: " + activeMatch[1];
      } else {
        mentionPopup.style.display = "none";
        mentionBadge.textContent = "popup: hidden";
      }
    }
    mentionEditor.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        mentionPopup.style.display = "none";
        mentionBadge.textContent = "popup: dismissed (Escape)";
        return;
      }
      updateMentionPopup();
    });
    mentionEditor.addEventListener("input", () => updateMentionPopup());

    const formField1 = document.getElementById("form-field-1");
    const formField2 = document.getElementById("form-field-2");
    const formBadge = document.getElementById("form-badge");
    function updateFormBadge() {
      formBadge.textContent = `f1:${formField1.value.length} | f2:${formField2.value.length}`;
    }
    formField1.addEventListener("input", updateFormBadge);
    formField2.addEventListener("input", updateFormBadge);

    const formattedEditor = document.getElementById("formatted-editor");
    const formattedBadge = document.getElementById("formatted-badge");
    formattedEditor.addEventListener("input", () => {
      const bCount = formattedEditor.querySelectorAll("b").length;
      const codeCount = formattedEditor.querySelectorAll("code").length;
      formattedBadge.textContent = `b:${bCount} code:${codeCount} len:${formattedEditor.textContent.length}`;
    });
    window.qaFocusFormattedEnd = () => {
      formattedEditor.focus();
      const range = document.createRange();
      range.selectNodeContents(formattedEditor);
      range.collapse(false);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      return document.activeElement === formattedEditor;
    };

    const chatInput = document.getElementById("chat-input");
    const chatMessages = document.getElementById("chat-messages");
    const chatCount = document.getElementById("chat-count");
    chatInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.isComposing) {
        e.preventDefault();
        const text = chatInput.value;
        if (text.length > 0) {
          const div = document.createElement("div");
          div.className = "chat-bubble";
          div.textContent = text;
          chatMessages.appendChild(div);
          chatCount.textContent = chatMessages.children.length + " msgs";
        }
        chatInput.value = "";
      }
    });

    function escapeHtml(str) {
      return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
    }

    async function loadResults() {
      const res = await fetch("/api/results");
      const rows = await res.json();
      const tbody = document.getElementById("qa-results-body");
      tbody.innerHTML = rows.map((r) => `
        <tr>
          <td><strong>${escapeHtml(r.name)}</strong></td>
          <td><code>${escapeHtml(r.selector)}</code></td>
          <td>${escapeHtml(r.speed)}</td>
          <td>~${escapeHtml(r.wpm)}</td>
          <td>${escapeHtml(r.durationMs)} ms</td>
          <td class="status-${escapeHtml(r.status)}">${escapeHtml(r.status)}</td>
          <td>${escapeHtml(r.actual)}${r.status === "FAIL" ? "<br><small style='color:#f87171'>Expected: " + escapeHtml(r.expected) + "</small>" : ""}</td>
        </tr>
      `).join("");
      const passed = rows.filter((r) => r.status === "PASS").length;
      document.getElementById("qa-summary").textContent = `${passed}/${rows.length} PASS`;
    }

    async function clearResults() {
      await fetch("/api/clear", { method: "POST" });
      await loadResults();
    }

    window.qaResetAll = () => {
      omnibox.value = "";
      omniboxBadge.textContent = "suggestion: none";
      textarea.value = "";
      textareaCount.textContent = "0 chars";
      richEditor.textContent = "";
      richEventCounter = 0;
      richBadge.textContent = "events: 0";
      stateText = "";
      reactInput.value = "";
      reactRenderCount = 0;
      reactBadge.textContent = "renders: 0";
      mentionEditor.textContent = "";
      mentionPopup.style.display = "none";
      mentionBadge.textContent = "popup: hidden";
      chatInput.value = "";
      chatMessages.innerHTML = "";
      chatCount.textContent = "0 msgs";
      formField1.value = "";
      formField2.value = "";
      formBadge.textContent = "tab: ready";
      formattedEditor.innerHTML = "<b>[Bold]</b> <code>inline_code</code> ";
      formattedBadge.textContent = "tags: b + code";
    };

    window.addEventListener("DOMContentLoaded", loadResults);
  </script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def _send_json(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/?"):
            body = HTML_PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/api/health":
            self._send_json(200, {"ok": True})
        elif self.path == "/api/results":
            with LOCK:
                snapshot = list(RESULTS)
            self._send_json(200, snapshot)
        else:
            self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length > 0 else b""
        if self.path == "/api/results":
            item = json.loads(raw.decode("utf-8"))
            with LOCK:
                RESULTS.append(item)
            self._send_json(200, {"ok": True})
        elif self.path == "/api/clear":
            with LOCK:
                RESULTS.clear()
            self._send_json(200, {"ok": True})
        else:
            self.send_error(404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VietGo Browser QA Lab HTTP Server")
    parser.add_argument("--port", type=int, default=8765, help="Port to bind (default: 8765)")
    args = parser.parse_args()

    server = HTTPServer(("127.0.0.1", args.port), Handler)
    print(f"VietGo Browser QA Lab listening on http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()
