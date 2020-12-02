import CryptoSwift
import PromiseKit
import SessionUtilitiesKit

public protocol SharedSenderKeysDelegate {

    func requestSenderKey(for groupPublicKey: String, senderPublicKey: String, using transaction: Any)
}

public enum SharedSenderKeys {
    private static let gcmTagSize: UInt = 16
    private static let ivSize: UInt = 12

    // MARK: Ratcheting Error
    public enum RatchetingError : LocalizedError {
        case loadingFailed(groupPublicKey: String, senderPublicKey: String)
        case messageKeyMissing(targetKeyIndex: UInt, groupPublicKey: String, senderPublicKey: String)
        case generic

        public var errorDescription: String? {
            switch self {
            case .loadingFailed(let groupPublicKey, let senderPublicKey): return "Couldn't get ratchet for closed group with public key: \(groupPublicKey), sender public key: \(senderPublicKey)."
            case .messageKeyMissing(let targetKeyIndex, let groupPublicKey, let senderPublicKey): return "Couldn't find message key for old key index: \(targetKeyIndex), public key: \(groupPublicKey), sender public key: \(senderPublicKey)."
            case .generic: return "An error occurred"
            }
        }
    }

    // MARK: Private/Internal API
    public static func generateRatchet(for groupPublicKey: String, senderPublicKey: String, using transaction: Any) -> ClosedGroupRatchet {
        let rootChainKey = Data.getSecureRandomData(ofSize: 32)!.toHexString()
        let ratchet = ClosedGroupRatchet(chainKey: rootChainKey, keyIndex: 0, messageKeys: [])
        SNProtocolKitConfiguration.shared.storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: ratchet, in: .current, using: transaction)
        return ratchet
    }

    private static func step(_ ratchet: ClosedGroupRatchet) throws -> ClosedGroupRatchet {
        let nextMessageKey = try HMAC(key: Data(hex: ratchet.chainKey).bytes, variant: .sha256).authenticate([ UInt8(1) ])
        let nextChainKey = try HMAC(key: Data(hex: ratchet.chainKey).bytes, variant: .sha256).authenticate([ UInt8(2) ])
        let nextKeyIndex = ratchet.keyIndex + 1
        let messageKeys = ratchet.messageKeys + [ nextMessageKey.toHexString() ]
        return ClosedGroupRatchet(chainKey: nextChainKey.toHexString(), keyIndex: nextKeyIndex, messageKeys: messageKeys)
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func stepRatchetOnce(for groupPublicKey: String, senderPublicKey: String, using transaction: Any) throws -> ClosedGroupRatchet {
        #if DEBUG
        assert(!Thread.isMainThread)
        #endif
        guard let ratchet = SNProtocolKitConfiguration.shared.storage.getClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, from: .current) else {
            let error = RatchetingError.loadingFailed(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey)
            SNLog("\(error.errorDescription!)")
            throw error
        }
        do {
            let result = try step(ratchet)
            SNProtocolKitConfiguration.shared.storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: result, in: .current, using: transaction)
            return result
        } catch {
            SNLog("Couldn't step ratchet due to error: \(error).")
            throw error
        }
    }

    /// - Note: Sync. Don't call from the main thread.
    private static func stepRatchet(for groupPublicKey: String, senderPublicKey: String, until targetKeyIndex: UInt, using transaction: Any, isRetry: Bool = false) throws -> ClosedGroupRatchet {
        #if DEBUG
        assert(!Thread.isMainThread)
        #endif
        let collection: ClosedGroupRatchetCollectionType = (isRetry) ? .old : .current
        guard let ratchet = SNProtocolKitConfiguration.shared.storage.getClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, from: collection) else {
            let error = RatchetingError.loadingFailed(groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey)
            SNLog("\(error.errorDescription!)")
            throw error
        }
        if targetKeyIndex < ratchet.keyIndex {
            // There's no need to advance the ratchet if this is invoked for an old key index
            guard ratchet.messageKeys.count > targetKeyIndex else {
                let error = RatchetingError.messageKeyMissing(targetKeyIndex: targetKeyIndex, groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey)
                SNLog("\(error.errorDescription!)")
                throw error
            }
            return ratchet
        } else {
            var currentKeyIndex = ratchet.keyIndex
            var result = ratchet
            while currentKeyIndex < targetKeyIndex {
                do {
                    result = try step(result)
                    currentKeyIndex = result.keyIndex
                } catch {
                    SNLog("Couldn't step ratchet due to error: \(error).")
                    throw error
                }
            }
            let collection: ClosedGroupRatchetCollectionType = (isRetry) ? .old : .current
            SNProtocolKitConfiguration.shared.storage.setClosedGroupRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, ratchet: result, in: collection, using: transaction)
            return result
        }
    }

    // MARK: Public API
    public static func encrypt(_ plaintext: Data, for groupPublicKey: String, senderPublicKey: String, using transaction: Any) throws -> (ivAndCiphertext: Data, keyIndex: UInt) {
        let ratchet: ClosedGroupRatchet
        do {
            ratchet = try stepRatchetOnce(for: groupPublicKey, senderPublicKey: senderPublicKey, using: transaction)
        } catch {
            if case RatchetingError.loadingFailed(_, _) = error {
                SNProtocolKitConfiguration.shared.sharedSenderKeysDelegate.requestSenderKey(for: groupPublicKey, senderPublicKey: senderPublicKey, using: transaction)
            }
            throw error
        }
        let iv = Data.getSecureRandomData(ofSize: ivSize)!
        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
        let messageKey = ratchet.messageKeys.last!
        let aes = try AES(key: Data(hex: messageKey).bytes, blockMode: gcm, padding: .noPadding)
        let ciphertext = try aes.encrypt(plaintext.bytes)
        return (ivAndCiphertext: iv + Data(ciphertext), ratchet.keyIndex)
    }

    public static func decrypt(_ ivAndCiphertext: Data, for groupPublicKey: String, senderPublicKey: String, keyIndex: UInt, using transaction: Any, isRetry: Bool = false) throws -> Data {
        let ratchet: ClosedGroupRatchet
        do {
            ratchet = try stepRatchet(for: groupPublicKey, senderPublicKey: senderPublicKey, until: keyIndex, using: transaction, isRetry: isRetry)
        } catch {
            if !isRetry {
                return try decrypt(ivAndCiphertext, for: groupPublicKey, senderPublicKey: senderPublicKey, keyIndex: keyIndex, using: transaction, isRetry: true)
            } else {
                if case RatchetingError.loadingFailed(_, _) = error {
                    SNProtocolKitConfiguration.shared.sharedSenderKeysDelegate.requestSenderKey(for: groupPublicKey, senderPublicKey: senderPublicKey, using: transaction)
                }
                throw error
            }
        }
        let iv = ivAndCiphertext[0..<Int(ivSize)]
        let ciphertext = ivAndCiphertext[Int(ivSize)...]
        let gcm = GCM(iv: iv.bytes, tagLength: Int(gcmTagSize), mode: .combined)
        let messageKeys = ratchet.messageKeys
        let lastNMessageKeys: [String]
        if messageKeys.count > 16 { // Pick an arbitrary number of message keys to try; this helps resolve issues caused by messages arriving out of order
            lastNMessageKeys = [String](messageKeys[messageKeys.index(messageKeys.endIndex, offsetBy: -16)..<messageKeys.endIndex])
        } else {
            lastNMessageKeys = messageKeys
        }
        guard !lastNMessageKeys.isEmpty else {
            throw RatchetingError.messageKeyMissing(targetKeyIndex: keyIndex, groupPublicKey: groupPublicKey, senderPublicKey: senderPublicKey)
        }
        var error: Error?
        for messageKey in lastNMessageKeys.reversed() { // Reversed because most likely the last one is the one we need
            let aes = try AES(key: Data(hex: messageKey).bytes, blockMode: gcm, padding: .noPadding)
            do {
                return Data(try aes.decrypt(ciphertext.bytes))
            } catch (let e) {
                error = e
            }
        }
        if !isRetry {
            return try decrypt(ivAndCiphertext, for: groupPublicKey, senderPublicKey: senderPublicKey, keyIndex: keyIndex, using: transaction, isRetry: true)
        } else {
            SNProtocolKitConfiguration.shared.sharedSenderKeysDelegate.requestSenderKey(for: groupPublicKey, senderPublicKey: senderPublicKey, using: transaction)
            throw error ?? RatchetingError.generic
        }
    }
}
