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
    public typealias SharedSecret = Data
    
    private static let scalarLength: Int = Int(crypto_core_ed25519_scalarbytes())   // 32
    private static let noClampLength: Int = Int(crypto_scalarmult_ed25519_bytes())  // 32
    private static let scalarMultLength: Int = Int(crypto_scalarmult_bytes())       // 32
    private static let publicKeyLength: Int = Int(crypto_scalarmult_bytes())        // 32
    private static let secretKeyLength: Int = Int(crypto_sign_secretkeybytes())     // 64
    
    public func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair? {
        guard edKeyPair.publicKey.count == Sodium.publicKeyLength && edKeyPair.secretKey.count == Sodium.secretKeyLength else {
            return nil
        }
        
        /// 64-byte blake2b hash then reduce to get the blinding factor:
        ///     k = salt.crypto_core_ed25519_scalar_reduce(blake2b(server_pk, digest_size=64).digest())
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
        
        /// Calculate k*a.  To get 'a' (the Ed25519 private key scalar) we call the sodium function to
        /// convert to an *x* secret key, which seems wrong--but isn't because converted keys use the
        /// same secret scalar secret.  (And so this is just the most convenient way to get 'a' out of
        /// a sodium Ed25519 secret key).
        ///     a = s.to_curve25519_private_key().encode()
        let secretKeyBytes: Bytes = [UInt8](edKeyPair.secretKey)
        let aPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarMultLength)
        
        let aResult = secretKeyBytes.withUnsafeBytes { (secretKeyPtr: UnsafeRawBufferPointer) -> Int32 in
            guard let secretKeyBaseAddress: UnsafePointer<UInt8> = secretKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            
            return crypto_sign_ed25519_sk_to_curve25519(aPtr, secretKeyBaseAddress)
        }
        
        /// Ensure the above worked
        guard aResult == 0 else { return nil }
        
        /// Generate the blinded key pair `ka`, `kA`
        let kaPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.secretKeyLength)
        let kAPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.publicKeyLength)
        crypto_core_ed25519_scalar_mul(kaPtr, kPtr, aPtr)
        guard crypto_scalarmult_ed25519_base_noclamp(kAPtr, kaPtr) == 0 else { return nil }
        
        return Box.KeyPair(
            publicKey: Data(bytes: kAPtr, count: Sodium.publicKeyLength).bytes,
            secretKey: Data(bytes: kaPtr, count: Sodium.secretKeyLength).bytes
        )
    }
    
    /// Constructs an Ed25519 signature from a root Ed25519 key and a blinded scalar/pubkey pair, with one tweak to the
    /// construction: we add kA into the hashed value that yields r so that we have domain separation for different blinded
    /// pubkeys (This doesn't affect verification at all).
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
    
    public func sharedEdSecret(_ firstKeyBytes: [UInt8], _ secondKeyBytes: [UInt8]) -> SharedSecret? {
        let sharedSecretPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.noClampLength)
        let result = secondKeyBytes.withUnsafeBytes { (secondKeyPtr: UnsafeRawBufferPointer) -> Int32 in
            return firstKeyBytes.withUnsafeBytes { (firstKeyPtr: UnsafeRawBufferPointer) -> Int32 in
                guard let firstKeyBaseAddress: UnsafePointer<UInt8> = firstKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                guard let secondKeyBaseAddress: UnsafePointer<UInt8> = secondKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                
                return crypto_scalarmult_ed25519_noclamp(sharedSecretPtr, firstKeyBaseAddress, secondKeyBaseAddress)
            }
        }
        
        guard result == 0 else { return nil }
        
        return Data(bytes: sharedSecretPtr, count: Sodium.scalarMultLength)
    }
    
    public func sharedSecret(_ firstKeyBytes: [UInt8], _ secondKeyBytes: [UInt8]) -> SharedSecret? {
        guard firstKeyBytes.count == Sodium.publicKeyLength && secondKeyBytes.count == Sodium.publicKeyLength else {
            return nil
        }
        
        let sharedSecretPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.scalarMultLength)
        let result = secondKeyBytes.withUnsafeBytes { (secondKeyPtr: UnsafeRawBufferPointer) -> Int32 in
            return firstKeyBytes.withUnsafeBytes { (firstKeyPtr: UnsafeRawBufferPointer) -> Int32 in
                guard let firstKeyBaseAddress: UnsafePointer<UInt8> = firstKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                guard let secondKeyBaseAddress: UnsafePointer<UInt8> = secondKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                
                //crypto_sign_ed25519_publickeybytes
                //crypto_scalarmult_curve25519(<#T##q: UnsafeMutablePointer<UInt8>##UnsafeMutablePointer<UInt8>#>, <#T##n: UnsafePointer<UInt8>##UnsafePointer<UInt8>#>, <#T##p: UnsafePointer<UInt8>##UnsafePointer<UInt8>#>)
                return crypto_scalarmult(sharedSecretPtr, firstKeyBaseAddress, secondKeyBaseAddress)
            }
        }
        
        guard result == 0 else { return nil }
        
        return Data(bytes: sharedSecretPtr, count: Sodium.scalarMultLength)
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
