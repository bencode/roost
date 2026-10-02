import { kernel } from './roost-kernel.js'

// Scheme is the class exported by Hoot's reflect.js; callers pass it in so the loader
// works with or without the Vite plugin. The application starts itself from Scheme.
export const boot = ({ Scheme, wasm, modules = {}, reflectWasmDir }) =>
  Scheme.load_main(wasm, {
    reflect_wasm_dir: reflectWasmDir,
    user_imports: { roost: kernel({ global: globalThis, ...modules }) },
  })
