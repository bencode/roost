;; Host Guile stand-in for Hoot's (hoot keywords), so the Guile tests can load Roost's
;; libraries. Roost imports Hoot's small libraries because importing (guile) makes
;; every Hoot build expand all of Guile's compatibility library.
(define-module (hoot keywords)
  #:re-export (keyword? keyword->symbol symbol->keyword))
