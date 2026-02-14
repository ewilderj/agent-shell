;;; agent-shell-quiet.el --- Quiet mode for compact turn display -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Alvaro Ramirez

;; Author: Alvaro Ramirez https://xenodium.com
;; URL: https://github.com/xenodium/agent-shell

;; This package is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This package is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Provides quiet mode for agent-shell.  When enabled, all thought
;; process and tool call fragments within a turn are grouped under a
;; single collapsible section, reducing vertical space.
;;
;; Report issues at https://github.com/xenodium/agent-shell/issues
;;
;; ✨ Please support this work https://github.com/sponsors/xenodium ✨

;;; Code:

(require 'map)
(require 'agent-shell-ui)

(defvar agent-shell--state)

(declare-function agent-shell--update-fragment "agent-shell")
(declare-function agent-shell-viewport--buffer "agent-shell-viewport")
(declare-function agent-shell-viewport--shell-buffer "agent-shell-viewport")

(defcustom agent-shell-quiet-mode nil
  "Whether to use quiet mode for agent turns.

When non-nil, all thought process and tool call sections within a
turn are grouped under a single collapsible section.  The section
label shows the current thought summary.  Expanding reveals the
individual tool calls and thought content as nested collapsible
sections.

When nil (the default), each thought and tool call is shown as a
separate top-level collapsible section."
  :type 'boolean
  :group 'agent-shell)

(defvar agent-shell--quiet-mode-spinner-frames '("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  "Braille spinner animation frames.")

(defun agent-shell--quiet-mode-spinner-start (state)
  "Start a spinner animation on the current quiet group in STATE.
The timer and frame index are stored on the group alist so that
multiple sessions can each have their own independent spinner."
  (agent-shell--quiet-mode-spinner-stop state)
  (when-let* ((group (map-elt state :quiet-group)))
    (let ((timer (run-with-timer 0 0.1
                                 #'agent-shell--quiet-mode-spinner-tick state)))
      (map-put! group :spinner-timer timer)
      (map-put! group :spinner-index 0))))

(defun agent-shell--quiet-mode-spinner-stop (state)
  "Stop the spinner animation for the current quiet group in STATE."
  (when-let* ((group (map-elt state :quiet-group))
              (timer (map-elt group :spinner-timer)))
    (cancel-timer timer)
    (map-put! group :spinner-timer nil)))

(defun agent-shell--quiet-mode-spinner-tick (state)
  "Advance the spinner one frame and update the wrapper label in STATE."
  (condition-case err
      (when-let* ((group (map-elt state :quiet-group))
                  (buf (map-elt state :buffer)))
        (when (buffer-live-p buf)
          (let* ((idx (or (map-elt group :spinner-index) 0))
                 (frame (nth (mod idx
                                  (length agent-shell--quiet-mode-spinner-frames))
                             agent-shell--quiet-mode-spinner-frames))
                 (label (map-elt group :label))
                 (display-label (format "%s %s" frame label)))
            (map-put! group :spinner-index (1+ idx))
            (agent-shell--update-fragment
             :state state
             :namespace-id (map-elt group :request-count)
             :block-id (map-elt group :wrapper-block-id)
             :label-left (propertize display-label
                                     'font-lock-face 'font-lock-doc-markup-face)))))
    (error (message "quiet-mode spinner error: %S" err)
           (agent-shell--quiet-mode-spinner-stop state))))

(defun agent-shell--quiet-mode-finalize-group (state)
  "Stop the spinner and show a checkmark on the current group in STATE."
  (agent-shell--quiet-mode-spinner-stop state)
  (when-let* ((group (map-elt state :quiet-group)))
    (let ((label (or (map-elt group :label) "Working…")))
      (agent-shell--update-fragment
       :state state
       :namespace-id (map-elt group :request-count)
       :block-id (map-elt group :wrapper-block-id)
       :label-left (propertize (format "✓ %s" label)
                               'font-lock-face 'font-lock-doc-markup-face))
      (when (map-elt group :child-block-ids)
        (agent-shell--quiet-mode-sync-children-visibility state group)))))

(defun agent-shell--quiet-mode-simplify-childless-groups (state)
  "Finalize any groups that were not yet finalized in STATE.
Called at turn end to catch groups that may have been missed."
  (dolist (group (map-elt state :quiet-groups))
    (let ((label (or (map-elt group :label) "Working…")))
      (agent-shell--update-fragment
       :state state
       :namespace-id (map-elt group :request-count)
       :block-id (map-elt group :wrapper-block-id)
       :label-left (propertize (format "✓ %s" label)
                               'font-lock-face 'font-lock-doc-markup-face)))))

(defun agent-shell--quiet-mode-ensure-wrapper (state &optional new-thought-p)
  "Ensure a quiet-mode wrapper fragment exists for the current phase in STATE.
Creates a new wrapper when starting a new turn or when NEW-THOUGHT-P is
non-nil and the current group already has tool calls (indicating a new
phase of work).  Returns the current quiet-group alist."
  (let* ((group (map-elt state :quiet-group))
         (same-turn (and group
                         (equal (map-elt group :request-count)
                                (map-elt state :request-count))))
         (need-new (or (not same-turn)
                       ;; New phase: thought arriving after tool calls
                       (and same-turn new-thought-p
                            (map-elt group :has-tool-calls)))))
    (when need-new
      ;; Finalize previous group (stop spinner, show checkmark)
      (when group
        (agent-shell--quiet-mode-finalize-group state))
      (let ((group-index (if same-turn
                             (1+ (or (map-elt state :quiet-group-index) 0))
                           1)))
        (setq group (list (cons :request-count (map-elt state :request-count))
                          (cons :wrapper-block-id
                                (format "quiet-%s-%s"
                                        (map-elt state :request-count)
                                        group-index))
                          (cons :child-block-ids nil)
                          (cons :has-tool-calls nil)
                          (cons :spinner-timer nil)
                          (cons :spinner-index 0)
                          (cons :thought-text "")
                          (cons :label "Working…")))
        (map-put! state :quiet-group group)
        (map-put! state :quiet-group-index group-index)
        ;; Track all groups for toggle support
        (let ((groups (map-elt state :quiet-groups)))
          (map-put! state :quiet-groups (append groups (list group))))
        ;; Register invisibility spec in both buffers
        (dolist (buf (list (map-elt state :buffer)
                           (agent-shell-viewport--buffer
                            :shell-buffer (map-elt state :buffer)
                            :existing-only t)))
          (when (and buf (buffer-live-p buf))
            (with-current-buffer buf
              (add-to-invisibility-spec 'agent-shell-quiet))))
        ;; Create the wrapper fragment (collapsed by default)
        (agent-shell--update-fragment
         :state state
         :namespace-id (map-elt group :request-count)
         :block-id (map-elt group :wrapper-block-id)
         :label-left (propertize (map-elt group :label)
                                 'font-lock-face 'font-lock-doc-markup-face)
         :body " "
         :expanded nil)
        ;; Start spinner animation
        (agent-shell--quiet-mode-spinner-start state)))
    group))

(defun agent-shell--quiet-mode-strip-markup (text)
  "Strip markdown bold/italic markup from TEXT.
Returns nil if the result is empty or whitespace-only."
  (let ((s text))
    (setq s (replace-regexp-in-string "\\*\\*\\|__" "" s))
    (setq s (string-trim s))
    (when (> (length s) 0) s)))

(defun agent-shell--quiet-mode-update-label (state text)
  "Accumulate thought TEXT into the current group in STATE.
Strips markup from the accumulated text and uses it as the label.
When the label exceeds 72 characters, it is truncated and the full
thought is inserted as a hidden child fragment."
  (when-let* ((group (map-elt state :quiet-group)))
    (let* ((accumulated (concat (or (map-elt group :thought-text) "") text))
           (label (agent-shell--quiet-mode-strip-markup accumulated)))
      (map-put! group :thought-text accumulated)
      (when label
        ;; Truncate at first newline, then check length limit.
        (let* ((first-line (car (split-string label "\n")))
               (too-long (> (length first-line) 72))
               (display-label (if too-long
                                  (concat (substring first-line 0 72) "…")
                                first-line))
               (need-child (or too-long (not (string= first-line label)))))
          (if need-child
              (let ((thought-id (format "%s-thought"
                                        (map-elt group :wrapper-block-id))))
                (map-put! group :label display-label)
                ;; Insert full thought as a hidden child fragment
                (agent-shell--update-fragment
                 :state state
                 :namespace-id (map-elt group :request-count)
                 :block-id thought-id
                 :label-left (propertize label
                                         'font-lock-face 'font-lock-doc-markup-face))
                ;; Register as first child if not already
                (unless (member thought-id (map-elt group :child-block-ids))
                  (map-put! group :child-block-ids
                           (cons thought-id (map-elt group :child-block-ids))))
                (agent-shell--quiet-mode-sync-children-visibility state group))
            (map-put! group :label label)))))))

(defun agent-shell--quiet-mode-register-child (state block-id)
  "Register BLOCK-ID as a child of the current quiet group in STATE."
  (when-let* ((group (map-elt state :quiet-group)))
    (let ((children (map-elt group :child-block-ids)))
      (unless (member block-id children)
        (map-put! group :child-block-ids
                 (append children (list block-id)))))))

(defun agent-shell--quiet-mode-find-group-for-child (state block-id)
  "Find the quiet group in STATE that owns BLOCK-ID.
Searches all groups in reverse order (most recent first)."
  (let ((found nil))
    (dolist (group (reverse (map-elt state :quiet-groups)))
      (when (and (not found)
                 (member block-id (map-elt group :child-block-ids)))
        (setq found group)))
    found))

(defun agent-shell--quiet-mode-mark-tool-call (state)
  "Mark the current quiet group in STATE as having tool calls.
This allows `agent-shell--quiet-mode-ensure-wrapper' to start a
new group when the next thought arrives."
  (when-let* ((group (map-elt state :quiet-group)))
    (map-put! group :has-tool-calls t)))

(defun agent-shell--quiet-mode-style-child (start end collapsed)
  "Apply quiet-mode styling to child fragment region from START to END.
When COLLAPSED is non-nil, hide the region.  When nil, show it
with indentation and reduced spacing.

Uses the `agent-shell-quiet' invisible spec to avoid conflicting
with fragment-level collapse which uses t."
  (if collapsed
      ;; Hide: set agent-shell-quiet only where invisible is currently nil,
      ;; preserving fragment-internal invisible=t on collapsed bodies.
      (save-excursion
        (let ((pos start))
          (while (< pos end)
            (let* ((val (get-text-property pos 'invisible))
                   (next (next-single-property-change pos 'invisible nil end)))
              (unless val
                (put-text-property pos next 'invisible 'agent-shell-quiet))
              (setq pos next)))))
    ;; Show: remove our invisible spec from the region,
    ;; leaving t (fragment-internal collapse) untouched.
    (save-excursion
      (let ((pos start))
        (while (< pos end)
          (let* ((val (get-text-property pos 'invisible))
                 (next (next-single-property-change pos 'invisible nil end)))
            (when (eq val 'agent-shell-quiet)
              (remove-text-properties pos next '(invisible nil)))
            (setq pos next)))))
    ;; Indent child fragments to show hierarchy
    (put-text-property start end 'line-prefix "  ")
    (put-text-property start end 'wrap-prefix "  ")
    ;; Reduce preceding newlines: keep only 1 instead of 2
    (save-excursion
      (goto-char start)
      (when (and (> start (point-min))
                 (eq (char-before start) ?\n)
                 (> (1- start) (point-min))
                 (eq (char-before (1- start)) ?\n))
        (put-text-property (1- start) start 'invisible 'agent-shell-quiet)))))

(defun agent-shell--quiet-mode-hide-wrapper-body (buf qualified-wrapper-id)
  "Hide the wrapper fragment's body padding in BUF.
QUALIFIED-WRAPPER-ID identifies the wrapper.  The wrapper's body
is just a placeholder space; we keep it invisible even when the
wrapper is expanded so it doesn't add blank lines.

This function exists because agent-shell-ui requires a non-nil body
to show a collapse indicator (▶/▼).  If the UI supported a
`:bodyless-collapsible' option on fragments, this workaround and
the placeholder body in `agent-shell--quiet-mode-ensure-wrapper'
could be removed entirely."
  (when (and buf (buffer-live-p buf))
    (with-current-buffer buf
      (save-mark-and-excursion
        (let ((inhibit-read-only t)
              (buffer-undo-list t))
          (goto-char (point-max))
          (when-let* ((match (text-property-search-backward
                              'agent-shell-ui-state nil
                              (lambda (_ s)
                                (equal (map-elt s :qualified-id) qualified-wrapper-id))
                              t))
                      (block-start (prop-match-beginning match))
                      (block-end (prop-match-end match))
                      (body-range (agent-shell-ui--nearest-range-matching-property
                                   :property 'agent-shell-ui-section :value 'body
                                   :from block-start :to block-end))
                      (label-end (or (map-elt (agent-shell-ui--nearest-range-matching-property
                                               :property 'agent-shell-ui-section :value 'label-right
                                               :from block-start :to block-end)
                                              :end)
                                     (map-elt (agent-shell-ui--nearest-range-matching-property
                                               :property 'agent-shell-ui-section :value 'label-left
                                               :from block-start :to block-end)
                                              :end))))
            ;; Hide from end of label to end of body (the \n\n + " ")
            (put-text-property label-end (map-elt body-range :end)
                               'invisible 'agent-shell-quiet)))))))

(defun agent-shell--quiet-mode-sync-children-visibility (state &optional group)
  "Sync quiet-mode child visibility with wrapper collapsed state in STATE.
Uses GROUP if provided, otherwise the current quiet group.
Called after a child fragment is created/updated to ensure it matches
the wrapper's visibility."
  (when-let* ((group (or group (map-elt state :quiet-group)))
              (wrapper-id (map-elt group :wrapper-block-id))
              (request-count (map-elt group :request-count))
              (namespace-id (format "%s" request-count))
              (qualified-wrapper-id (format "%s-%s" namespace-id wrapper-id)))
    ;; Process each buffer (shell + viewport)
    (dolist (buf (list (map-elt state :buffer)
                       (agent-shell-viewport--buffer
                        :shell-buffer (map-elt state :buffer)
                        :existing-only t)))
      (when (and buf (buffer-live-p buf))
        ;; Always keep wrapper body hidden (it's just a placeholder)
        (agent-shell--quiet-mode-hide-wrapper-body buf qualified-wrapper-id)
        (with-current-buffer buf
          (save-mark-and-excursion
            (let ((inhibit-read-only t)
                  (buffer-undo-list t))
              ;; Find wrapper state to check if collapsed
              (goto-char (point-max))
              (when-let* ((match (text-property-search-backward
                                  'agent-shell-ui-state nil
                                  (lambda (_ s)
                                    (equal (map-elt s :qualified-id) qualified-wrapper-id))
                                  t))
                          (wrapper-state (get-text-property (prop-match-beginning match)
                                                           'agent-shell-ui-state)))
                (let ((wrapper-collapsed (map-elt wrapper-state :collapsed)))
                  ;; Style all children based on wrapper collapsed state
                  (dolist (child-id (map-elt group :child-block-ids))
                    (let ((qualified-child-id (format "%s-%s" namespace-id child-id)))
                      (goto-char (point-max))
                      (when-let* ((child-match (text-property-search-backward
                                                'agent-shell-ui-state nil
                                                (lambda (_ s)
                                                  (equal (map-elt s :qualified-id) qualified-child-id))
                                                t)))
                        (let ((start (prop-match-beginning child-match))
                              (end (prop-match-end child-match)))
                          (save-excursion
                            (goto-char start)
                            (skip-chars-backward "\n")
                            (setq start (point)))
                          (agent-shell--quiet-mode-style-child
                           start end wrapper-collapsed))))))))))))))

(defun agent-shell--quiet-mode-toggle-children (orig-fn)
  "Advice around `agent-shell-ui-toggle-fragment-at-point' for quiet mode.
After toggling a quiet wrapper, also toggle its child fragments.
ORIG-FN is the original toggle function."
  (let* ((state-before (get-text-property (point) 'agent-shell-ui-state))
         (qualified-id (and state-before (map-elt state-before :qualified-id))))
    (funcall orig-fn)
    ;; After toggle, check if this was a quiet wrapper
    (when (and agent-shell-quiet-mode
               qualified-id
               (string-match "^\\(.+\\)-quiet-\\(.+\\)$" qualified-id))
      (let* ((shell-buf (cond
                          ((derived-mode-p 'agent-shell-mode) (current-buffer))
                          (t (agent-shell-viewport--shell-buffer))))
             (shell-state (and shell-buf (buffer-live-p shell-buf)
                               (buffer-local-value 'agent-shell--state shell-buf))))
        (when shell-state
          ;; Find the group whose wrapper matches this qualified-id
          (let ((target-group nil))
            (dolist (group (map-elt shell-state :quiet-groups))
              (when (string-suffix-p (map-elt group :wrapper-block-id)
                                     qualified-id)
                (setq target-group group)))
            (agent-shell--quiet-mode-sync-children-visibility
             shell-state target-group)))))))
(advice-add 'agent-shell-ui-toggle-fragment-at-point
            :around #'agent-shell--quiet-mode-toggle-children)

(provide 'agent-shell-quiet)

;;; agent-shell-quiet.el ends here
