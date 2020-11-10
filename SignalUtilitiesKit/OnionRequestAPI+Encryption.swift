import CryptoSwift
import PromiseKit

extension OnionRequestAPI {

    internal static func encode(ciphertext: Data, json: JSON) throws -> Data {
        // The encoding of V2 onion requests looks like: | 4 bytes: size N of ciphertext | N bytes: ciphertext | json as utf8 |
        guard JSONSerialization.isValidJSONObject(json) else { throw HTTP.Error.invalidJSON }
        let jsonAsData = try JSONSerialization.data(withJSONObject: json, options: [ .fragmentsAllowed ])
        let ciphertextSize = Int32(ciphertext.count).littleEndian
        let ciphertextSizeAsData = withUnsafePointer(to: ciphertextSize) { Data(bytes: $0, count: MemoryLayout<Int32>.size) }
        return ciphertextSizeAsData + ciphertext + jsonAsData
    }

    /// Encrypts `payload` for `destination` and returns the result. Use this to build the core of an onion request.
    internal static func encrypt(_ payload: JSON, for destination: Destination) -> Promise<EncryptionResult> {
        let (promise, seal) = Promise<EncryptionResult>.pending()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard JSONSerialization.isValidJSONObject(payload) else { return seal.reject(HTTP.Error.invalidJSON) }
                // Wrapping isn't needed for file server or open group onion requests
                switch destination {
                case .snode(let snode):
                    let snodeX25519PublicKey = snode.publicKeySet.x25519Key
                    let payloadAsData = try JSONSerialization.data(withJSONObject: payload, options: [ .fragmentsAllowed ])
                    let plaintext = try encode(ciphertext: payloadAsData, json: [ "headers" : "" ])
                    let result = try EncryptionUtilities.encrypt(plaintext, using: snodeX25519PublicKey)
                    seal.fulfill(result)
                case .server(_, let serverX25519PublicKey):
                    let plaintext = try JSONSerialization.data(withJSONObject: payload, options: [ .fragmentsAllowed ])
                    let result = try EncryptionUtilities.encrypt(plaintext, using: serverX25519PublicKey)
                    seal.fulfill(result)
                }
            } catch (let error) {
                seal.reject(error)
            }
        }
        return promise
    }

    /// Encrypts the previous encryption result (i.e. that of the hop after this one) for this hop. Use this to build the layers of an onion request.
    internal static func encryptHop(from lhs: Destination, to rhs: Destination, using previousEncryptionResult: EncryptionResult) -> Promise<EncryptionResult> {
        let (promise, seal) = Promise<EncryptionResult>.pending()
        DispatchQueue.global(qos: .userInitiated).async {
            var parameters: JSON
            switch rhs {
            case .snode(let snode):
                let snodeED25519PublicKey = snode.publicKeySet.ed25519Key
                parameters = [ "destination" : snodeED25519PublicKey ]
            case .server(let host, _):
                parameters = [ "host" : host, "target" : "/loki/v2/lsrpc", "method" : "POST" ]
            }
            parameters["ephemeral_key"] = previousEncryptionResult.ephemeralPublicKey.toHexString()
            let x25519PublicKey: String
            switch lhs {
            case .snode(let snode):
                let snodeX25519PublicKey = snode.publicKeySet.x25519Key
                x25519PublicKey = snodeX25519PublicKey
            case .server(_, let serverX25519PublicKey):
                x25519PublicKey = serverX25519PublicKey
            }
            do {
                let plaintext = try encode(ciphertext: previousEncryptionResult.ciphertext, json: parameters)
                let result = try EncryptionUtilities.encrypt(plaintext, using: x25519PublicKey)
                seal.fulfill(result)
            } catch (let error) {
                seal.reject(error)
            }
        }
        return promise
    }
}
