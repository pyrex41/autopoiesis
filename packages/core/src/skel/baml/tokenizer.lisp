;;;; tokenizer.lisp - BAML tokenizer

(in-package #:autopoiesis.skel.baml)

;;; ============================================================================
;;; Reserved Keywords
;;; ============================================================================

(defparameter *baml-keywords*
  '("class" "function" "enum" "client" "prompt"
    "test" "impl" "override" "retry_policy"
    "generator" "template_string" "true" "false" "null")
  "List of BAML reserved keywords.")

(defun baml-keyword-p (str)
  "Return T if STR is a BAML keyword."
  (member str *baml-keywords* :test #'string=))

;;; ============================================================================
;;; Tokenizer State
;;; ============================================================================

(defstruct (tokenizer-state (:conc-name ts-))
  "Internal state for the tokenizer."
  (input "" :type string)
  (pos 0 :type fixnum)
  (line 1 :type fixnum)
  (column 1 :type fixnum)
  (tokens nil :type list))

(defun ts-peek (state &optional (offset 0))
  (let ((pos (+ (ts-pos state) offset)))
    (if (< pos (length (ts-input state)))
        (char (ts-input state) pos)
        nil)))

(defun ts-advance (state)
  (let ((ch (ts-peek state)))
    (when ch
      (incf (ts-pos state))
      (if (char= ch #\Newline)
          (progn
            (incf (ts-line state))
            (setf (ts-column state) 1))
          (incf (ts-column state))))
    ch))

(defun ts-eof-p (state)
  (>= (ts-pos state) (length (ts-input state))))

(defun ts-emit (state type value)
  (push (make-baml-token :type type
                         :value value
                         :line (ts-line state)
                         :column (ts-column state))
        (ts-tokens state)))

;;; ============================================================================
;;; Character Predicates
;;; ============================================================================

(defun whitespace-p (ch)
  (and ch (member ch '(#\Space #\Tab #\Newline #\Return) :test #'char=)))

(defun digit-p (ch)
  (and ch (digit-char-p ch)))

(defun identifier-start-p (ch)
  (and ch (or (alpha-char-p ch) (char= ch #\_))))

(defun identifier-char-p (ch)
  (and ch (or (alphanumericp ch) (char= ch #\_))))

;;; ============================================================================
;;; Token Readers
;;; ============================================================================

(defun skip-whitespace (state)
  (loop while (whitespace-p (ts-peek state))
        do (ts-advance state)))

(defun skip-line-comment (state)
  (ts-advance state)
  (ts-advance state)
  (loop until (or (ts-eof-p state)
                  (char= (ts-peek state) #\Newline))
        do (ts-advance state))
  (when (not (ts-eof-p state))
    (ts-advance state)))

(defun skip-block-comment (state)
  (ts-advance state)
  (ts-advance state)
  (loop until (or (ts-eof-p state)
                  (and (eql (ts-peek state) #\*)
                       (eql (ts-peek state 1) #\/)))
        do (ts-advance state))
  (unless (ts-eof-p state)
    (ts-advance state)
    (ts-advance state)))

(defun read-identifier (state)
  (let ((start-col (ts-column state))
        (start-line (ts-line state))
        (chars nil))
    (loop while (identifier-char-p (ts-peek state))
          do (push (ts-advance state) chars))
    (let ((name (coerce (nreverse chars) 'string)))
      (push (make-baml-token :type (if (baml-keyword-p name) :keyword :identifier)
                             :value name
                             :line start-line
                             :column start-col)
            (ts-tokens state)))))

(defun read-number (state)
  (let ((start-col (ts-column state))
        (start-line (ts-line state))
        (chars nil)
        (has-dot nil))
    (loop while (or (digit-p (ts-peek state))
                    (and (eql (ts-peek state) #\.)
                         (not has-dot)))
          do (let ((ch (ts-advance state)))
               (when (char= ch #\.)
                 (setf has-dot t))
               (push ch chars)))
    (let ((num-str (coerce (nreverse chars) 'string)))
      (push (make-baml-token :type :number
                             :value (if has-dot
                                        (read-from-string num-str)
                                        (parse-integer num-str))
                             :line start-line
                             :column start-col)
            (ts-tokens state)))))

(defun read-string (state)
  (let ((start-col (ts-column state))
        (start-line (ts-line state))
        (chars nil))
    (ts-advance state)
    (loop until (or (ts-eof-p state)
                    (eql (ts-peek state) #\"))
          do (let ((ch (ts-peek state)))
               (cond
                 ((char= ch #\\)
                  (ts-advance state)
                  (let ((escaped (ts-peek state)))
                    (case escaped
                      (#\n (push #\Newline chars))
                      (#\t (push #\Tab chars))
                      (#\r (push #\Return chars))
                      (#\" (push #\" chars))
                      (#\\ (push #\\ chars))
                      (t (push escaped chars)))
                    (ts-advance state)))
                 (t
                  (push (ts-advance state) chars)))))
    (when (eql (ts-peek state) #\")
      (ts-advance state))
    (push (make-baml-token :type :string
                           :value (coerce (nreverse chars) 'string)
                           :line start-line
                           :column start-col)
          (ts-tokens state))))

(defun read-raw-string (state)
  (let ((start-col (ts-column state))
        (start-line (ts-line state))
        (chars nil))
    (ts-advance state)
    (ts-advance state)
    (loop until (or (ts-eof-p state)
                    (and (eql (ts-peek state) #\")
                         (eql (ts-peek state 1) #\#)))
          do (push (ts-advance state) chars))
    (when (eql (ts-peek state) #\")
      (ts-advance state)
      (ts-advance state))
    (push (make-baml-token :type :string
                           :value (coerce (nreverse chars) 'string)
                           :line start-line
                           :column start-col)
          (ts-tokens state))))

;;; ============================================================================
;;; Main Tokenizer
;;; ============================================================================

(defun tokenize-baml (content)
  "Tokenize BAML content string into a list of tokens."
  (let ((state (make-tokenizer-state :input content)))
    (loop until (ts-eof-p state) do
      (let ((ch (ts-peek state)))
        (cond
          ((whitespace-p ch)
           (skip-whitespace state))
          ((and (char= ch #\/)
                (eql (ts-peek state 1) #\/))
           (skip-line-comment state))
          ((and (char= ch #\/)
                (eql (ts-peek state 1) #\*))
           (skip-block-comment state))
          ((and (char= ch #\#)
                (eql (ts-peek state 1) #\"))
           (read-raw-string state))
          ((char= ch #\")
           (read-string state))
          ((digit-p ch)
           (read-number state))
          ((identifier-start-p ch)
           (read-identifier state))
          ((and (char= ch #\-)
                (eql (ts-peek state 1) #\>))
           (ts-emit state :arrow "->")
           (ts-advance state)
           (ts-advance state))
          ((char= ch #\{)
           (ts-emit state :lbrace "{")
           (ts-advance state))
          ((char= ch #\})
           (ts-emit state :rbrace "}")
           (ts-advance state))
          ((char= ch #\()
           (ts-emit state :lparen "(")
           (ts-advance state))
          ((char= ch #\))
           (ts-emit state :rparen ")")
           (ts-advance state))
          ((char= ch #\[)
           (ts-emit state :lbracket "[")
           (ts-advance state))
          ((char= ch #\])
           (ts-emit state :rbracket "]")
           (ts-advance state))
          ((char= ch #\:)
           (ts-emit state :colon ":")
           (ts-advance state))
          ((char= ch #\@)
           (ts-emit state :at "@")
           (ts-advance state))
          ((char= ch #\|)
           (ts-emit state :pipe "|")
           (ts-advance state))
          ((char= ch #\?)
           (ts-emit state :question "?")
           (ts-advance state))
          ((char= ch #\,)
           (ts-emit state :comma ",")
           (ts-advance state))
          ((char= ch #\<)
           (ts-emit state :langle "<")
           (ts-advance state))
          ((char= ch #\>)
           (ts-emit state :rangle ">")
           (ts-advance state))
          (t
           (error 'baml-tokenize-error
                  :message "Unexpected character"
                  :line (ts-line state)
                  :column (ts-column state)
                  :content (string ch))))))
    (nreverse (ts-tokens state))))

;;; ============================================================================
;;; Token Stream Utilities
;;; ============================================================================

(defun token-stream-peek (tokens)
  (first tokens))

(defun token-stream-advance (tokens)
  (values (first tokens) (rest tokens)))

(defun token-stream-expect (tokens expected-type &optional expected-value)
  (let ((token (first tokens)))
    (unless token
      (error 'baml-parse-error
             :message "Unexpected end of input"
             :expected expected-type))
    (unless (eq (token-type token) expected-type)
      (error 'baml-parse-error
             :message "Unexpected token type"
             :expected expected-type
             :found (token-type token)))
    (when (and expected-value
               (not (equal (token-value token) expected-value)))
      (error 'baml-parse-error
             :message "Unexpected token value"
             :expected expected-value
             :found (token-value token)))
    (values token (rest tokens))))

(defun token-stream-match-p (tokens type &optional value)
  (let ((token (first tokens)))
    (and token
         (eq (token-type token) type)
         (or (null value)
             (equal (token-value token) value)))))
