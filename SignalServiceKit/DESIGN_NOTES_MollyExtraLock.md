# Molly Extra Lock - Key Handling Strategy

## peerExtra Key Pair Derivation

- **`peerExtraPrivate` Derivation Method**: HKDF-SHA256
- **Input Key Material (IKM)**: User's local ACI (Account Identity) `identityPrivateKey`.
  - *Rationale*: The ACI identity is the primary, long-term identity for the account. Using PNI identity might also be an option, but ACI seems more fundamental.
- **Salt**: A unique, fixed string: `"MollyExtraLockPeerKey"`
- **Info/Context (Optional but Recommended)**: A fixed string for domain separation, e.g., `"Signal Molly Peer Extra Key Derivation v1"`
- **Output Length**: 32 bytes (for a 256-bit key, compatible with Curve25519).
- **Derivation Formula**: `peerExtraPrivateKey = HKDF-SHA256(salt: "MollyExtraLockPeerKey", ikm: aciIdentityPrivateKey, info: "Signal Molly Peer Extra Key Derivation v1", outputLength: 32)`
- **Public Key**: `peerExtraPublicKey` will be derived from `peerExtraPrivateKey` using standard Curve25519 scalar multiplication.

## Key Exchange

- **Mechanism**: The `peerExtraPublicKey` will be explicitly exchanged during the device provisioning/linking phase.
- **Protobuf Modification**:
    - The `ProvisionMessage` in `Provisioning.proto` will be augmented with an `optional bytes peer_extra_public_key` field.
    - This key will be sent by the newly linking device to the primary device (and vice-versa if applicable, though typically the primary device dictates or already has its keys).

## Rationale for Derivation from Existing Identity Keys

- **No New Verification Step**: By deriving the `peerExtra` key pair from an existing, verified identity key, we avoid introducing a new, complex, and potentially vulnerable key verification ceremony. The trust in `peerExtraPublicKey` is bootstrapped from the trust in the existing `aciIdentityKey`.
- **Simplicity**: Leverages existing cryptographic primitives and established identity.

## `peerExtraPrivate` Handling

- **On-Demand Derivation**: `peerExtraPrivate` will be derived on-demand by each device when needed for cryptographic operations (e.g., deriving a shared secret with a peer's `peerExtraPublicKey`).
- **Not Stored**: To minimize risk and simplify key management, `peerExtraPrivate` will NOT be stored persistently. It can always be regenerated from the `aciIdentityPrivateKey`. This also means if the ACI identity key changes, the `peerExtra` keys will implicitly change too, which is a desired property.

## Security Considerations
- The salt and info parameters for HKDF must be globally unique and constant for this specific purpose to ensure key uniqueness.
- If the ACI identity key is compromised, the `peerExtraPrivate` key will also be compromised. This is an accepted trade-off for the simplicity gained by avoiding a new verification step. The security of the `peerExtra` key relies on the security of the main identity key.
