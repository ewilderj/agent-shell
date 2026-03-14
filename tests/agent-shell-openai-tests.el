;;; agent-shell-openai-tests.el --- Tests for agent-shell-openai -*- lexical-binding: t; -*-

(require 'ert)
(require 'agent-shell)
(require 'agent-shell-openai)

;;; Code:

(ert-deftest agent-shell-openai-default-model-id-test ()
  "Test that Codex config exposes default model id."
  (let ((default-model-id-fn
         (map-elt (agent-shell-openai-make-codex-config) :default-model-id)))

    (let ((agent-shell-openai-default-model-id nil))
      (should (null (funcall default-model-id-fn))))

    (let ((agent-shell-openai-default-model-id "gpt-5.4/low"))
      (should (string= (funcall default-model-id-fn) "gpt-5.4/low")))

    (let ((agent-shell-openai-default-model-id (lambda () "gpt-5.4/low")))
      (should (string= (funcall default-model-id-fn) "gpt-5.4/low")))))

(ert-deftest agent-shell-openai-default-session-mode-id-test ()
  "Test that Codex config exposes default session mode id."
  (let ((default-session-mode-id-fn
         (map-elt (agent-shell-openai-make-codex-config) :default-session-mode-id)))

    (let ((agent-shell-openai-default-session-mode-id nil))
      (should (null (funcall default-session-mode-id-fn))))

    (let ((agent-shell-openai-default-session-mode-id "full-access"))
      (should (string= (funcall default-session-mode-id-fn) "full-access")))))

(provide 'agent-shell-openai-tests)
;;; agent-shell-openai-tests.el ends here
