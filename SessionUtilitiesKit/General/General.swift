// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import Curve25519Kit

public enum General {
    public enum Cache {
        public static var cachedEncodedPublicKey: Atomic<String?> = Atomic(nil)
    }
}

public enum GeneralError: Error {
    case keyGenerationFailed
}

@objc(SNGeneralUtilities)
public class GeneralUtilities: NSObject {
    @objc public static func getUserPublicKey() -> String {
        return getUserHexEncodedPublicKey()
    }
}

public func getUserHexEncodedPublicKey(_ db: Database? = nil) -> String {
    if let cachedKey: String = General.Cache.cachedEncodedPublicKey.wrappedValue { return cachedKey }
    
    // TODO: Refactor this to be a sessionId instead of custom creating it
    if let publicKey: Data = Identity.fetchUserPublicKey(db) { // Can be nil under some circumstances
        General.Cache.cachedEncodedPublicKey.mutate { $0 = "05\(publicKey.toHexString())" }
        return "05\(publicKey.toHexString())"
    }
    
    return ""
}

/// Does nothing, but is never inlined and thus evaluating its argument will never be optimized away.
///
/// Useful for forcing the instantiation of lazy properties like globals.
@inline(never)
public func touch<Value>(_ value: Value) { /* Do nothing */ }

/// Returns `f(x!)` if `x != nil`, or `nil` otherwise.
public func given<T, U>(_ x: T?, _ f: (T) throws -> U) rethrows -> U? { return try x.map(f) }

public func with<T, U>(_ x: T, _ f: (T) throws -> U) rethrows -> U { return try f(x) }
