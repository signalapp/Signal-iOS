import Foundation

public enum General {
    public enum Cache {
        public static var cachedEncodedPublicKey: String? = nil
    }
}

@objc(SNGeneralUtilities)
public class GeneralUtilities: NSObject {
    @objc public static func getUserPublicKey() -> String {
        return getUserHexEncodedPublicKey()
    }
}

public func getUserHexEncodedPublicKey() -> String {
    if let cachedKey: String = General.Cache.cachedEncodedPublicKey { return cachedKey }
    
    if let keyPair = OWSIdentityManager.shared().identityKeyPair() { // Can be nil under some circumstances
        General.Cache.cachedEncodedPublicKey = keyPair.hexEncodedPublicKey
        return keyPair.hexEncodedPublicKey
    }
    
    return ""
}
