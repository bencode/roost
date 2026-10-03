// Just enough of a Scheme reader for the development server: top-level form
// boundaries, module headers, record definitions, and the libraries a file imports.
// Lists read as arrays and every other datum as its source text.

const delimiter = /[\s()";]/

const skipAtmosphere = (text, i) => {
  while (i < text.length) {
    if (/\s/.test(text[i])) i += 1
    else if (text[i] === ';') i = text.indexOf('\n', i) === -1 ? text.length : text.indexOf('\n', i)
    else if (text.startsWith('#|', i)) i = closing(text, '|#', i) + 2
    else if (text.startsWith('#;', i)) i = readDatum(text, skipAtmosphere(text, i + 2)).end
    else return i
  }
  return i
}

const incomplete = () => new Error('scheme-source: incomplete form')

const closing = (text, token, from) => {
  const at = text.indexOf(token, from)
  if (at === -1) throw incomplete()
  return at
}

const readString = (text, i) => {
  let j = i + 1
  while (text[j] !== '"') {
    if (j >= text.length) throw incomplete()
    j += text[j] === '\\' ? 2 : 1
  }
  return { datum: text.slice(i, j + 1), end: j + 1 }
}

const readList = (text, i) => {
  const datum = []
  let j = skipAtmosphere(text, i)
  while (text[j] !== ')') {
    if (j >= text.length) throw incomplete()
    const item = readDatum(text, j)
    datum.push(item.datum)
    j = skipAtmosphere(text, item.end)
  }
  return { datum, end: j + 1 }
}

function readDatum(text, i) {
  if (text[i] === '(') return readList(text, i + 1)
  if (text[i] === '"') return readString(text, i)
  if (text.startsWith('#\\', i)) {
    let j = i + 3
    while (j < text.length && !delimiter.test(text[j])) j += 1
    return { datum: text.slice(i, j), end: j }
  }
  const vector = text.slice(i).match(/^(#vu8|#u8|#)\(/)
  if (vector) return readList(text, i + vector[0].length)
  const quote = text.slice(i).match(/^(,@|'|`|,)/)
  if (quote) return readDatum(text, i + quote[0].length)
  let j = i
  while (j < text.length && !delimiter.test(text[j])) j += 1
  return { datum: text.slice(i, j), end: j }
}

export const readForms = text => {
  const forms = []
  let i = skipAtmosphere(text, 0)
  while (i < text.length) {
    const { datum, end } = readDatum(text, i)
    forms.push({ start: i, end, datum })
    i = skipAtmosphere(text, end)
  }
  return forms
}

const head = form => Array.isArray(form.datum) && form.datum[0]
const show = datum => (Array.isArray(datum) ? `(${datum.map(show).join(' ')})` : datum)

export const moduleHeader = text => {
  const [first] = readForms(text)
  return first && head(first) === 'define-module' ? { name: show(first.datum[1]), text: text.slice(first.start, first.end) } : null
}

// The parts of a module that reloading cannot change in place: its header and its
// record types. When they change, the page must load the module afresh.
export const moduleStructure = text =>
  readForms(text)
    .filter((form, index) => index === 0 || head(form) === 'define-record-type')
    .map(form => text.slice(form.start, form.end))
    .join('\n')

const unwrapImport = spec =>
  Array.isArray(spec) && ['only', 'prefix', 'except', 'rename'].includes(spec[0]) ? unwrapImport(spec[1]) : spec

const guileImport = spec => (Array.isArray(spec[0]) ? spec[0] : spec)

// Library names, as source text, imported by a program, define-library, or define-module.
export const importedLibraries = text =>
  readForms(text).flatMap(form => {
    if (head(form) === 'import') return form.datum.slice(1).map(spec => show(unwrapImport(spec)))
    if (head(form) === 'define-library')
      return form.datum
        .filter(clause => Array.isArray(clause) && clause[0] === 'import')
        .flatMap(clause => clause.slice(1).map(spec => show(unwrapImport(spec))))
    if (head(form) === 'define-module')
      return form.datum.flatMap((item, i) => (item === '#:use-module' ? [show(guileImport(form.datum[i + 1]))] : []))
    return []
  })

// A program (import ...) body... as a library, so the interpreter can load it.
export const programAsLibrary = (text, name) => {
  const [imports, ...body] = readForms(text)
  if (head(imports) !== 'import') throw new Error('scheme-source: a program must start with import')
  const rest = body.length ? text.slice(body[0].start) : ''
  return `(define-library ${name}\n  (export)\n  ${text.slice(imports.start, imports.end)}\n  (begin\n${rest}))\n`
}
