;;;; persistent-structs.lisp - Persistent data structure wrappers
;;;;
;;;; Thin wrappers around fset library providing persistent maps, vectors,
;;;; and sets with API names that insulate from the underlying implementation.

(in-package #:autopoiesis.core)

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Maps (wrapping fset:map)
;;; ═══════════════════════════════════════════════════════════════════

(defun pmap-empty ()
  "Return an empty persistent map."
  (fset:empty-map))

(defun pmap-get (map key &optional default)
  "Look up KEY in persistent MAP. Returns (values value found-p)."
  (let ((val (fset:lookup map key)))
    (if val
        (values val t)
        (values default (not (null (fset:domain-contains? map key)))))))

(defun pmap-put (map key value)
  "Return a new persistent map with KEY mapped to VALUE."
  (fset:with map key value))

(defun pmap-remove (map key)
  "Return a new persistent map without KEY."
  (fset:less map key))

(defun pmap-contains-p (map key)
  "Return T if MAP contains KEY."
  (fset:domain-contains? map key))

(defun pmap-keys (map)
  "Return a list of all keys in MAP."
  (fset:convert 'list (fset:domain map)))

(defun pmap-values (map)
  "Return a list of all values in MAP."
  (let (result)
    (fset:do-map (k v map)
      (declare (ignore k))
      (push v result))
    (nreverse result)))

(defun pmap-count (map)
  "Return the number of key-value pairs in MAP."
  (fset:size map))

(defun pmap-merge (map1 map2)
  "Return a new map containing all entries from MAP1 and MAP2.
   On key conflict, MAP2 wins."
  (fset:map-union map1 map2))

(defun pmap-to-alist (map)
  "Convert persistent MAP to an association list."
  (let (result)
    (fset:do-map (k v map)
      (push (cons k v) result))
    (nreverse result)))

(defun alist-to-pmap (alist)
  "Convert an association list to a persistent map."
  (fset:convert 'fset:map alist))

(defun pmap-equal (map1 map2)
  "Return T if MAP1 and MAP2 have the same key-value pairs."
  (fset:equal? map1 map2))

(defun pmap-hash (map)
  "Content-addressable hash of MAP."
  (sexpr-hash (pmap-to-alist map)))

(defun pmap-map-values (fn map)
  "Return a new map with FN applied to each value."
  (let ((result (pmap-empty)))
    (fset:do-map (k v map)
      (setf result (pmap-put result k (funcall fn v))))
    result))

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Vectors (wrapping fset:seq)
;;; ═══════════════════════════════════════════════════════════════════

(defun pvec-empty ()
  "Return an empty persistent vector."
  (fset:empty-seq))

(defun pvec-push (vec value)
  "Return a new vector with VALUE appended at the end."
  (fset:with-last vec value))

(defun pvec-ref (vec index)
  "Return the element at INDEX in VEC."
  (fset:@ vec index))

(defun pvec-set (vec index value)
  "Return a new vector with INDEX set to VALUE."
  (fset:with vec index value))

(defun pvec-length (vec)
  "Return the number of elements in VEC."
  (fset:size vec))

(defun pvec-last (vec)
  "Return the last element of VEC, or NIL if empty."
  (if (fset:empty? vec)
      nil
      (fset:last vec)))

(defun pvec-to-list (vec)
  "Convert persistent vector to a list."
  (fset:convert 'list vec))

(defun list-to-pvec (list)
  "Convert a list to a persistent vector."
  (fset:convert 'fset:seq list))

(defun pvec-map (fn vec)
  "Return a new vector with FN applied to each element."
  (fset:image fn vec))

(defun pvec-equal (vec1 vec2)
  "Return T if VEC1 and VEC2 have the same elements in order."
  (fset:equal? vec1 vec2))

(defun pvec-concat (vec1 vec2)
  "Return a new vector that is the concatenation of VEC1 and VEC2."
  (fset:concat vec1 vec2))

(defun pvec-subseq (vec start &optional end)
  "Return a sub-vector from START to END."
  (fset:subseq vec start end))

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Sets (wrapping fset:set)
;;; ═══════════════════════════════════════════════════════════════════

(defun pset-empty ()
  "Return an empty persistent set."
  (fset:empty-set))

(defun pset-add (set element)
  "Return a new set with ELEMENT added."
  (fset:with set element))

(defun pset-remove (set element)
  "Return a new set without ELEMENT."
  (fset:less set element))

(defun pset-contains-p (set element)
  "Return T if SET contains ELEMENT."
  (fset:contains? set element))

(defun pset-count (set)
  "Return the number of elements in SET."
  (fset:size set))

(defun pset-union (set1 set2)
  "Return the union of SET1 and SET2."
  (fset:union set1 set2))

(defun pset-intersection (set1 set2)
  "Return the intersection of SET1 and SET2."
  (fset:intersection set1 set2))

(defun pset-difference (set1 set2)
  "Return elements in SET1 but not in SET2."
  (fset:set-difference set1 set2))

(defun pset-to-list (set)
  "Convert persistent set to a list."
  (fset:convert 'list set))

(defun list-to-pset (list)
  "Convert a list to a persistent set."
  (fset:convert 'fset:set list))

(defun pset-equal (set1 set2)
  "Return T if SET1 and SET2 contain the same elements."
  (fset:equal? set1 set2))

(defun pset-subset-p (set1 set2)
  "Return T if SET1 is a subset of SET2."
  (fset:subset? set1 set2))

(defun pset-hash (set)
  "Content-addressable hash of SET."
  (sexpr-hash (sort (copy-list (pset-to-list set))
                    (lambda (a b)
                      (string< (princ-to-string a) (princ-to-string b))))))
