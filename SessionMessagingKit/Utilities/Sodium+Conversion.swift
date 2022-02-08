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
    public typealias SOGSDerivedKey = Data
    
    private static let publicKeyBytes: Int = Int(crypto_scalarmult_bytes())
    private static let sharedSecretBytes: Int = Int(crypto_scalarmult_bytes())
    
    public func derivedKey(serverPublicKeyBytes: [UInt8], userKeyBytes: [UInt8]) -> SOGSDerivedKey? {
        guard serverPublicKeyBytes.count == Sodium.publicKeyBytes && userKeyBytes.count == Sodium.publicKeyBytes else { return nil }
        
        let sharedSecretPtr: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: Sodium.sharedSecretBytes)
        let result = userKeyBytes.withUnsafeBytes { (userPublicKeyPtr: UnsafeRawBufferPointer) in
            return serverPublicKeyBytes.withUnsafeBytes { (serverPublicKeyPtr: UnsafeRawBufferPointer) -> Int32 in
                guard let serverKeyBaseAddress: UnsafePointer<UInt8> = serverPublicKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), let userKeyBaseAddress: UnsafePointer<UInt8> = userPublicKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
                }
                
                return crypto_scalarmult(sharedSecretPtr, serverKeyBaseAddress, userKeyBaseAddress)
            }
        }
        
        guard result == 0 else { return nil }
        
        return Data(bytes: sharedSecretPtr, count: Sodium.sharedSecretBytes)
    }
}
