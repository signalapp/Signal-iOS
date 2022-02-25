import Clibsodium
import Sodium

extension Sign {

    /**
     Converts an Ed25519 public key to an X25519 public key.
     - Parameter ed25519PublicKey: The Ed25519 public key to convert.
     - Returns: The X25519 public key if conversion is successful.
     */
    public func toX25519(ed25519PublicKey: PublicKey) -> PublicKey? {
        var x25519PublicKey = PublicKey(repeating: 0, count: 32)

        // FIXME: It'd be nice to check the exit code here, but all the properties of the object
        // returned by the call below are internal.
        let _ = crypto_sign_ed25519_pk_to_curve25519 (
            &x25519PublicKey,
            ed25519PublicKey
        )
        
        return x25519PublicKey
    }

    /**
     Converts an Ed25519 secret key to an X25519 secret key.
     - Parameter ed25519SecretKey: The Ed25519 secret key to convert.
     - Returns: The X25519 secret key if conversion is successful.
     */
    public func toX25519(ed25519SecretKey: SecretKey) -> SecretKey? {
        var x25519SecretKey = SecretKey(repeating: 0, count: 32)

        // FIXME: It'd be nice to check the exit code here, but all the properties of the object
        // returned by the call below are internal.
        let _ = crypto_sign_ed25519_sk_to_curve25519 (
            &x25519SecretKey,
            ed25519SecretKey
        )

        return x25519SecretKey
    }
}

extension Sodium {
    private static let scalarLength: Int = Int(crypto_core_ed25519_scalarbytes())   // 32
    private static let noClampLength: Int = Int(crypto_scalarmult_ed25519_bytes())  // 32
    private static let scalarMultLength: Int = Int(crypto_scalarmult_bytes())       // 32
    private static let publicKeyLength: Int = Int(crypto_scalarmult_bytes())        // 32
    private static let secretKeyLength: Int = Int(crypto_sign_secretkeybytes())     // 64
    
    /// 64-byte blake2b hash then reduce to get the blinding factor
    public func generateBlindingFactor(serverPublicKey: String) -> Bytes? {
        /// k = salt.crypto_core_ed25519_scalar_reduce(blake2b(server_pk, digest_size=64).digest())
        guard let serverPubKeyData: Data = serverPublicKey.dataFromHex() else { return nil }
        guard let serverPublicKeyHashBytes: Bytes = genericHash.hash(message: [UInt8](serverPubKeyData), outputLength: 64) else {
            return nil
        }
        
        /// Reduce the server public key into an ed25519 scalar (`k`)
        let kPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        
        let kResult = serverPublicKeyHashBytes.withUnsafeBytes { (serverPublicKeyHashPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let serverPublicKeyHashBaseAddress: UnsafePointer<UInt8> = serverPublicKeyHashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            
            crypto_core_ed25519_scalar_reduce(kPtr, serverPublicKeyHashBaseAddress)
            return 0
        }
        
        /// Ensure the above worked
        guard kResult == 0 else { return nil }
        
        return Data(bytes: kPtr, count: Sodium.scalarLength).bytes
    }
    
    /// Calculate k*a.  To get 'a' (the Ed25519 private key scalar) we call the sodium function to
    /// convert to an *x* secret key, which seems wrong--but isn't because converted keys use the
    /// same secret scalar secret (and so this is just the most convenient way to get 'a' out of
    /// a sodium Ed25519 secret key)
    private func generatePrivateKeyScalar(secretKey: Bytes) -> Bytes? {
        /// a = s.to_curve25519_private_key().encode()
        let aPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarMultLength)
        
        let aResult = secretKey.withUnsafeBytes { (secretKeyPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let secretKeyBaseAddress: UnsafePointer<UInt8> = secretKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            
            return crypto_sign_ed25519_sk_to_curve25519(aPtr, secretKeyBaseAddress)
        }
        
        /// Ensure the above worked
        guard aResult == 0 else { return nil }
        
        return Data(bytes: aPtr, count: Sodium.scalarMultLength).bytes
    }
    
    /// Constructs a "blinded" key pair (`ka, kA`) based on an open group server `publicKey` and an ed25519 `keyPair`
    public func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair? {
        guard edKeyPair.publicKey.count == Sodium.publicKeyLength && edKeyPair.secretKey.count == Sodium.secretKeyLength else {
            return nil
        }
        guard let kBytes: Bytes = generateBlindingFactor(serverPublicKey: serverPublicKey) else { return nil }
        guard let aBytes: Bytes = generatePrivateKeyScalar(secretKey: edKeyPair.secretKey) else { return nil }
        
        /// Generate the blinded key pair `ka`, `kA`
        let kaPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.secretKeyLength)
        let kAPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.publicKeyLength)
        
        let kaResult = aBytes.withUnsafeBytes { (aPtr: UnsafeRawBufferPointer) -> Int32 in
            return kBytes.withUnsafeBytes { (kPtr: UnsafeRawBufferPointer) -> Int32 in
                guard let kBaseAddress: UnsafePointer<UInt8> = kPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                guard let aBaseAddress: UnsafePointer<UInt8> = aPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                
                crypto_core_ed25519_scalar_mul(kaPtr, kBaseAddress, aBaseAddress)
                return 0
            }
        }
        
        /// Ensure the above worked
        guard kaResult == 0 else { return nil }
        
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
        
        let rResult = combinedHashBytes.withUnsafeBytes { (combinedHashPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let combinedHashBaseAddress: UnsafePointer<UInt8> = combinedHashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            
            crypto_core_ed25519_scalar_reduce(rPtr, combinedHashBaseAddress)
            return 0
        }
        
        /// Ensure the above worked
        guard rResult == 0 else { return nil }
        
        /// sig_R = salt.crypto_scalarmult_ed25519_base_noclamp(r)
        let sig_RPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.noClampLength)
        guard crypto_scalarmult_ed25519_base_noclamp(sig_RPtr, rPtr) == 0 else { return nil }
        
        /// HRAM = salt.crypto_core_ed25519_scalar_reduce(sha512_multipart(sig_R, kA, message_parts))
        let sig_RBytes: Bytes = Data(bytes: sig_RPtr, count: Sodium.noClampLength).bytes
        let HRAMHashBytes: Bytes = (sig_RBytes + kA + message).sha512()
        let HRAMPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        
        let HRAMResult = HRAMHashBytes.withUnsafeBytes { (HRAMHashPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let HRAMHashBaseAddress: UnsafePointer<UInt8> = HRAMHashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            
            crypto_core_ed25519_scalar_reduce(HRAMPtr, HRAMHashBaseAddress)
            return 0
        }
        
        /// Ensure the above worked
        guard HRAMResult == 0 else { return nil }
        
        /// sig_s = salt.crypto_core_ed25519_scalar_add(r, salt.crypto_core_ed25519_scalar_mul(HRAM, ka))
        let sig_sMulPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        let sig_sPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarLength)
        
        let sig_sResult = ka.withUnsafeBytes { (kaPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let kaBaseAddress: UnsafePointer<UInt8> = kaPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            
            crypto_core_ed25519_scalar_mul(sig_sMulPtr, HRAMPtr, kaBaseAddress)
            crypto_core_ed25519_scalar_add(sig_sPtr, rPtr, sig_sMulPtr)
            return 0
        }
        
        guard sig_sResult == 0 else { return nil }
        
        /// full_sig = sig_R + sig_s
        return (Data(bytes: sig_RPtr, count: Sodium.noClampLength).bytes + Data(bytes: sig_sPtr, count: Sodium.scalarLength).bytes)
    }
    
    /// Combines two keys (`kA`)
    public func combineKeys(lhsKeyBytes: Bytes, rhsKeyBytes: Bytes) -> Bytes? {
        let combinedPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.noClampLength)
        
        let result = rhsKeyBytes.withUnsafeBytes { (rhsKeyBytesPtr: UnsafeRawBufferPointer) -> Int32 in
            return lhsKeyBytes.withUnsafeBytes { (lhsKeyBytesPtr: UnsafeRawBufferPointer) -> Int32 in
                guard let lhsKeyBytesBaseAddress: UnsafePointer<UInt8> = lhsKeyBytesPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                guard let rhsKeyBytesBaseAddress: UnsafePointer<UInt8> = rhsKeyBytesPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                
                return crypto_scalarmult_ed25519_noclamp(combinedPtr, lhsKeyBytesBaseAddress, rhsKeyBytesBaseAddress)
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
        guard let aBytes: Bytes = generatePrivateKeyScalar(secretKey: secretKey) else { return nil }
        guard let combinedKeyBytes: Bytes = combineKeys(lhsKeyBytes: aBytes, rhsKeyBytes: otherBlindedPublicKey) else { return nil }
        
        return genericHash.hash(message: (combinedKeyBytes + kA + kB), outputLength: 32)
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
