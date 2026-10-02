# Roost

Scheme-first React bindings powered by Guile Hoot.

Roost 正在设计中，目标是用 Scheme 编写 React 应用，经 Hoot 编译为 WebAssembly，由库内的 JavaScript 桥接连接 React。

设计采用 Hiccup 表达 UI，使用 React 原生 Hooks，并保留 Scheme 的表达式、词法作用域和模块导入方式。

当前尚无可安装的 Roost 库，具体 API 仍在设计。已确认的方向见 [设计原则](docs/design-principles.md)。
