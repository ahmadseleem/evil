;; evil-tests.el --- unit tests for Evil -*- coding: utf-8 -*-

;; This file is for developers. It runs some unit tests on Evil.
;; To load it, add the following lines to .emacs:
;;
;;     (setq evil-tests-run t) ; run tests immediately
;;     (global-set-key [f12] 'evil-tests-run) ; hotkey
;;     (require 'evil-tests)
;;
;; This file is NOT part of Evil itself.

(require 'ert)
(require 'evil)

(defvar evil-tests-run nil
  "Run Evil tests.")

(defun evil-tests-run (&optional arg)
  "Run Evil tests."
  (interactive '(t))
  (if arg (ert-run-tests-interactively '(tag evil))
    (ert-run-tests-batch '(tag evil))))

(defmacro evil-test-buffer (&rest body)
  "Execute BODY in a temporary buffer.
The buffer contains the familiar *scratch* message,
and `evil-local-mode' is enabled."
  (declare (indent defun)
           (debug t))
  `(let ((kill-ring kill-ring)
         (kill-ring-yank-pointer kill-ring-yank-pointer)
         x-select-enable-clipboard
         message-log-max)
     (save-window-excursion
       (with-temp-buffer
         (switch-to-buffer-other-window (current-buffer))
         (buffer-enable-undo)
         (evil-local-mode 1)
         (insert ";; This buffer is for notes you don't want to save, \
and for Lisp evaluation.\n;; If you want to create a file, visit \
that file with C-x C-f,\n;; then enter the text in that file's own \
buffer.\n")
         (goto-char (point-min))
         ,@body))))

;;; States

(defun evil-test-local-mode-enabled ()
  "Verify that `evil-local-mode' is enabled properly"
  (ert-info ("Set the mode variable to t")
    (should (eq evil-local-mode t)))
  (ert-info ("Refresh `emulation-mode-map-alist'")
    (should (memq 'evil-mode-map-alist emulation-mode-map-alists)))
  (ert-info ("Refresh the modeline")
    (should (memq 'evil-modeline-tag global-mode-string)))
  (ert-info ("Create a buffer-local value for `evil-mode-map-alist'")
    (should (assq 'evil-mode-map-alist (buffer-local-variables))))
  (ert-info ("Initialize buffer-local keymaps")
    (should (assq 'evil-normal-state-local-map (buffer-local-variables)))
    (should (keymapp evil-normal-state-local-map))
    (should (assq 'evil-emacs-state-local-map (buffer-local-variables)))
    (should (keymapp evil-emacs-state-local-map)))
  (ert-info ("Refresh buffer-local entries in `evil-mode-map-alist'")
    (should (rassq evil-normal-state-local-map evil-mode-map-alist))
    (should (rassq evil-emacs-state-local-map evil-mode-map-alist)))
  (ert-info ("Don't add buffer-local entries to the default value")
    (should-not (rassq evil-normal-state-local-map
                       (default-value 'evil-mode-map-alist)))
    (should-not (rassq evil-emacs-state-local-map
                       (default-value 'evil-mode-map-alist)))))

(defun evil-test-local-mode-disabled ()
  "Verify that `evil-local-mode' is disabled properly"
  (ert-info ("Set the mode variable to nil")
    (should-not evil-local-mode))
  (ert-info ("Disable all states")
    (evil-test-no-states)))

(defun evil-test-no-states ()
  "Verify that all states are disabled"
  (ert-info ("Set `evil-state' to nil")
    (should-not evil-state))
  (ert-info ("Disable all state keymaps")
    (dolist (state (mapcar 'car evil-states-alist) t)
      (should-not (symbol-value (evil-state-property state :mode)))
      (should-not (memq (symbol-value (evil-state-property state :keymap))
                        (current-active-maps)))
      (should-not (symbol-value (evil-state-property state :local-mode)))
      (should-not (memq (symbol-value (evil-state-property state :local-keymap))
                        (current-active-maps)))
      (dolist (map (evil-state-auxiliary-keymaps state))
        (should-not (memq map (current-active-maps)))))))

(ert-deftest evil-test-toggle-local-mode ()
  "Toggle `evil-local-mode'"
  :tags '(evil)
  (with-temp-buffer
    (ert-info ("Enable `evil-local-mode'")
      (evil-local-mode 1)
      (evil-test-local-mode-enabled))
    (ert-info ("Disable `evil-local-mode'")
      (evil-local-mode -1)
      (evil-test-local-mode-disabled))))

(defun evil-test-change-state (state)
  "Change state to STATE and check keymaps"
  (let (mode keymap local-mode local-keymap tag)
    (evil-change-state state)
    (setq mode (evil-state-property state :mode)
          keymap (symbol-value (evil-state-property
                                state :keymap))
          local-mode (evil-state-property state :local-mode)
          local-keymap (symbol-value (evil-state-property
                                      state :local-keymap))
          tag (symbol-value (evil-state-property
                             state :tag)))
    (ert-info ("Update `evil-state'")
      (should (eq evil-state state)))
    (ert-info ("Ensure `evil-local-mode' is enabled")
      (evil-test-local-mode-enabled))
    (ert-info ("Enable state modes")
      (should (symbol-value mode))
      (should (symbol-value local-mode)))
    (ert-info ("Push state keymaps to the top")
      (evil-test-state-keymaps state))
    (ert-info ("Refresh modeline tag")
      (should (equal evil-modeline-tag tag)))))

(defun evil-test-state-keymaps (state)
  "Verify that STATE's keymaps are pushed to the top"
  (let ((actual (evil-state-keymaps state))
        (expected (list (symbol-value (evil-state-property
                                       state :local-keymap))
                        (symbol-value (evil-state-property
                                       state :keymap)))))
    ;; additional keymaps inherited with :enable
    (cond
     ((eq state 'operator)
      (setq expected
            (append expected
                    (list evil-normal-state-local-map
                          evil-normal-state-map
                          evil-operator-shortcut-map)))))
    (dotimes (i (length expected))
      (should (keymapp (nth i expected)))
      (should (eq (nth i actual) (nth i expected)))
      (should (memq (nth i expected) (current-active-maps)))
      (should (eq (cdr (nth i evil-mode-map-alist))
                  (nth i expected))))))

(ert-deftest evil-test-exit-normal-state ()
  "Enter Normal state and then disable all states"
  :tags '(evil)
  (with-temp-buffer
    (evil-test-change-state 'normal)
    (evil-normal-state -1)
    (evil-test-no-states)))

(ert-deftest evil-test-change-states ()
  "Change between Normal state, Emacs state and Operator-Pending state"
  :tags '(evil)
  (with-temp-buffer
    (evil-test-change-state 'normal)
    (evil-test-change-state 'emacs)
    (evil-test-change-state 'normal)
    (evil-test-change-state 'operator)
    (evil-test-change-state 'normal)
    (evil-test-change-state 'emacs)))

(ert-deftest evil-test-enter-normal-state-disabled ()
  "Enter Normal state even if `evil-local-mode' is disabled"
  :tags '(evil)
  (with-temp-buffer
    (evil-local-mode -1)
    (evil-test-local-mode-disabled)
    (evil-test-change-state 'normal)))

(defun evil-test-suppress-keymap (state)
  "Verify that `self-insert-command' is suppressed in STATE"
  (evil-test-buffer
    (evil-test-change-state state)
    ;; TODO: this must be done better
    (should (eq (key-binding "y") 'undefined))
    (should (eq (key-binding "u") 'undefined))
    (should (eq (key-binding "e") 'undefined))
    (ert-info ("Don't insert text")
      ;; may or may not signal an error, depending on batch mode
      (condition-case nil
          (execute-kbd-macro "yue")
        (error nil))
      (should (string= (buffer-substring 1 4) ";; ")))))

(ert-deftest evil-test-emacs-state-suppress-keymap ()
  "`self-insert-command' works in emacs-state"
  :tags '(evil)
  (should-error (evil-test-suppress-keymap 'emacs)))

(ert-deftest evil-test-normal-state-suppress-keymap ()
  "No `self-insert-command' in normal-state"
  :tags '(evil)
  (evil-test-suppress-keymap 'normal))

(ert-deftest evil-test-operator-state-suppress-keymap ()
  "Operator-Pending state should inherit suppression
of `self-insert-command' from Normal state"
  :tags '(evil)
  (evil-test-suppress-keymap 'operator))

(ert-deftest evil-test-operator-state-shortcut-keymap ()
  "Enable shortcut keymap in Operator-Pending state"
  :tags '(evil)
  (evil-test-buffer
    (ert-info ("Activate `evil-operator-shortcut-map' in
Operator-Pending state")
      (evil-test-change-state 'operator)
      (should (memq evil-operator-shortcut-map
                    (evil-state-keymaps 'operator)))
      (should (keymapp evil-operator-shortcut-map))
      (should evil-operator-shortcut-mode))
    (should (memq evil-operator-shortcut-map
                  (current-active-maps)))
    (ert-info ("Deactivate `evil-operator-shortcut-map'
outside Operator-Pending state")
      (evil-test-change-state 'emacs)
      (should-not evil-operator-shortcut-mode)
      (should-not (memq evil-operator-shortcut-map
                        (current-active-maps))))
    (ert-info ("Reset `evil-operator-shortcut-map'
when entering Operator-Pending state")
      (define-key evil-operator-shortcut-map "f" 'foo)
      (should (eq (lookup-key evil-operator-shortcut-map "f")
                  'foo))
      (evil-test-change-state 'operator)
      (should-not (eq (lookup-key evil-operator-shortcut-map "f")
                      'foo)))
    (ert-info ("Reset `evil-operator-shortcut-map'
when exiting Operator-Pending state")
      (define-key evil-operator-shortcut-map "b" 'bar)
      (should (eq (lookup-key evil-operator-shortcut-map "b")
                  'bar))
      (evil-test-change-state 'emacs)
      (should-not (eq (lookup-key evil-operator-shortcut-map "b")
                      'bar)))))

;;; Type system

(ert-deftest evil-test-exclusive-type ()
  "Expand and contract the `line' type"
  :tags '(evil)
  (evil-test-buffer
    (let* ((first-line 1)
           (second-line (progn
                          (forward-line)
                          (point)))
           (third-line (progn
                         (forward-line)
                         (point))))
      (ert-info ("Return the beginning and end unchanged
if they are the same")
        (should (equal (evil-expand 1 1 'exclusive)
                       (list 1 1 'exclusive))))
      (ert-info ("expand to `inclusive' if the end position
is at the beginning of a line")
        (should (equal (evil-expand (1+ first-line) second-line 'exclusive)
                       (list (1+ first-line) second-line 'inclusive))))
      (ert-info ("expand to `line' if both the beginning and end
are at the beginning of a line")
        (should (equal (evil-expand first-line second-line 'exclusive)
                       (list first-line second-line 'line))))
      (ert-info ("Measure as the strict difference between the end
and the beginning")
        (should (string= (evil-describe 1 1 'exclusive)
                         "0 characters"))
        (should (string= (evil-describe 1 2 'exclusive)
                         "1 character"))
        (should (string= (evil-describe 5 2 'exclusive)
                         "3 characters"))))))

(ert-deftest evil-test-inclusive-type ()
  "Expand and contract the `inclusive' type"
  :tags '(evil)
  (evil-test-buffer
    (ert-info ("Include the ending character")
      (should (equal (evil-expand 1 1 'inclusive)
                     '(1 2 inclusive))))
    (ert-info ("Don't mind if positions are in wrong order")
      (should (equal (evil-expand 5 2 'inclusive)
                     '(2 6 inclusive))))
    (ert-info ("Exclude the ending character when contracting")
      (should (equal (evil-contract 1 2 'inclusive)
                     '(1 1 inclusive))))
    (ert-info ("Don't mind positions order when contracting")
      (should (equal (evil-contract 6 2 'inclusive)
                     '(2 5 inclusive))))
    (ert-info ("Measure as one more than the difference")
      (should (string= (evil-describe 1 1 'inclusive)
                       "1 character"))
      (should (string= (evil-describe 5 2 'inclusive)
                       "4 characters")))))

(ert-deftest evil-test-line-type ()
  "Expand the `line' type"
  :tags '(evil)
  (evil-test-buffer
    (let* ((first-line 1)
           (second-line (progn
                          (forward-line)
                          (point)))
           (third-line (progn
                         (forward-line)
                         (point))))
      (ert-info ("Expand to the whole first line")
        (should (equal (evil-expand first-line first-line 'line)
                       (list first-line second-line 'line)))
        (should (string= (evil-describe first-line first-line 'line)
                         "1 line")))
      (ert-info ("Expand to the two first lines")
        (should (equal (evil-expand first-line second-line 'line)
                       (list first-line third-line 'line)))
        (should (string= (evil-describe first-line second-line 'line)
                         "2 lines"))))))

(ert-deftest evil-test-block-type ()
  "Expand and contract the `block' type"
  :tags '(evil)
  (evil-test-buffer
    (let* ((first-line 1)
           (second-line (progn
                          (forward-line)
                          (point)))
           (third-line (progn
                         (forward-line)
                         (point))))
      (ert-info ("Expand to a 1x1 block")
        (should (equal (evil-expand 1 1 'block)
                       (list 1 2 'block)))
        (should (string= (evil-describe 1 1 'block)
                         "1 row and 1 column")))
      (ert-info ("Expand to a 2x1 block")
        (should (equal (evil-expand first-line second-line 'block)
                       (list first-line (1+ second-line) 'block)))
        (should (string= (evil-describe first-line second-line 'block)
                         "2 rows and 1 column")))
      (ert-info ("Expand to a 3x2 block")
        (should (equal (evil-expand first-line (1+ third-line) 'block)
                       (list first-line (1+ (1+ third-line)) 'block)))
        (should (string= (evil-describe first-line (1+ third-line) 'block)
                         "3 rows and 2 columns")))
      (ert-info ("Contract to a 0x0 rectangle")
        (should (equal (evil-contract 1 2 'block)
                       (list 1 1 'block))))
      (ert-info ("Contract to a 2x0 rectangle")
        (should (equal (evil-contract first-line (1+ second-line) 'block)
                       (list first-line second-line 'block))))
      (ert-info ("Contract to a 3x1 rectangle")
        (should (equal (evil-contract first-line (1+ (1+ third-line)) 'block)
                       (list first-line (1+ third-line) 'block)))))))

;;; Utilities

(ert-deftest evil-test-truncate-vector ()
  "Test `evil-truncate-vector'"
  :tags '(evil)
  (ert-info ("Positive numbers")
    (should (equal (evil-truncate-vector [a b c] 0) []))
    (should (equal (evil-truncate-vector [a b c] 1) [a]))
    (should (equal (evil-truncate-vector [a b c] 2) [a b]))
    (should (equal (evil-truncate-vector [a b c] 3) [a b c]))
    (should (equal (evil-truncate-vector [a b c] 4) [a b c])))
  (ert-info ("Negative numbers")
    (should (equal (evil-truncate-vector [a b c] -1) [a b]))
    (should (equal (evil-truncate-vector [a b c] -2) [a]))
    (should (equal (evil-truncate-vector [a b c] -3) []))
    (should (equal (evil-truncate-vector [a b c] -4) [])))
  (ert-info ("Limit cases")
    (should (equal (evil-truncate-vector [] 0) []))
    (should (equal (evil-truncate-vector [] 3) []))))


(ert-deftest evil-test-normalize-repeat-info ()
  "Verify normalize-repeat-info"
  (ert-info ("Single array")
    (should (equal (evil-normalize-repeat-info
                    '("abc"))
                   '([?a ?b ?c]))))
  (ert-info ("Single symbol")
    (should (equal (evil-normalize-repeat-info
                    '(SYM))
                   '(SYM))))
  (ert-info ("Arrays only")
    (should (equal (evil-normalize-repeat-info
                    '("abc" [XX YY] "def"))
                   '([?a ?b ?c XX YY ?d ?e ?f]))))
  (ert-info ("Several symbols")
    (should (equal (evil-normalize-repeat-info
                    '(BEG MID END))
                   '(BEG MID END))))
  (ert-info ("Arrays with symbol at the beginning")
    (should (equal (evil-normalize-repeat-info
                    '(BEG "abc" [XX YY] "def"))
                   '(BEG [?a ?b ?c XX YY ?d ?e ?f]))))
  (ert-info ("Arrays with symbol at the end")
    (should (equal (evil-normalize-repeat-info
                    '("abc" [XX YY] "def" END))
                   '([?a ?b ?c XX YY ?d ?e ?f] END))))
  (ert-info ("Arrays with symbol in the middle")
    (should (equal (evil-normalize-repeat-info
                    '("abc" [XX YY] MID "def" ))
                   '([?a ?b ?c XX YY] MID [?d ?e ?f]))))
  (ert-info ("Concatenate arrays with several symbols")
    (should (equal (evil-normalize-repeat-info
                    '(BEG "abc" [XX YY] MID "def" END))
                   '(BEG [?a ?b ?c XX YY] MID [?d ?e ?f] END)))))

(defun evil-test-repeat-info (keys &optional recorded)
  "Executes a sequence of keys and verifies that `evil-repeat-info' records them correctly.
`keys' is the sequence of keys to execute `recorded' is the
expected sequence of recorded events, if nil `keys' is used"
  (execute-kbd-macro keys)
  (should (equal (evil-normalize-repeat-info evil-repeat-info)
                 (list (vconcat (or recorded keys))))))

(ert-deftest evil-test-normal-repeat-info-simple-command ()
  "Save key-sequence after simple editing command in vi-state"
  :tags '(evil)
  (evil-test-buffer
    (evil-test-change-state 'normal)
    (ert-info ("Call simple command without count")
      (evil-test-repeat-info "x"))
    (ert-info ("Call simple command with count 3")
      (evil-test-repeat-info "3x"))))

(ert-deftest evil-test-normal-repeat-info-char-command ()
  "Save key-sequence after editing command with character in vi-state"
  :tags '(evil)
  (evil-test-buffer
    (evil-test-change-state 'normal)
    (ert-info ("Call command with character argument without count")
      (evil-test-repeat-info "r5"))
    (ert-info ("Call command with character argument with count 12")
      (evil-test-repeat-info "12rX"))))

(ert-deftest evil-test-insert-repeat-info ()
  "Save key-sequence after insertion mode"
  :tags '(evil)
  (evil-test-buffer
    (evil-test-change-state 'normal)
    (ert-info ("Insert text without count")
      (evil-test-repeat-info (vconcat "iABC" [escape])))
    (ert-info ("Insert text with count 42")
      (evil-test-repeat-info (vconcat "42iABC" [escape])))))

(defun evil-test-editing (keys expected &optional point-char)
  "Execute key-sequence `keys' and verify if the text around point matches
`expected' afterwards.
`keys' is a sequence of events to be passed to `execute-kbd-macro'
`expected' is a regexp with a special character marking (point)'s position
`point-char' is the special character marking (point)'s position, defaulted to °
If, e.g., expected is \"ABC°def\" this means the expected text before point is
\"ABC\" and the expected text after point is \"def\". "
  (setq point-char (regexp-quote (char-to-string (or point-char ?°))))
  (unless (string-match point-char expected)
    (error "No cursor specified in expected string: %s" expected))
  (let ((before (substring expected 0 (match-beginning 0)))
        (after (substring expected (match-end 0))))
    (execute-kbd-macro keys)
    (ert-info ((format "Text before point is %s"
                       (buffer-substring (max (point-min)
                                              (- (point) (length before)))
                                         (point))))
      (should (looking-back before)))
    (ert-info ((format "Text after point is %s"
                       (buffer-substring (point)
                                         (min (point-max)
                                              (+ (point) (length after))))))
      (should (looking-at after)))))

(defun evil-test-editing-clean (keys expected &optional point-char)
  "The same as `evil-test-editing' but starts with a new
unchanged test-buffer in normal-state."
  (evil-test-buffer
    (evil-test-change-state 'normal)
    (evil-test-editing keys expected point-char)))


(ert-deftest evil-test-repeat ()
  "Repeat several editing commands."
  :tags '(evil)
  (ert-info ("Repeat replace")
    (evil-test-editing-clean (vconcat "rX" [right right] ".")
                             "\\`X;°XThis"))

  (ert-info ("Repeat replace with count")
    (evil-test-editing-clean (vconcat "2rX" [right right] ".")
                             "\\`XX X°Xis "))

  (ert-info ("Repeat replace without count with a new count")
    (evil-test-editing-clean (vconcat "rX" [right right] "13.")
                             "\\`X;XXXXXXXXXXXX°Xis for"))

  (ert-info ("Repeat replace with count replacing original count")
    (evil-test-editing-clean (vconcat "11rX" [right right] "20.")
                             "\\`XXXXXXXXXXXfXXXXXXXXXXXXXXXXXXX°Xdon't ")))

(ert-deftest evil-test-cmd-replace-char ()
  "Calling `evil-replace-char' should replace characters."
  :tags '(evil)
  (evil-test-editing-clean "r5" "\\`°5; This")
  (evil-test-editing-clean "3rX" "\\`XX°XThis"))

(ert-deftest evil-test-insert-before ()
  "Test insertion of text before point"
  :tags '(evil)
  (evil-test-buffer
    (evil-local-mode 1)
    (goto-char (+ 3 (point-min)))
    (should (and (looking-at "This") (looking-back ";; ")))
    (evil-test-editing  (vconcat "ievil rulz " [escape])
                        "\\`;; evil rulz° This")))

(ert-deftest evil-test-insert-before-with-count ()
  "Test insertion of text before point with repeat count"
  :tags '(evil)
  (evil-test-buffer
    (evil-local-mode 1)
    (goto-char (+ 3 (point-min)))
    (should (and (looking-at "This") (looking-back ";; ")))
    (evil-test-editing  (vconcat "2ievil rulz " [escape])
                        "\\`;; evil rulz evil rulz° This")))

(ert-deftest evil-test-repeat-insert-before ()
  "Test repeating of insert-before command."
  :tags '(evil)
  (ert-info ("Repeat insert")
    (evil-test-editing-clean (vconcat "iABC" [escape] "..")
                             "ABABAB°CCC;; This"))

  (ert-info ("Repeat insert with count")
    (evil-test-editing-clean (vconcat "2iABC" [escape] "..")
                             "ABCABABCABABCAB°CCC;; This"))

  (ert-info ("Repeat insert with repeat count")
    (evil-test-editing-clean (vconcat "iABC" [escape] "11.")
                             "ABABCABCABCABCABCABCABCABCABCABCAB°CC;; This"))

  (ert-info ("Repeat insert with count with repeat with count")
    (evil-test-editing-clean
     (vconcat "10iABC" [escape] "11.")
     "ABCABCABCABCABCABCABCABCABCABABCABCABCABCABCABCABCABCABCABCAB°CC;; This")))

(ert-deftest evil-test-insert-after ()
  "Test insertion of text after point"
  :tags '(evil)
  (evil-test-buffer
    (evil-local-mode 1)
    (goto-char (+ 3 (point-min)))
    (should (and (looking-at "This") (looking-back ";; ")))
    (evil-test-editing  (vconcat "aevil rulz " [escape])
                        "\\`;; Tevil rulz° his")))

(ert-deftest evil-test-insert-after-with-count ()
  "Test insertion of text after point with repeat count"
  :tags '(evil)
  (evil-test-buffer
    (evil-local-mode 1)
    (goto-char (+ 3 (point-min)))
    (evil-test-editing  (vconcat "2aevil rulz " [escape])
                        "\\`;; Tevil rulz evil rulz° his")))

(ert-deftest evil-test-repeat-insert-after ()
  "Test repeating of insert-after command."
  :tags '(evil)
  (ert-info ("Repeat insert")
    (evil-test-editing-clean (vconcat "aABC" [escape] "..")
                             ";ABCABCAB°C; This"))

  (ert-info ("Repeat insert with count")
    (evil-test-editing-clean (vconcat "2aABC" [escape] "..")
                             ";ABCABCABCABCABCAB°C; This"))

  (ert-info ("Repeat insert with repeat count")
    (evil-test-editing-clean (vconcat "aABC" [escape] "11.")
                             ";ABCABCABCABCABCABCABCABCABCABCABCAB°C; This"))

  (ert-info ("Repeat insert with count with repeat with count")
    (evil-test-editing-clean
     (vconcat "10aABC" [escape] "11.")
     ";ABCABCABCABCABCABCABCABCABCABCABCABCABCABCABCABCABCABCABCABCAB°C; This")))

(ert-deftest evil-test-insert-above ()
  "Test insertion of text above point"
  :tags '(evil)
  (evil-test-buffer
    (evil-local-mode 1)
    (forward-line)
    (evil-test-editing  (vconcat "Oabc\ndef" [escape])
                        "evaluation.\nabc\nde°f\n;; If you")))

(ert-deftest evil-test-insert-above-with-count ()
  "Test insertion of text above point with repeat count"
  :tags '(evil)
  (evil-test-buffer
    (evil-local-mode 1)
    (forward-line)
    (evil-test-editing  (vconcat "2Oevil\nrulz" [escape])
                        "evaluation.\nevil\nrulz\nevil\nrul°z\n;; If you")))

(ert-deftest evil-test-repeat-insert-above ()
  "Test repeating of insert-above command."
  :tags '(evil)
  (ert-info ("Repeat insert")
    (evil-test-editing-clean (vconcat "Oevil\nrulz" [escape] "..")
                             "\\`evil\nevil\nevil\nrul°z\nrulz\nrulz\n;; This"))

  (ert-info ("Repeat insert with count")
    (evil-test-editing-clean
     (vconcat "2Oevil\nrulz" [escape] "..")
     "\\`evil\nrulz\nevil\nevil\nrulz\nevil\nevil\nrulz\nevil\nrul°z\nrulz\nrulz\n;; This"))

  (ert-info ("Repeat insert with repeat count")
    (evil-test-editing-clean (vconcat "Oevil\nrulz" [escape] "2.")
                             "evil\nevil\nrulz\nevil\nrul°z\nrulz\n;; This"))

  (ert-info ("Repeat insert with count with repeat with count")
    (evil-test-editing-clean
     (vconcat "2Oevil\nrulz" [escape] "3.")
     "\\`evil\nrulz\nevil\nevil\nrulz\nevil\nrulz\nevil\nrul°z\nrulz\n;; This")))

(ert-deftest evil-test-insert-below ()
  "Test insertion of text below point"
  :tags '(evil)
  (evil-test-buffer
    (evil-local-mode 1)
    (evil-test-editing  (vconcat "oabc\ndef" [escape])
                        "evaluation.\nabc\nde°f\n;; If you")))

(ert-deftest evil-test-insert-below-with-count ()
  "Test insertion of text below point with repeat count"
  :tags '(evil)
  (evil-test-buffer
    (evil-local-mode 1)
    (evil-test-editing  (vconcat "2oevil\nrulz" [escape])
                        "evaluation.\nevil\nrulz\nevil\nrul°z\n;; If you")))

(ert-deftest evil-test-repeat-insert-below ()
  "Test repeating of insert-below command."
  :tags '(evil)
  (ert-info ("Repeat insert")
    (evil-test-editing-clean (vconcat "oevil\nrulz" [escape] "..")
                             "evaluation.\nevil\nrulz\nevil\nrulz\nevil\nrul°z\n;; If you"))

  (ert-info ("Repeat insert with count")
    (evil-test-editing-clean
     (vconcat "2oevil\nrulz" [escape] "..")
     "evaluation.\nevil\nrulz\nevil\nrulz\nevil\nrulz\nevil\nrulz\nevil\nrulz\nevil\nrul°z\n;; If you"))

  (ert-info ("Repeat insert with repeat count")
    (evil-test-editing-clean
     (vconcat "oevil\nrulz" [escape] "2.")
     "evaluation.\nevil\nrulz\nevil\nrulz\nevil\nrul°z\n;; If you"))

  (ert-info ("Repeat insert with count with repeat with count")
    (evil-test-editing-clean
     (vconcat "2oevil\nrulz" [escape] "3.")
     "evaluation.\nevil\nrulz\nevil\nrulz\nevil\nrulz\nevil\nrulz\nevil\nrul°z\n;; If you")))


(defun evil-test-dummy-complete ()
  "Test function for change-base repeation.
Removes 5 characters, insert BEGIN\\n\\nEND\\nplaces
cursor on the new line."
  (interactive)
  (delete-char 5)
  (insert "BEGIN\n")
  (save-excursion
    (insert "\nEND\n")))


(ert-deftest evil-test-repeat-by-change ()
  "Test repeation by tracking changes for completion commands."
  (let (line-move-visual)
    (define-key evil-insert-state-map (kbd "C-c C-p") 'evil-test-dummy-complete)
    (evil-set-insert-repeat-type 'evil-test-dummy-complete 'change)
    (evil-test-editing-clean
     (vconcat [right right right] "iABC " (kbd "C-c C-p") "BODY" [escape]
              [down down home] ".")
     "\\`;; ABC BEGIN\nBODY\nEND\nABC BEGIN\nBOD°Y\nEND\nr is for")))

(ert-deftest evil-test-repeat-kill-buffer ()
  "Test safe-guard preventing buffers from being deleted when repeating a command."
  (ert-info ("Test killing works for direct calls to `evil-execute-repeat-info'")
    (evil-test-buffer
      (evil-local-mode 1)
      (setq evil-repeat-info '((kill-buffer nil)))
      (evil-execute-repeat-info evil-repeat-info)
      (should (not (looking-at ";; This")))))

  (ert-info ("Verify an error is raised when using `evil-repeat' command")
    (evil-test-buffer
      (evil-local-mode 1)
      (setq evil-repeat-info '((kill-buffer nil)))
      (should-error (call-interactively 'evil-repeat)))))

(ert-deftest evil-test-operator ()
  "Test operator."
  (evil-test-editing-clean
   (vconcat [right right right] "g?" [M-right])
   ";; °Guvf buffer")) 

(ert-deftest evil-test-operator-with-count ()
  "Test operator."
  (ert-info ("Count before operator")
    (evil-test-editing-clean
     (vconcat [right right right] "2g?" [M-right])
     ";; °Guvf ohssre is"))

  (ert-info ("Count before motion")
    (evil-test-editing-clean
     (vconcat [right right right] "g?2" [M-right])
     ";; °Guvf ohssre is"))

  (ert-info ("Count before operator and motion")
    (evil-test-editing-clean
     (vconcat [right right right] "3g?2" [M-right])
     ";; °Guvf ohssre vf sbe abgrf lbh don't")))

(when evil-tests-run
  (evil-tests-run))

(provide 'evil-tests)

;;; evil-tests.el ends here
