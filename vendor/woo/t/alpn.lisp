(in-package :cl-user)
(defpackage woo-test.alpn
  (:use :cl :rove)
  (:import-from :woo.ssl.alpn
                :+ssl-tlsext-err-ok+
                :+ssl-tlsext-err-alert-fatal+
                :+ssl-tlsext-err-noack+
                :make-alpn-selector)
  (:import-from :cffi
                :with-foreign-object
                :mem-aref
                :foreign-alloc
                :foreign-free))
(in-package :woo-test.alpn)

;;; Test ALPN Constants

(deftest test-alpn-constants
  (testing "ALPN error constants have correct values"
    (ok (= +ssl-tlsext-err-ok+ 0))
    (ok (= +ssl-tlsext-err-alert-fatal+ 2))
    (ok (= +ssl-tlsext-err-noack+ 3))))

;;; Test parse-alpn-protocols

(deftest test-parse-alpn-protocols-empty
  (testing "parse-alpn-protocols handles empty buffer"
    (cffi:with-foreign-object (data :unsigned-char 0)
      (let ((result (woo.ssl.alpn::parse-alpn-protocols data 0)))
        (ok (null result))))))

(deftest test-parse-alpn-protocols-single
  (testing "parse-alpn-protocols parses single protocol"
    ;; Wire format for "h2": [2, 'h', '2']
    (let ((buffer #(2 104 50)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (let ((result (woo.ssl.alpn::parse-alpn-protocols data (length buffer))))
          (ok (equal result '("h2"))))))))

(deftest test-parse-alpn-protocols-multiple
  (testing "parse-alpn-protocols parses multiple protocols"
    ;; Wire format for ["h2", "http/1.1"]:
    ;; [2, 'h', '2', 8, 'h', 't', 't', 'p', '/', '1', '.', '1']
    (let ((buffer #(2 104 50 8 104 116 116 112 47 49 46 49)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (let ((result (woo.ssl.alpn::parse-alpn-protocols data (length buffer))))
          (ok (equal result '("h2" "http/1.1"))))))))

(deftest test-parse-alpn-protocols-three-protocols
  (testing "parse-alpn-protocols parses three protocols"
    ;; Wire format for ["h2", "http/1.1", "h3"]:
    ;; [2, 'h', '2', 8, 'h', 't', 't', 'p', '/', '1', '.', '1', 2, 'h', '3']
    (let ((buffer #(2 104 50 8 104 116 116 112 47 49 46 49 2 104 51)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (let ((result (woo.ssl.alpn::parse-alpn-protocols data (length buffer))))
          (ok (equal result '("h2" "http/1.1" "h3"))))))))

(deftest test-parse-alpn-protocols-zero-length-protocol
  (testing "parse-alpn-protocols skips zero-length protocol"
    ;; Wire format with zero-length protocol: [0, 2, 'h', '2']
    (let ((buffer #(0 2 104 50)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (let ((result (woo.ssl.alpn::parse-alpn-protocols data (length buffer))))
          (ok (equal result '("h2"))))))))

(deftest test-parse-alpn-protocols-truncated
  (testing "parse-alpn-protocols handles truncated buffer gracefully"
    ;; Wire format claims length 10 but only 5 bytes follow: [10, 'h', '2', ...]
    (let ((buffer #(10 104 50)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (let ((result (woo.ssl.alpn::parse-alpn-protocols data (length buffer))))
          ;; Should skip the invalid protocol
          (ok (null result)))))))

;;; Test find-protocol-in-buffer

(deftest test-find-protocol-in-buffer-found
  (testing "find-protocol-in-buffer finds existing protocol"
    ;; Wire format for ["h2", "http/1.1"]
    (let ((buffer #(2 104 50 8 104 116 116 112 47 49 46 49)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (multiple-value-bind (ptr len)
            (woo.ssl.alpn::find-protocol-in-buffer data (length buffer) "h2")
          (ok (not (null ptr)))
          (ok (= len 2))
          ;; Verify the pointer points to the correct location
          (ok (= (cffi:mem-aref ptr :unsigned-char 0) 104)) ; 'h'
          (ok (= (cffi:mem-aref ptr :unsigned-char 1) 50))))))) ; '2'

(deftest test-find-protocol-in-buffer-second-protocol
  (testing "find-protocol-in-buffer finds second protocol"
    ;; Wire format for ["h2", "http/1.1"]
    (let ((buffer #(2 104 50 8 104 116 116 112 47 49 46 49)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (multiple-value-bind (ptr len)
            (woo.ssl.alpn::find-protocol-in-buffer data (length buffer) "http/1.1")
          (ok (not (null ptr)))
          (ok (= len 8))
          ;; Verify first few characters
          (ok (= (cffi:mem-aref ptr :unsigned-char 0) 104)) ; 'h'
          (ok (= (cffi:mem-aref ptr :unsigned-char 1) 116)) ; 't'
          (ok (= (cffi:mem-aref ptr :unsigned-char 2) 116))))))) ; 't'

(deftest test-find-protocol-in-buffer-not-found
  (testing "find-protocol-in-buffer returns nil when protocol not found"
    ;; Wire format for ["h2", "http/1.1"]
    (let ((buffer #(2 104 50 8 104 116 116 112 47 49 46 49)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (multiple-value-bind (ptr len)
            (woo.ssl.alpn::find-protocol-in-buffer data (length buffer) "h3")
          (ok (null ptr))
          (ok (null len)))))))

(deftest test-find-protocol-in-buffer-empty
  (testing "find-protocol-in-buffer handles empty buffer"
    (cffi:with-foreign-object (data :unsigned-char 0)
      (multiple-value-bind (ptr len)
          (woo.ssl.alpn::find-protocol-in-buffer data 0 "h2")
        (ok (null ptr))
        (ok (null len))))))

(deftest test-find-protocol-in-buffer-partial-match
  (testing "find-protocol-in-buffer doesn't match partial strings"
    ;; Wire format for ["http/1.1"]
    (let ((buffer #(8 104 116 116 112 47 49 46 49)))
      (cffi:with-foreign-object (data :unsigned-char (length buffer))
        (loop for i from 0 below (length buffer)
              do (setf (cffi:mem-aref data :unsigned-char i) (aref buffer i)))
        (multiple-value-bind (ptr len)
            (woo.ssl.alpn::find-protocol-in-buffer data (length buffer) "http")
          ;; Should not match "http" when buffer contains "http/1.1"
          (ok (null ptr))
          (ok (null len)))))))

;;; Test make-alpn-selector

(deftest test-make-alpn-selector-basic
  (testing "make-alpn-selector creates working selector"
    (let ((selector (make-alpn-selector '("h2" "http/1.1"))))
      (ok (functionp selector))
      ;; Test selecting first preference
      (let ((result (funcall selector '("h2" "http/1.1"))))
        (ok (string= result "h2")))
      ;; Test selecting second preference when first not available
      (let ((result (funcall selector '("http/1.1" "h3"))))
        (ok (string= result "http/1.1"))))))

(deftest test-make-alpn-selector-order-preference
  (testing "make-alpn-selector respects server preference order"
    (let ((selector (make-alpn-selector '("h2" "http/1.1"))))
      ;; Even if client prefers http/1.1, server prefers h2
      (let ((result (funcall selector '("http/1.1" "h2"))))
        (ok (string= result "h2"))))))

(deftest test-make-alpn-selector-no-match
  (testing "make-alpn-selector returns nil when no match"
    (let ((selector (make-alpn-selector '("h2" "http/1.1"))))
      (let ((result (funcall selector '("h3" "spdy/3"))))
        (ok (null result))))))

(deftest test-make-alpn-selector-empty-client-list
  (testing "make-alpn-selector handles empty client list"
    (let ((selector (make-alpn-selector '("h2" "http/1.1"))))
      (let ((result (funcall selector '())))
        (ok (null result))))))

(deftest test-make-alpn-selector-empty-preferred-list
  (testing "make-alpn-selector with empty preference list returns nil"
    (let ((selector (make-alpn-selector '())))
      (let ((result (funcall selector '("h2" "http/1.1"))))
        (ok (null result))))))

(deftest test-make-alpn-selector-single-protocol
  (testing "make-alpn-selector works with single protocol"
    (let ((selector (make-alpn-selector '("http/1.1"))))
      ;; Match
      (let ((result (funcall selector '("http/1.1"))))
        (ok (string= result "http/1.1")))
      ;; No match
      (let ((result (funcall selector '("h2"))))
        (ok (null result))))))

(deftest test-make-alpn-selector-case-sensitive
  (testing "make-alpn-selector is case-sensitive"
    (let ((selector (make-alpn-selector '("h2"))))
      (let ((result (funcall selector '("H2"))))
        ;; Should not match due to case difference
        (ok (null result))))))

(deftest test-make-alpn-selector-multiple-matches
  (testing "make-alpn-selector returns first match in preference order"
    (let ((selector (make-alpn-selector '("h3" "h2" "http/1.1"))))
      ;; Client supports h2 and http/1.1, but server prefers h2
      (let ((result (funcall selector '("http/1.1" "h2"))))
        (ok (string= result "h2")))
      ;; Client supports all, server picks first preference
      (let ((result (funcall selector '("http/1.1" "h2" "h3"))))
        (ok (string= result "h3"))))))

;;; Test woo.ssl package

(deftest test-alpn-protocols-default
  (testing "*alpn-protocols* has correct default value"
    ;; Only test if woo.ssl package is available (requires full woo system)
    (when (find-package :woo.ssl)
      (ok (equal (symbol-value (find-symbol "*ALPN-PROTOCOLS*" :woo.ssl))
                 '("http/1.1"))))))
