(define-library (roost dom)
  ;; WHATWG HTML elements except html, head and body.
  (export a abbr address area article aside audio b base bdi bdo blockquote br button
          canvas caption cite code col colgroup data datalist dd del details dfn dialog div
          dl dt em embed fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header
          hgroup hr i iframe img input ins kbd label legend li link main map mark menu meta
          meter nav noscript object ol optgroup option output p picture pre progress q rp rt
          ruby s samp script search section select slot small source span strong style sub
          summary sup table tbody td template textarea tfoot th thead time title tr track u ul
          var video wbr)
  ;; The map element shadows Scheme's map inside this library.
  (import (except (scheme base) map)
          (roost hiccup))
  (begin
    (define-syntax define-dom-tags
      (syntax-rules ()
        ((_ (name tag) ...)
         (begin
           (define (name . contents)
             (apply make-node tag contents))
           ...))))

    (define-dom-tags
      (a "a") (abbr "abbr") (address "address") (area "area") (article "article")
      (aside "aside") (audio "audio") (b "b") (base "base") (bdi "bdi") (bdo "bdo")
      (blockquote "blockquote") (br "br") (button "button") (canvas "canvas")
      (caption "caption") (cite "cite") (code "code") (col "col") (colgroup "colgroup")
      (data "data") (datalist "datalist") (dd "dd") (del "del") (details "details")
      (dfn "dfn") (dialog "dialog") (div "div") (dl "dl") (dt "dt") (em "em")
      (embed "embed") (fieldset "fieldset") (figcaption "figcaption") (figure "figure")
      (footer "footer") (form "form") (h1 "h1") (h2 "h2") (h3 "h3") (h4 "h4") (h5 "h5")
      (h6 "h6") (header "header") (hgroup "hgroup") (hr "hr") (i "i") (iframe "iframe")
      (img "img") (input "input") (ins "ins") (kbd "kbd") (label "label") (legend "legend")
      (li "li") (link "link") (main "main") (map "map") (mark "mark") (menu "menu")
      (meta "meta") (meter "meter") (nav "nav") (noscript "noscript") (object "object")
      (ol "ol") (optgroup "optgroup") (option "option") (output "output") (p "p")
      (picture "picture") (pre "pre") (progress "progress") (q "q") (rp "rp") (rt "rt")
      (ruby "ruby") (s "s") (samp "samp") (script "script") (search "search")
      (section "section") (select "select") (slot "slot") (small "small")
      (source "source") (span "span") (strong "strong") (style "style") (sub "sub")
      (summary "summary") (sup "sup") (table "table") (tbody "tbody") (td "td")
      (template "template") (textarea "textarea") (tfoot "tfoot") (th "th")
      (thead "thead") (time "time") (title "title") (tr "tr") (track "track") (u "u")
      (ul "ul") (var "var") (video "video") (wbr "wbr"))))
