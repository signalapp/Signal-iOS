// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Clibsodium
import Sodium
import Curve25519Kit
import SessionUtilitiesKit

/// These extenion methods are used to generate a sign "blinded" messages
///
/// According to the Swift engineers the only situation when `UnsafeRawBufferPointer.baseAddress` is nil is when it's an
/// empty collection; as such our guard cases wihch return `-1` when unwrapping this value should never be hit and we can ignore
/// them as possible results.
///
/// For more information see:
/// https://forums.swift.org/t/when-is-unsafemutablebufferpointer-baseaddress-nil/32136/5
/// https://github.com/apple/swift-evolution/blob/master/proposals/0055-optional-unsafe-pointers.md#unsafebufferpointer
extension Sodium {
    private static let scalarLength: Int = Int(crypto_core_ed25519_scalarbytes())   // 32
    private static let noClampLength: Int = Int(Sodium.lib_crypto_scalarmult_ed25519_bytes())  // 32
    private static let scalarMultLength: Int = Int(crypto_scalarmult_bytes())       // 32
    private static let publicKeyLength: Int = Int(crypto_scalarmult_bytes())        // 32
    private static let secretKeyLength: Int = Int(crypto_sign_secretkeybytes())     // 64
    
    /// 64-byte blake2b hash then reduce to get the blinding factor
    public func generateBlindingFactor(serverPublicKey: String, genericHash: GenericHashType) -> Bytes? {
        /// k = salt.crypto_core_ed25519_scalar_reduce(blake2b(server_pk, digest_size=64).digest())
        let serverPubKeyData: Data = Data(hex: serverPublicKey)
        
        guard !serverPubKeyData.isEmpty, let serverPublicKeyHashBytes: Bytes = genericHash.hash(message: [UInt8](serverPubKeyData), outputLength: 64) else {
            return nil
        }
        
        /// Reduce the server public key into an ed25519 scalar (`k`)
        let kPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        
        _ = serverPublicKeyHashBytes.withUnsafeBytes { (serverPublicKeyHashPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let serverPublicKeyHashBaseAddress: UnsafePointer<UInt8> = serverPublicKeyHashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1   // Impossible case (refer to comments at top of extension)
            }
            
            Sodium.lib_crypto_core_ed25519_scalar_reduce(kPtr, serverPublicKeyHashBaseAddress)
            return 0
        }
        
        return Data(bytes: kPtr, count: Sodium.scalarLength).bytes
    }
    
    /// Calculate k*a.  To get 'a' (the Ed25519 private key scalar) we call the sodium function to
    /// convert to an *x* secret key, which seems wrong--but isn't because converted keys use the
    /// same secret scalar secret (and so this is just the most convenient way to get 'a' out of
    /// a sodium Ed25519 secret key)
    func generatePrivateKeyScalar(secretKey: Bytes) -> Bytes {
        /// a = s.to_curve25519_private_key().encode()
        let aPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarMultLength)
        
        /// Looks like the `crypto_sign_ed25519_sk_to_curve25519` function can't actually fail so no need to verify the result
        /// See: https://github.com/jedisct1/libsodium/blob/master/src/libsodium/crypto_sign/ed25519/ref10/keypair.c#L70
        _ = secretKey.withUnsafeBytes { (secretKeyPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let secretKeyBaseAddress: UnsafePointer<UInt8> = secretKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1   // Impossible case (refer to comments at top of extension)
            }
            
            return crypto_sign_ed25519_sk_to_curve25519(aPtr, secretKeyBaseAddress)
        }
        
        return Data(bytes: aPtr, count: Sodium.scalarMultLength).bytes
    }
    
    /// Constructs a "blinded" key pair (`ka, kA`) based on an open group server `publicKey` and an ed25519 `keyPair`
    public func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair? {
        guard edKeyPair.publicKey.count == Sodium.publicKeyLength && edKeyPair.secretKey.count == Sodium.secretKeyLength else {
            return nil
        }
        guard let kBytes: Bytes = generateBlindingFactor(serverPublicKey: serverPublicKey, genericHash: genericHash) else {
            return nil
        }
        let aBytes: Bytes = generatePrivateKeyScalar(secretKey: edKeyPair.secretKey)
        
        /// Generate the blinded key pair `ka`, `kA`
        let kaPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.secretKeyLength)
        let kAPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.publicKeyLength)
        
        _ = aBytes.withUnsafeBytes { (aPtr: UnsafeRawBufferPointer) -> Int32 in
            return kBytes.withUnsafeBytes { (kPtr: UnsafeRawBufferPointer) -> Int32 in
                guard let kBaseAddress: UnsafePointer<UInt8> = kPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1   // Impossible case (refer to comments at top of extension)
                }
                guard let aBaseAddress: UnsafePointer<UInt8> = aPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1   // Impossible case (refer to comments at top of extension)
                }
                
                Sodium.lib_crypto_core_ed25519_scalar_mul(kaPtr, kBaseAddress, aBaseAddress)
                return 0
            }
        }
        
        guard crypto_scalarmult_ed25519_base_noclamp(kAPtr, kaPtr) == 0 else { return nil }
        
        return Box.KeyPair(
            publicKey: Data(bytes: kAPtr, count: Sodium.publicKeyLength).bytes,
            secretKey: Data(bytes: kaPtr, count: Sodium.secretKeyLength).bytes
        )
    }
    
    /// Constructs an Ed25519 signature from a root Ed25519 key and a blinded scalar/pubkey pair, with one tweak to the
    /// construction: we add kA into the hashed value that yields r so that we have domain separation for different blinded
    /// pubkeys (this doesn't affect verification at all)
    public func sogsSignature(message: Bytes, secretKey: Bytes, blindedSecretKey ka: Bytes, blindedPublicKey kA: Bytes) -> Bytes? {
        /// H_rh = sha512(s.encode()).digest()[32:]
        let H_rh: Bytes = Bytes(secretKey.sha512().suffix(32))

        /// r = salt.crypto_core_ed25519_scalar_reduce(sha512_multipart(H_rh, kA, message_parts))
        let combinedHashBytes: Bytes = (H_rh + kA + message).sha512()
        let rPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        
        _ = combinedHashBytes.withUnsafeBytes { (combinedHashPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let combinedHashBaseAddress: UnsafePointer<UInt8> = combinedHashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1   // Impossible case (refer to comments at top of extension)
            }
            
            Sodium.lib_crypto_core_ed25519_scalar_reduce(rPtr, combinedHashBaseAddress)
            return 0
        }
        
        /// sig_R = salt.crypto_scalarmult_ed25519_base_noclamp(r)
        let sig_RPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.noClampLength)
        guard crypto_scalarmult_ed25519_base_noclamp(sig_RPtr, rPtr) == 0 else { return nil }
        
        /// HRAM = salt.crypto_core_ed25519_scalar_reduce(sha512_multipart(sig_R, kA, message_parts))
        let sig_RBytes: Bytes = Data(bytes: sig_RPtr, count: Sodium.noClampLength).bytes
        let HRAMHashBytes: Bytes = (sig_RBytes + kA + message).sha512()
        let HRAMPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        
        _ = HRAMHashBytes.withUnsafeBytes { (HRAMHashPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let HRAMHashBaseAddress: UnsafePointer<UInt8> = HRAMHashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1   // Impossible case (refer to comments at top of extension)
            }
            
            Sodium.lib_crypto_core_ed25519_scalar_reduce(HRAMPtr, HRAMHashBaseAddress)
            return 0
        }
        
        /// sig_s = salt.crypto_core_ed25519_scalar_add(r, salt.crypto_core_ed25519_scalar_mul(HRAM, ka))
        let sig_sMulPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        let sig_sPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        
        _ = ka.withUnsafeBytes { (kaPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let kaBaseAddress: UnsafePointer<UInt8> = kaPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1   // Impossible case (refer to comments at top of extension)
            }
            
            Sodium.lib_crypto_core_ed25519_scalar_mul(sig_sMulPtr, HRAMPtr, kaBaseAddress)
            Sodium.lib_crypto_core_ed25519_scalar_add(sig_sPtr, rPtr, sig_sMulPtr)
            return 0
        }
        
        /// full_sig = sig_R + sig_s
        return (Data(bytes: sig_RPtr, count: Sodium.noClampLength).bytes + Data(bytes: sig_sPtr, count: Sodium.scalarLength).bytes)
    }
    
    /// Combines two keys (`kA`)
    public func combineKeys(lhsKeyBytes: Bytes, rhsKeyBytes: Bytes) -> Bytes? {
        let combinedPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.noClampLength)
        
        let result = rhsKeyBytes.withUnsafeBytes { (rhsKeyBytesPtr: UnsafeRawBufferPointer) -> Int32 in
            return lhsKeyBytes.withUnsafeBytes { (lhsKeyBytesPtr: UnsafeRawBufferPointer) -> Int32 in
                guard let lhsKeyBytesBaseAddress: UnsafePointer<UInt8> = lhsKeyBytesPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1   // Impossible case (refer to comments at top of extension)
                }
                guard let rhsKeyBytesBaseAddress: UnsafePointer<UInt8> = rhsKeyBytesPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1   // Impossible case (refer to comments at top of extension)
                }
                
                return Sodium.lib_crypto_scalarmult_ed25519_noclamp(combinedPtr, lhsKeyBytesBaseAddress, rhsKeyBytesBaseAddress)
            }
        }
        
        /// Ensure the above worked
        guard result == 0 else { return nil }
        
        return Data(bytes: combinedPtr, count: Sodium.noClampLength).bytes
    }
    
    /// Calculate a shared secret for a message from A to B:
    ///
    /// BLAKE2b(a kB || kA || kB)
    ///
    /// The receiver can calulate the same value via:
    ///
    /// BLAKE2b(b kA || kA || kB)
    public func sharedBlindedEncryptionKey(secretKey: Bytes, otherBlindedPublicKey: Bytes, fromBlindedPublicKey kA: Bytes, toBlindedPublicKey kB: Bytes, genericHash: GenericHashType) -> Bytes? {
        let aBytes: Bytes = generatePrivateKeyScalar(secretKey: secretKey)
        
        guard let combinedKeyBytes: Bytes = combineKeys(lhsKeyBytes: aBytes, rhsKeyBytes: otherBlindedPublicKey) else {
            return nil
        }
        
        return genericHash.hash(message: (combinedKeyBytes + kA + kB), outputLength: 32)
    }
    
    /// This method should be used to check if a users standard sessionId matches a blinded one
    public func sessionId(_ standardSessionId: String, matchesBlindedId blindedSessionId: String, serverPublicKey: String, genericHash: GenericHashType) -> Bool {
        // Only support generating blinded keys for standard session ids
        guard let sessionId: SessionId = SessionId(from: standardSessionId), sessionId.prefix == .standard else { return false }
        guard let blindedId: SessionId = SessionId(from: blindedSessionId), blindedId.prefix == .blinded else { return false }
        guard let kBytes: Bytes = generateBlindingFactor(serverPublicKey: serverPublicKey, genericHash: genericHash) else {
            return false
        }

        /// From the session id (ignoring 05 prefix) we have two possible ed25519 pubkeys; the first is the positive (which is what
        /// Signal's XEd25519 conversion always uses)
        ///
        /// Note: The below method is code we have exposed from the `curve25519_verify` method within the Curve25519 library
        /// rather than custom code we have written
        guard let xEd25519Key: Data = try? Ed25519.publicKey(from: Data(hex: sessionId.publicKey)) else { return false }
        
        /// Blind the positive public key
        guard let pk1: Bytes = combineKeys(lhsKeyBytes: kBytes, rhsKeyBytes: xEd25519Key.bytes) else { return false }
        
        /// For the negative, what we're going to get out of the above is simply the negative of pk1, so flip the sign bit to get pk2
        ///     pk2 = pk1[0:31] + bytes([pk1[31] ^ 0b1000_0000])
        let pk2: Bytes = (pk1[0..<31] + [(pk1[31] ^ 0b1000_0000)])
        
        return (
            SessionId(.blinded, publicKey: pk1).publicKey == blindedId.publicKey ||
            SessionId(.blinded, publicKey: pk2).publicKey == blindedId.publicKey
        )
    }
}

extension GenericHash {
    public func hashSaltPersonal(
        message: Bytes,
        outputLength: Int,
        key: Bytes? = nil,
        salt: Bytes,
        personal: Bytes
    ) -> Bytes? {
        var output: [UInt8] = [UInt8](repeating: 0, count: outputLength)
        
        let result = crypto_generichash_blake2b_salt_personal(
            &output,
            outputLength,
            message,
            UInt64(message.count),
            key,
            (key?.count ?? 0),
            salt,
            personal
        )
        
        guard result == 0 else { return nil }
        
        return output
    }
}

extension AeadXChaCha20Poly1305IetfType {
    /// This method is the same as the standard AeadXChaCha20Poly1305IetfType `encrypt` method except it allows the
    /// specification of a nonce which allows for deterministic behaviour with unit testing
    public func encrypt(message: Bytes, secretKey: Bytes, nonce: Bytes, additionalData: Bytes? = nil) -> Bytes? {
        guard secretKey.count == KeyBytes else { return nil }

        var authenticatedCipherText = Bytes(repeating: 0, count: message.count + ABytes)
        var authenticatedCipherTextLen: UInt64 = 0

        let result = crypto_aead_xchacha20poly1305_ietf_encrypt(
            &authenticatedCipherText, &authenticatedCipherTextLen,
            message, UInt64(message.count),
            additionalData, UInt64(additionalData?.count ?? 0),
            nil, nonce, secretKey
        )
        
        guard result == 0 else { return nil }

        return authenticatedCipherText
    }
}

extension Box.KeyPair: Equatable {
    public static func == (lhs: Box.KeyPair, rhs: Box.KeyPair) -> Bool {
        return (
            lhs.publicKey == rhs.publicKey &&
            lhs.secretKey == rhs.secretKey
        )
    }
}
