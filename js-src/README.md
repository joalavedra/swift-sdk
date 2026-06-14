# js-src — bundled WebView JavaScript sources

Source for the prebuilt JS bundles checked into `Sources/OpenfortSwift/Resources/`. The bundles are
committed so the SwiftPM package needs no Node toolchain to build; this directory keeps them
reproducible.

## viem-7702-entry.js → Resources/viem-7702.js

EIP-7702 send helper. Defines `window.__ofSend7702(args)` inside the SDK WebView: signs the one-time
7702 authorization and the user operation with the embedded wallet's signer (no private-key export)
and submits a sponsored userOp via Openfort's bundler + paymaster.

### Build

```sh
mkdir -p /tmp/viem7702 && cd /tmp/viem7702
npm init -y >/dev/null
npm install viem@^2.52.2 esbuild@^0.28.1
cp /path/to/repo/js-src/viem-7702-entry.js entry.js
./node_modules/.bin/esbuild entry.js \
  --bundle --format=iife --platform=browser --target=es2020 \
  --outfile=/path/to/repo/Sources/OpenfortSwift/Resources/viem-7702.js
```

`--format=iife` so it runs as a single `WKUserScript`; `--platform=browser` so viem uses the
WebView's `fetch`/`crypto`. After rebuilding, confirm the bundle still defines the helper and pulls
in the expected viem APIs:

```sh
grep -oE "window.__ofSend7702|toSimple7702SmartAccount|hashAuthorization|sendUserOperation" \
  Sources/OpenfortSwift/Resources/viem-7702.js | sort -u
```
