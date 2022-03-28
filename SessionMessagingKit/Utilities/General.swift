import Foundation
import SessionUtilitiesKit

public protocol GeneralCacheType {
    var encodedPublicKey: String? { get set }
}

public enum General {
    public class Cache: GeneralCacheType {
        public var encodedPublicKey: String? = nil
    }
    
    public static var cache: Atomic<GeneralCacheType> = Atomic(Cache())
}

@objc(SNGeneralUtilities)
public class GeneralUtilities: NSObject {
    @objc public static func getUserPublicKey() -> String {
        return getUserHexEncodedPublicKey()
    }
}

public func getUserHexEncodedPublicKey(using dependencies: Dependencies = Dependencies()) -> String {
    if let cachedKey: String = dependencies.generalCache.wrappedValue.encodedPublicKey { return cachedKey }
    
    if let keyPair = dependencies.identityManager.identityKeyPair() { // Can be nil under some circumstances
        dependencies.generalCache.mutate { $0.encodedPublicKey = keyPair.hexEncodedPublicKey }
        return keyPair.hexEncodedPublicKey
    }
    
    return ""
}
