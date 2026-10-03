// The development server reads every saved file; a malformed one must fail, not hang
// the server (a stray closing parenthesis once looped until the heap ran out).
import { describe, expect, it } from 'vitest'
import { moduleHeader, readForms } from '../tooling/scheme-source.js'

describe('scheme-source', () => {
  it('reads top-level forms with strings, characters, comments and vectors', () => {
    const text = '(a #\\( "x)" #;(skip) \'(q) #(1 2) #:k) ; note\n#| block |# (b)'
    expect(readForms(text).map(form => form.datum)).toEqual([['a', '#\\(', '"x)"', ['q'], ['1', '2'], '#:k'], ['b']])
    expect(moduleHeader('(define-module (store cart)\n  #:pure)').name).toBe('(store cart)')
  })

  it.each([
    ['a stray closing parenthesis', '(a) )', 'unbalanced closing parenthesis'],
    ['an unclosed list', '(a (b)', 'incomplete form'],
    ['an unclosed string', '(a "text', 'incomplete form'],
    ['an unclosed block comment', '(a) #| comment', 'incomplete form'],
  ])('rejects %s', (_, text, message) => {
    expect(() => readForms(text)).toThrow(message)
  })
})
