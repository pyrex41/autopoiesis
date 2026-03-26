;;;; widget-tools.lisp - Generative UI widget tools
;;;;
;;;; Provides show-widget and read-design-system capabilities that
;;;; agents can use to generate interactive Arrow.js widgets in the
;;;; Command Center frontend.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Design System Documentation
;;; ═══════════════════════════════════════════════════════════════════

(defvar *design-system-docs*
  "# Autopoiesis Widget Design System

## Overview
Generate Arrow.js widgets that render in the Command Center.
Widgets run in sandboxed iframes with the design system CSS variables available.

## Colors (CSS variables)
Background depth scale (darkest to lightest):
  --void: #04060e, --deep: #080c18, --mid: #0e1525, --surface: #141d30, --raised: #1a2640

Borders:
  --border: #1e2d4a, --border-hi: #2a3f66

Text:
  --text: #d0daf0 (primary), --text-muted: #7a8ba8 (secondary), --text-dim: #4a5a78 (disabled)

Accent colors:
  --signal: #4fc3f7 (cyan, primary)
  --warm: #ffab40 (amber, secondary)
  --emerge: #69f0ae (green, success)
  --danger: #ff5252 (red, error)
  --purple: #b388ff
  --magenta: #f06292

## Typography
  --font-mono: 'JetBrains Mono' (all UI text)
  --font-display: 'Space Grotesk' (headings only)

## Rules
- Dark mode only — all backgrounds use --void/--deep/--surface
- Max 2-3 accent colors per widget
- No gradients, box-shadows, or blur
- Cards: background var(--surface), 1px solid var(--border), border-radius 6px, padding 12px
- Buttons: background var(--signal-dim), color white, border none, border-radius 4px, padding 6px 12px

## Arrow.js Widget Pattern
```javascript
// These are pre-imported for you:
// import { reactive, html, watch } from 'https://esm.sh/@arrow-js/core';
// output(data) — send data to the host app

const data = reactive({ count: 0 });

html`
  <div style=\"padding: 12px; font-family: var(--font-mono); color: var(--text);\">
    <h3 style=\"color: var(--signal); margin-bottom: 8px;\">My Widget</h3>
    <div>${() => data.count}</div>
    <button
      @click=\"${() => data.count++}\"
      style=\"padding: 6px 12px; background: var(--signal-dim); color: white;
             border: none; border-radius: var(--radius); cursor: pointer;\">
      Click me
    </button>
  </div>
`(document.getElementById('app'));
```

## Available to widgets
- `reactive(obj)` — create reactive state
- `html` tagged template — create DOM with reactive slots via ${() => expr}
- `watch(fn)` — side effects on reactive changes
- `output(data)` — send data back to the host application
- `fetch('/api/...')` — call any REST endpoint
- All CSS variables above are available via var()

## Important
- Mount to `document.getElementById('app')`
- Use inline styles with CSS variables — no external stylesheets
- Keep widgets focused — one visualization per widget
- Return meaningful data via output() when user interacts
"
  "Design system documentation for agent widget generation.")

;;; ═══════════════════════════════════════════════════════════════════
;;; Widget Capabilities
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.agent:defcapability read-design-system (&key modules)
  "Read the design system guidelines for generating widgets.

   Call this before generating a widget to learn the color palette,
   typography, layout rules, and Arrow.js patterns.
   MODULES is optional (reserved for future module-specific docs)."
  :permissions (:read)
  :body
  (declare (ignore modules))
  *design-system-docs*)

(autopoiesis.agent:defcapability show-widget (&key source css title height text)
  "Show an interactive Arrow.js widget to the user in the Command Center.

   SOURCE is the Arrow.js JavaScript source code. The widget environment
   pre-imports reactive, html, watch from Arrow.js and provides an
   output(data) function for host communication. Mount to #app element.

   CSS is optional custom styles for the widget.
   TITLE is an optional header label shown above the widget.
   HEIGHT is the suggested pixel height (default auto-sized).
   TEXT is optional markdown text shown alongside the widget."
  :permissions (:ui-write)
  :body
  (unless source
    (error "SOURCE is required for show-widget"))
  (when (> (length source) autopoiesis.integration::*widget-source-max-size*)
    (error "Widget source exceeds maximum size of ~a bytes"
           autopoiesis.integration::*widget-source-max-size*))
  (let ((widget-id (autopoiesis.core:make-uuid)))
    ;; Use the API broadcast function if available
    (when (find-package :autopoiesis.api)
      (let ((broadcast-fn (find-symbol "BROADCAST-WIDGET" :autopoiesis.api)))
        (when broadcast-fn
          (funcall broadcast-fn widget-id source
                   :css css :title title :height height :text text))))
    (format nil "Widget ~a displayed successfully" widget-id)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Widget Broadcast (API layer integration)
;;; ═══════════════════════════════════════════════════════════════════

;; This function is called from the show-widget capability.
;; It's defined here but will also be exported from the api package
;; via a forwarding function in the api layer.

(defvar *widget-source-max-size* 102400
  "Maximum widget source size in bytes (100KB).")
