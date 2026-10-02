// Generic JavaScript primitives that Hoot does not provide. Everything else, including
// the React bindings, is written in Scheme on top of these. Keep this file stable.

const THROWN = Object.freeze({})
let lastError

const guarded = thunk => {
  try {
    return thunk()
  } catch (error) {
    lastError = error
    return THROWN
  }
}

export const kernel = modules => ({
  module: name => modules[name],
  get: (object, key) => guarded(() => object[key]),
  set: (object, key, value) =>
    guarded(() => {
      object[key] = value
    }),
  object: () => ({}),
  array: () => [],
  push: (array, value) => {
    array.push(value)
  },
  apply: (fn, self, args) => guarded(() => fn.apply(self, args)),
  construct: (ctor, args) => guarded(() => new ctor(...args)),
  thrown: value => (value === THROWN ? 1 : 0),
  lastError: () => lastError,
  // The adapter receives a frame instead of converted arguments, which bypasses
  // Hoot's reflection conversions (they reject undefined and rewrap Scheme values).
  // A Scheme exception comes back as frame.error and is thrown here as JavaScript.
  fn: (adapter, length) =>
    Object.defineProperty(
      (...args) => {
        const frame = { args, result: undefined, failed: false, error: undefined }
        adapter(frame)
        if (frame.failed) throw frame.error
        return frame.result
      },
      'length',
      { value: length },
    ),
  typeOf: value => (value === null ? 'null' : typeof value),
  toNumber: value => value,
  toString: value => value,
  toBoolean: value => (value ? 1 : 0),
  opaque: value => value,
  string: value => value,
  number: value => value,
  boolean: value => value !== 0,
  undefined: () => undefined,
})
