// Entry for the bundled `Resources/openfort.js` loaded into the SDK WebView.
//
// Exposes the openfort-js `Openfort` class as a global so `OFConfig.openfortSyncScript`
// can `new Openfort({ baseConfiguration, shieldConfiguration, overrides: { storage } })`
// and assign `window.openfort`. The bridge (`openfort-sync.js`) then calls
// `window.openfort.authInstance.*` / `window.openfort.embeddedWalletInstance.*` — these
// are TypeScript-`private` fields, which are erased at runtime, so esbuild preserves them
// as ordinary properties (do NOT enable property mangling).
import { Openfort } from '@openfort/openfort-js'

globalThis.Openfort = Openfort
