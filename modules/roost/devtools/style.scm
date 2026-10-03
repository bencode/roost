;; The panel's stylesheet. It lives in the panel's shadow root, so it neither reaches
;; the application nor is reached by the application's CSS.
(define-module (roost devtools style)
  #:pure
  #:export (stylesheet)
  #:use-module (scheme base))

(define stylesheet "
:host { all: initial; }
* { box-sizing: border-box; }

.theme {
  --bg: #0d1117; --bar: #161b22; --fg: #c9d1d9; --muted: #8b949e; --line: #30363d;
  --accent: #7ee787; --value: #79c0ff; --error: #ff7b72;
  --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}
@media (prefers-color-scheme: light) {
  .theme {
    --bg: #fbfbf8; --bar: #f0f0eb; --fg: #24292f; --muted: #6e7781; --line: #d0d7de;
    --accent: #1a7f37; --value: #0550ae; --error: #cf222e;
  }
}

button, select, textarea { font: inherit; color: inherit; }
button {
  background: none; border: 1px solid var(--line); padding: 0 6px; cursor: pointer;
}
button:hover { border-color: var(--accent); color: var(--accent); }

.toggle {
  position: fixed; right: 16px; bottom: 16px; z-index: 2147483646;
  width: 32px; height: 32px; padding: 0;
  background: var(--bg); color: var(--accent); border: 1px solid var(--line);
  font: 700 16px/1 var(--mono);
}

.panel {
  position: fixed; z-index: 2147483647;
  display: flex; flex-direction: column;
  min-width: 320px; min-height: 200px; resize: both; overflow: hidden;
  background: var(--bg); color: var(--fg); border: 1px solid var(--line);
  font: 12px/1.5 var(--mono);
}

.bar {
  display: flex; align-items: center; gap: 8px; padding: 4px 8px;
  background: var(--bar); border-bottom: 1px solid var(--line);
  cursor: move; user-select: none; touch-action: none;
}
.bar .title { color: var(--accent); }
.bar .spacer { flex: 1; }
.bar select {
  background: var(--bg); border: 1px solid var(--line); padding: 0 4px; cursor: pointer;
}

.log { flex: 1; overflow: auto; padding: 4px 8px; }
.empty { color: var(--muted); padding: 8px 0; }
.entry { padding: 4px 0; border-bottom: 1px dashed var(--line); }
.entry .head { display: flex; gap: 8px; align-items: baseline; }
.entry .source { flex: 1; white-space: pre-wrap; cursor: pointer; }
.entry .source::before { content: 'λ> '; color: var(--accent); }
.entry .module { color: var(--muted); }
.entry .copy { visibility: hidden; }
.entry:hover .copy { visibility: visible; }
.output { color: var(--muted); white-space: pre-wrap; }
.value { color: var(--value); white-space: pre-wrap; }
.value::before { content: '=> '; }
.error { color: var(--error); white-space: pre-wrap; margin: 0; }
.node { color: var(--value); cursor: pointer; }
.node.selected { text-decoration: underline; }

.preview { border-top: 1px solid var(--line); max-height: 50%; overflow: auto; }
.preview .label {
  display: flex; justify-content: space-between; padding: 2px 8px;
  color: var(--muted); background: var(--bar); border-bottom: 1px solid var(--line);
}
.preview .stage { padding: 8px; }

.editor {
  display: block; width: 100%; height: 72px; resize: none; padding: 6px 8px;
  background: var(--bg); border: 0; border-top: 1px solid var(--line); outline: none;
}
.hint { padding: 2px 8px; color: var(--muted); border-top: 1px solid var(--line); }
")
