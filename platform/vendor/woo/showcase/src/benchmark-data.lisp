(in-package :woo-showcase)

;; Pre-recorded benchmark data from benchmark.md
;; Conditions: wrk -c 100 -t 4 -d 10
(defvar *benchmark-data*
  '((:name "Woo (4 workers)"
     :language "Common Lisp"
     :requests-per-sec 110528
     :latency-avg-ms 1.12
     :latency-max-ms 21.69
     :highlight t)
    (:name "Go (GOMAXPROCS=4)"
     :language "Go"
     :requests-per-sec 106036
     :latency-avg-ms 1.26
     :latency-max-ms 62.68
     :highlight nil)
    (:name "Unicorn + nginx"
     :language "Ruby"
     :requests-per-sec 73711
     :latency-avg-ms 1.63
     :latency-max-ms 103.23
     :highlight nil)
    (:name "Node.js (4 cluster)"
     :language "JavaScript"
     :requests-per-sec 48546
     :latency-avg-ms 2.05
     :latency-max-ms 21.24
     :highlight nil)
    (:name "Woo (single)"
     :language "Common Lisp"
     :requests-per-sec 38591
     :latency-avg-ms 2.60
     :latency-max-ms 17.18
     :highlight t)
    (:name "Hunchentoot (multi-threaded)"
     :language "Common Lisp"
     :requests-per-sec 32007
     :latency-avg-ms 12.36
     :latency-max-ms 943.13
     :highlight nil)
    (:name "Node.js (single)"
     :language "JavaScript"
     :requests-per-sec 11984
     :latency-avg-ms 8.33
     :latency-max-ms 20.02
     :highlight nil)
    (:name "Tornado (PyPy)"
     :language "Python"
     :requests-per-sec 10636
     :latency-avg-ms 9.42
     :latency-max-ms 45.47
     :highlight nil)
    (:name "Hunchentoot (single)"
     :language "Common Lisp"
     :requests-per-sec 4082
     :latency-avg-ms 28.87
     :latency-max-ms 1610
     :highlight nil)
    (:name "Tornado (CPython)"
     :language "Python"
     :requests-per-sec 2102
     :latency-avg-ms 47.30
     :latency-max-ms 80.61
     :highlight nil)))

;; Benchmark environment info
(defvar *benchmark-environment*
  '(:cpu "8 Core"
    :memory "16GB"
    :os "Ubuntu 16.04.2 LTS"
    :tool "wrk 4.0.0"
    :command "wrk -c 100 -t 4 -d 10"))
