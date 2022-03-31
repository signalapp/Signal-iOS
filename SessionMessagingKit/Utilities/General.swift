import Foundation

public enum General {
    public enum Cache {
        public static var cachedEncodedPublicKey: Atomic<String?> = Atomic(nil)
    }
}

@objc(SNGeneralUtilities)
public class GeneralUtilities: NSObject {
    @objc public static func getUserPublicKey() -> String {
        return getUserHexEncodedPublicKey()
    }
}

public func getUserHexEncodedPublicKey() -> String {
    if let cachedKey: String = General.Cache.cachedEncodedPublicKey.wrappedValue { return cachedKey }
    
    if let keyPair = OWSIdentityManager.shared().identityKeyPair() { // Can be nil under some circumstances
        General.Cache.cachedEncodedPublicKey.mutate { $0 = keyPair.hexEncodedPublicKey }
        return keyPair.hexEncodedPublicKey
    }
    
    return ""
}
