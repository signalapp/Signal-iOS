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
    
    private static let publicKeyBytes: Int = Int(crypto_scalarmult_bytes())
    private static let sharedSecretBytes: Int = Int(crypto_scalarmult_bytes())
    
    public func sharedSecret(_ firstKeyBytes: [UInt8], _ secondKeyBytes: [UInt8]) -> SharedSecret? {
        guard firstKeyBytes.count == Sodium.publicKeyBytes && secondKeyBytes.count == Sodium.publicKeyBytes else {
            return nil
        }
        
        let sharedSecretPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.sharedSecretBytes)
        let result = secondKeyBytes.withUnsafeBytes { (secondKeyPtr: UnsafeRawBufferPointer) -> Int32 in
            return firstKeyBytes.withUnsafeBytes { (firstKeyPtr: UnsafeRawBufferPointer) -> Int32 in
                guard let firstKeyBaseAddress: UnsafePointer<UInt8> = firstKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                guard let secondKeyBaseAddress: UnsafePointer<UInt8> = secondKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                
                return crypto_scalarmult(sharedSecretPtr, firstKeyBaseAddress, secondKeyBaseAddress)
            }
        }
        
        guard result == 0 else { return nil }
        
        return Data(bytes: sharedSecretPtr, count: Sodium.sharedSecretBytes)
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
