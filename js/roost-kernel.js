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
  // Calls with exactly 0 to 3 arguments, avoiding an argument array.
  call0: (fn, self) => guarded(() => fn.call(self)),
  call1: (fn, self, a) => guarded(() => fn.call(self, a)),
  call2: (fn, self, a, b) => guarded(() => fn.call(self, a, b)),
  call3: (fn, self, a, b, c) => guarded(() => fn.call(self, a, b, c)),
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
  // 0 undefined, 1 null, 2 boolean, 3 number, 4 string, 5 function, 6 object, 7 other.
  typeCode: value =>
    value === null ? 1 : ({ undefined: 0, boolean: 2, number: 3, string: 4, function: 5, object: 6 })[typeof value] ?? 7,
  weakMap: () => new WeakMap(),
  weakGet: (map, key) => (map.has(key) ? map.get(key) : null),
  weakSet: (map, key, value) => guarded(() => void map.set(key, value)),
  toNumber: value => value,
  toString: value => value,
  toBoolean: value => (value ? 1 : 0),
  string: value => value,
  number: value => value,
  boolean: value => value !== 0,
  undefined: () => undefined,
})
