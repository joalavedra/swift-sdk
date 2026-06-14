// Entry source for the bundled EIP-7702 helper (Sources/OpenfortSwift/Resources/viem-7702.js).
//
// Build: see js-src/README.md. The bundle defines `window.__ofSend7702`, which sends a gasless
// EIP-7702 user operation from the embedded wallet's EOA, sponsored by an Openfort policy.
//
// Native signing (no key export): the embedded wallet signs the one-time 7702 authorization and
// every user-operation signature through `window.openfort.embeddedWalletInstance`, so the EOA
// private key never leaves Openfort's secure signer. `embeddedWalletInstance.signMessage(hash,
// { hashMessage: false, arrayifyMessage: false })` returns a RAW ECDSA signature over the exact
// 32-byte digest with no EIP-191 prefix — exactly what EIP-7702 authorizations require.

import { createPublicClient, defineChain, http, parseSignature } from 'viem'
import { hashAuthorization } from 'viem/utils'
import { toAccount } from 'viem/accounts'
import { toSimple7702SmartAccount, createBundlerClient, createPaymasterClient } from 'viem/account-abstraction'

// Known chains for the 7702 flow. Anything else is built dynamically from `chainId` + `rpcUrl`.
const CHAINS = {
  84532: { name: 'Base Sepolia', nativeCurrency: { name: 'Sepolia Ether', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: ['https://sepolia.base.org'] } } },
  8453: { name: 'Base', nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 }, rpcUrls: { default: { http: ['https://mainnet.base.org'] } } },
}

// eth-infinitism Simple7702Account — viem's toSimple7702SmartAccount default implementation.
const DEFAULT_IMPLEMENTATION = '0xe6Cae83BdE06E4c305530e199D7217f42808555B'

function buildChain(chainId, rpcUrl) {
  const known = CHAINS[chainId]
  const http = rpcUrl ? [rpcUrl] : known?.rpcUrls.default.http ?? []
  return defineChain({
    id: chainId,
    name: known?.name ?? `Chain ${chainId}`,
    nativeCurrency: known?.nativeCurrency ?? { name: 'Ether', symbol: 'ETH', decimals: 18 },
    rpcUrls: { default: { http } },
  })
}

// Wraps the digest-to-signature primitive the secure signer exposes via the embedded wallet.
// Returns a 0x-prefixed 65-byte ECDSA signature over the exact bytes of `hash`.
async function signDigest(hash) {
  const wallet = window.openfort.embeddedWalletInstance
  const sig = await wallet.signMessage(hash, { hashMessage: false, arrayifyMessage: false })
  return sig.startsWith('0x') ? sig : '0x' + sig
}

// A viem LocalAccount backed by the embedded signer instead of an exported private key.
// Every signing op routes through window.openfort, so the EOA key never leaves the secure signer.
function embeddedOwner(address) {
  return toAccount({
    address,
    async sign({ hash }) {
      return signDigest(hash)
    },
    async signMessage({ message }) {
      const wallet = window.openfort.embeddedWalletInstance
      // viem passes { raw } for bytes or a string; the embedded wallet applies the EIP-191 prefix.
      const value = typeof message === 'object' && message !== null && 'raw' in message ? message.raw : message
      return wallet.signMessage(value)
    },
    async signTypedData({ domain, types, message }) {
      return window.openfort.embeddedWalletInstance.signTypedData(domain, types, message)
    },
    async signAuthorization(authorization) {
      const { chainId, nonce, contractAddress, address: authAddress } = authorization
      const target = contractAddress ?? authAddress
      const hash = hashAuthorization({ chainId, nonce, address: target })
      const { r, s, yParity } = parseSignature(await signDigest(hash))
      // viem serializes the authorization from `address` (the implementation), so set it explicitly.
      return { address: target, chainId, nonce, r, s, yParity, v: yParity === 0 ? 27n : 28n }
    },
    async signTransaction() {
      throw new Error('signTransaction is not supported by the embedded EIP-7702 signer')
    },
  })
}

// Sends a gasless EIP-7702 user operation from the embedded wallet's EOA.
//
// args: { to, data, value, policyId, publishableKey, chainId?, implementationAddress?, rpcUrl? }
// Returns the userOp/tx hash.
window.__ofSend7702 = async function (args) {
  const {
    to, data, value, policyId, publishableKey,
    chainId = 84532,
    implementationAddress = DEFAULT_IMPLEMENTATION,
    rpcUrl,
  } = args

  const chain = buildChain(Number(chainId), rpcUrl)
  const bundlerRpc = `https://api.openfort.io/rpc/${chain.id}`

  const stored = await window.openfort.embeddedWalletInstance.get()
  const ownerAddress = stored?.address
  if (!ownerAddress) throw new Error('No embedded wallet account; configure the embedded wallet first')
  const owner = embeddedOwner(ownerAddress)

  const publicClient = createPublicClient({ chain, transport: http() })
  const account = await toSimple7702SmartAccount({ client: publicClient, owner, implementation: implementationAddress })

  const headers = { Authorization: 'Bearer ' + publishableKey }
  const paymaster = createPaymasterClient({ transport: http(bundlerRpc, { fetchOptions: { headers } }) })
  const bundler = createBundlerClient({
    account, paymaster, client: publicClient,
    transport: http(bundlerRpc, { fetchOptions: { headers } }),
  })

  const authorization = await owner.signAuthorization({
    contractAddress: implementationAddress,
    chainId: chain.id,
    nonce: await publicClient.getTransactionCount({ address: ownerAddress }),
  })

  const hash = await bundler.sendUserOperation({
    calls: [{ to, data: data || '0x', value: BigInt(value || 0) }],
    authorization,
    paymasterContext: { policyId },
  })
  return hash
}
