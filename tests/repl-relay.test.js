// The relay passes the REPL whole inputs: a form typed over several lines must arrive
// as one, or the page would read half a form.
import { describe, expect, it } from 'vitest'
import { inputSplitter } from '../tooling/repl-relay.js'

describe('inputSplitter', () => {
  it('passes complete lines on at once', () => {
    const split = inputSplitter()
    expect(split('(+ 1 2)\n')).toEqual(['(+ 1 2)\n'])
    expect(split('(car 1) (cdr 2)\n')).toEqual(['(car 1) (cdr 2)\n'])
  })

  it('waits for the rest of a form typed over several lines', () => {
    const split = inputSplitter()
    expect(split('(define (f x)\n')).toEqual([])
    expect(split('  (* x 2))\n')).toEqual(['(define (f x)\n  (* x 2))\n'])
  })

  it('takes a meta-command as its line', () => {
    const split = inputSplitter()
    expect(split(',m (store cart)\n(cart-count c)\n')).toEqual([',m (store cart)\n', '(cart-count c)\n'])
    expect(split(',apropos cart-\n')).toEqual([',apropos cart-\n'])
  })

  it('waits for the end of a line', () => {
    const split = inputSplitter()
    expect(split('(+ 1')).toEqual([])
    expect(split(' 2)\n')).toEqual(['(+ 1 2)\n'])
  })

  it('leaves a malformed line to the REPL to report', () => {
    expect(inputSplitter()('(a))\n')).toEqual(['(a))\n'])
  })
})
