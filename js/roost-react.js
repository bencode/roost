// React builder: Scheme walks a Hiccup tree and drives these functions through direct,
// fixed-type calls; the builder assembles standard React elements on a frame stack.
// Names arrive already converted and cached. Immutable Scheme strings (literals) are
// passed as objects and looked up in a WeakMap, so each converts to JavaScript once.
//
// Frames: element {type, props, children} becomes React.createElement(type, props,
// ...children), keeping trailing children static; object {object} and array {array}
// become plain JavaScript data (an array child is a dynamic collection).
export const reactBuilder = () => {
  let React
  let dispatch
  const stack = []
  const texts = new WeakMap()
  // Calls with a string object return 0 when it is not yet known; Scheme then
  // remembers it and calls again.
  const withText = (string, use) => {
    const text = texts.get(string)
    if (text === undefined) return 0
    use(text)
    return 1
  }

  const top = () => stack[stack.length - 1]
  const field = (name, value) => {
    const frame = top()
    ;(frame.props ?? frame.object)[name] = value
  }
  const item = value => {
    const frame = top()
    ;(frame.children ?? frame.array).push(value)
  }
  const close = () => {
    const frame = stack.pop()
    return frame.props ? React.createElement(frame.type, frame.props, ...frame.children) : (frame.object ?? frame.array)
  }

  return {
    setup: (react, onDispatch) => {
      React = react
      dispatch = onDispatch
    },
    // begin returns the depth so that Scheme can restore the stack after an error.
    begin: () => stack.push({ array: [] }),
    finish: () => stack.pop().array[0],
    reset: depth => {
      stack.length = depth - 1
    },
    openElement: type => {
      stack.push({ type, props: {}, children: [] })
    },
    remember: (string, text) => {
      texts.set(string, text)
    },
    openTagText: string => withText(string, type => stack.push({ type, props: {}, children: [] })),
    fieldText: (name, string) => withText(string, text => field(name, text)),
    itemText: string => withText(string, item),
    openObject: () => {
      stack.push({ object: {} })
    },
    openArray: () => {
      stack.push({ array: [] })
    },
    closeItem: () => item(close()),
    closeField: name => field(name, close()),
    // Declared in Scheme with different parameter types; JavaScript shares one body.
    field,
    fieldBool: (name, flag) => field(name, flag !== 0),
    fieldUndefined: name => field(name, undefined),
    // DOM event handlers: a fresh function per render, like an inline handler in JSX.
    fieldHandler: (name, procedure) => field(name, (...args) => dispatch(procedure, ...args)),
    item,
    itemBool: flag => item(flag !== 0),
  }
}
