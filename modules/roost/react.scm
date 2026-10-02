(define-library (roost react)
  (export render-root)
  (import (scheme base)
          (scheme lazy)
          (only (guile) keyword->symbol)
          (roost props)
          (prefix (roost js) js/))
  (begin
    ;; Lazy: Hoot evaluates library bodies at expansion time, where JavaScript is absent.
    (define react (delay (js/module "react")))
    (define create-element-procedure (delay (js/ref (force react) "createElement")))
    (define (create-element . args) (apply (force create-element-procedure) args))
    (define fragment (delay (js/ref (force react) "Fragment")))

    ;; Two or more trailing children of a component. Forwarded through a Fragment so
    ;; React treats them as static children (no key checks), unlike dynamic lists.
    (define-record-type <static-children>
      (make-static-children items)
      static-children?
      (items static-children-items))

    ;; One React type per render procedure, keyed by the procedure itself in a WeakMap
    ;; so render procedures created on the fly can be collected. React calls components
    ;; as (props, undefined); length 1 passes only props.
    (define component-types (delay (js/new (js/ref js/global "WeakMap"))))

    (define (render->react-type render)
      (let ((types (force component-types)))
        (or (js/method types "get" render)
            (let ((type (js/function
                         (lambda (js-props)
                           (node->react (render (js/ref js-props "roostProps"))))
                         1)))
              (js/method types "set" render type)
              type))))

    (define (split-contents node)
      (let ((contents (cdr (vector->list node))))
        (if (and (pair? contents) (props? (car contents)))
            (values (car contents) (cdr contents))
            (values #f contents))))

    (define (entries attributes)
      (if attributes (props-entries attributes) '()))

    (define (entries->props entries)
      (apply props (append-map (lambda (e) (list (car e) (cdr e))) entries)))

    (define (append-map f items)
      (apply append (map f items)))

    (define (react-key value)
      (cond
       ((string? value) value)
       ((exact-integer? value) (number->string value))
       (else (error "node->react: key must be a string or an exact integer" value))))

    (define (without-keys entries keys)
      (let loop ((rest entries) (acc '()))
        (cond
         ((null? rest) (reverse acc))
         ((memq (caar rest) keys) (loop (cdr rest) acc))
         (else (loop (cdr rest) (cons (car rest) acc))))))

    ;; Trailing children become #:children: none keeps the explicit value, one is kept as
    ;; is, several form a static collection. #:key goes to React, not to the component.
    (define (component-element render attributes children)
      (let* ((given (entries attributes))
             (key (assq #:key given))
             (forwarded
              (cond
               ((null? children) #f)
               ((null? (cdr children)) (car children))
               (else (make-static-children children))))
             (component-props
              (if (and (not key) (null? children) attributes)
                  attributes
                  (entries->props
                   (append (without-keys given (if (null? children) '(#:key) '(#:key #:children)))
                           (if (null? children) '() (list (cons #:children forwarded)))))))
             (config (if key
                         (js/object "roostProps" component-props "key" (react-key (cdr key)))
                         (js/object "roostProps" component-props))))
        (create-element (render->react-type render) config)))

    (define (dom-name keyword)
      (let ((name (symbol->string (keyword->symbol keyword))))
        (cond
         ((string=? name "class") "className")
         ((string=? name "for") "htmlFor")
         ((or (string-prefix? "aria-" name) (string-prefix? "data-" name)) name)
         (else (js/property-name keyword)))))

    (define (string-prefix? prefix s)
      (and (<= (string-length prefix) (string-length s))
           (string=? prefix (substring s 0 (string-length prefix)))))

    (define (style-name keyword)
      (let ((name (symbol->string (keyword->symbol keyword))))
        (if (string-prefix? "--" name) name (js/property-name keyword))))

    (define (dom-value value)
      (if (or (string? value) (real? value) (boolean? value) (procedure? value) (js/value? value))
          value
          (error "node->react: unsupported DOM property value" value)))

    (define (style-object style)
      (unless (props? style)
        (error "node->react: #:style must be a props value" style))
      (apply js/object
             (append-map (lambda (e)
                           (let ((value (cdr e)))
                             (unless (or (string? value) (real? value))
                               (error "node->react: unsupported style value" value))
                             (list (style-name (car e)) value)))
                         (props-entries style))))

    (define (dom-config attributes)
      (apply js/object
             (append-map
              (lambda (e)
                (let ((key (car e)) (value (cdr e)))
                  (cond
                   ((eq? key #:key) (list "key" (react-key value)))
                   ((eq? key #:children) (list "children" (node->react value)))
                   ((eq? key #:style) (list "style" (style-object value)))
                   (else (list (dom-name key) (dom-value value))))))
              (entries attributes))))

    ;; Props of JavaScript components are plain JavaScript data.
    (define (js-component-config attributes)
      (apply js/object
             (append-map (lambda (e) (list (js/property-name (car e)) (js/from-scheme (cdr e))))
                         (entries attributes))))

    (define (node-element node)
      (let-values (((attributes children) (split-contents node)))
        (let ((type (vector-ref node 0)))
          (cond
           ((string? type)
            (apply create-element type (dom-config attributes) (map node->react children)))
           ((or (js/value? type) (js/function? type))
            (apply create-element type (js-component-config attributes) (map node->react children)))
           ((procedure? type)
            (component-element type attributes children))
           (else (error "node->react: unsupported node type" type))))))

    (define (node->react child)
      (cond
       ((and (vector? child) (> (vector-length child) 0)) (node-element child))
       ((or (string? child) (real? child) (boolean? child) (js/value? child)) child)
       ((list? child) (apply js/array (map node->react child)))
       ((static-children? child)
        (apply create-element (force fragment) (js/object) (map node->react (static-children-items child))))
       (else (error "node->react: unsupported child" child))))

    (js/set-node-converter! node->react)

    (define (render-root node element-id)
      (let* ((document (js/ref js/global "document"))
             (create-root (js/ref (js/module "react-dom/client") "createRoot"))
             (root (create-root (js/method document "getElementById" element-id))))
        (js/method root "render" (node->react node))
        root))))
