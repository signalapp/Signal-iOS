// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import Curve25519Kit

public struct SessionId {
    public enum Prefix: String, CaseIterable {
        case standard = "05"    // Used for identified users, open groups, etc.
        case blinded = "15"     // Used for authentication and participants in open groups with blinding enabled
        case unblinded = "00"   // Used for authentication in open groups with blinding disabled
        
        public init?(from stringValue: String?) {
            guard let stringValue: String = stringValue else { return nil }
            
            guard stringValue.count > 2 else {
                guard let targetPrefix: Prefix = Prefix(rawValue: stringValue) else { return nil }
                self = targetPrefix
                return
            }
            
            guard ECKeyPair.isValidHexEncodedPublicKey(candidate: stringValue) else { return nil }
            guard let targetPrefix: Prefix = Prefix(rawValue: String(stringValue.prefix(2))) else { return nil }
            
            self = targetPrefix
        }
    }
    
    public let prefix: Prefix
    public let publicKey: String
    
    public var hexString: String {
        return prefix.rawValue + publicKey
    }
    
    // MARK: - Initialization
    
    public init?(from idString: String?) {
        guard let idString: String = idString, idString.count > 2 else { return nil }
        guard let targetPrefix: Prefix = Prefix(from: idString) else { return nil }
        
        self.prefix = targetPrefix
        self.publicKey = idString.substring(from: 2)
    }
    
    public init(_ type: Prefix, publicKey: Bytes) {
        self.prefix = type
        self.publicKey = publicKey.map { String(format: "%02hhx", $0) }.joined()
    }
}
