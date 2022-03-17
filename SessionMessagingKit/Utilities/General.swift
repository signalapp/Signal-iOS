import Foundation

public func getUserHexEncodedPublicKey(using dependencies: Dependencies = Dependencies()) -> String {
    if let keyPair = dependencies.identityManager.identityKeyPair() { // Can be nil under some circumstances
        return keyPair.hexEncodedPublicKey
    }
    
    return ""
}
