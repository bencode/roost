;; Roost's playground: write a module, run it, and try it in a REPL, all in the page.
;; It is compiled with Hoot's run-time module system (see vite.config.js), so the code
;; written in it runs in Hoot's interpreter.
;;
;; A program holds only the libraries it imports, so every library playground code can
;; import is imported here, even those this program does not use.
(import (scheme base)
        (scheme char)
        (scheme write)
        (prefix (roost dom) h/)
        (prefix (roost hooks) hooks/)
        (only (roost react) render-root)
        (only (roost hiccup) component)
        (only (roost props) props)
        (prefix (roost js) js/)
        (only (lab workspace) make-workspace)
        (only (views playground) playground))

;; The npm packages playground code can use with js/module, besides React. The build
;; bundles the packages named in the program's source.
(js/module "react-router-dom")

(render-root (component playground (props #:workspace (make-workspace))) "playground")
