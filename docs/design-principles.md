# Roost 设计原则

状态：设计阶段。本文记录已确认的方向，不代表库或示例 API 已实现。

## Scheme 应用与 React 运行时

应用组件、事件处理和业务逻辑以 Scheme 编写，经 Guile Hoot 编译为 Wasm。库内的 JavaScript 桥接负责连接 React；应用作者无需为每个组件手写 JavaScript 包装。

UI 采用 Hiccup 表达。书写方式沿用 Scheme 的表达式、词法绑定和函数组合，利用宏能力组织构造语法；不以 quasiquote/unquote 作为默认 UI 写法。节点的内部表示和组件构造接口仍待定。

props 使用独立类型，以 `(props #:class "card")` 构造，与节点和 children 集合按类型区分。属性名称到 React 的映射规则仍待定。

## React 原生 Hooks

状态、更新调度、渲染、effect 和 cleanup 由 React 承担。Roost 不引入 ratom、reaction、自动依赖追踪或独立更新队列。

桥接层遵守 React Hooks 调用规则，保留状态更新语义及依赖逐项 `Object.is` 比较；同一个 Scheme 值不应因重复包装而制造依赖变化。[Hooks 规则](https://react.dev/reference/rules/rules-of-hooks)、[useEffect](https://react.dev/reference/react/useEffect)

## 模块导入与名称

DOM 模块导出普通标签名称。文档默认通过 `#:prefix h/` 导入；需要短名称时，通过 `#:select` 显式导入。标签不自动注入应用作用域，库不增加自定义导入语法。[Guile 模块导入](https://www.gnu.org/software/guile/manual/html_node/Using-Guile-Modules.html)

下面展示拟定模块的导入风格；模块及标签构造器尚未实现。

```scheme
(use-modules ((roost dom) #:prefix h/)
             ((roost props) #:select (props)))

(h/section
  (props #:class "card")
  (h/h2 title)
  (h/p "Hello"))
```

也允许在调用模块中选择短名称：

```scheme
(use-modules ((roost dom) #:select (section h2 p)))

(section (h2 title) (p "Hello"))
```

前缀由调用者选择。`h/section` 是导入后的 Scheme 标识符，节点构造的具体 API 仍在设计。
