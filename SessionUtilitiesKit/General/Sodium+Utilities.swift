// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Clibsodium
import Sodium
import Curve25519Kit

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
