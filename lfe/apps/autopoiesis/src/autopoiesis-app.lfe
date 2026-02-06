(defmodule autopoiesis-app
  (behaviour application)
  (export (start 2) (stop 1)))

(defun start (_type _args)
  (autopoiesis-sup:start_link))

(defun stop (_state)
  (logger:info "Autopoiesis application shutting down")
  'ok)