(push *default-pathname-defaults* asdf:*central-registry*)
(ql:quickload :rove :silent t)
(asdf:load-system :woo :force t :verbose nil)
(load "t/http2-stream.lisp")

;; Run all the tests in the package
(in-package :woo-test.http2-stream)
(format t "~%~%========== HTTP/2 STREAM STATE MACHINE TESTS ==========~%~%")
(let ((results '()))
  (do-external-symbols (sym (find-package :woo-test.http2-stream))
    (when (and (fboundp sym)
               (typep (symbol-function sym) 'function)
               (search "TEST" (symbol-name sym)))
      (push sym results)))
  (format t "Found ~D test functions~%" (length results))
  (dolist (test-sym (sort results #'string< :key #'symbol-name))
    (format t "~%Running ~A..." test-sym)
    (handler-case
        (progn
          (funcall test-sym)
          (format t " PASSED~%"))
      (error (e)
        (format t " FAILED: ~A~%" e)))))

(format t "~%~%========== ALL TESTS COMPLETE ==========~%~%")
(quit)
