import CryptoSwift
import PromiseKit

extension OnionRequestAPI {

    /// Encrypts `payload` for `destination` and returns the result. Use this to build the core of an onion request.
    internal static func encrypt(_ payload: JSON, for destination: Destination) -> Promise<EncryptionResult> {
        let (promise, seal) = Promise<EncryptionResult>.pending()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard JSONSerialization.isValidJSONObject(payload) else { return seal.reject(HTTP.Error.invalidJSON) }
                // Wrapping isn't needed for file server or open group onion requests
                switch destination {
                case .snode(let snode):
                    guard let snodeX25519PublicKey = snode.publicKeySet?.x25519Key else { return seal.reject(Error.snodePublicKeySetMissing) }
                    let payloadAsData = try JSONSerialization.data(withJSONObject: payload, options: [ .fragmentsAllowed ])
                    let payloadAsString = String(data: payloadAsData, encoding: .utf8)! // Snodes only accept this as a string
                    let wrapper: JSON = [ "body" : payloadAsString, "headers" : "" ]
                    guard JSONSerialization.isValidJSONObject(wrapper) else { return seal.reject(HTTP.Error.invalidJSON) }
                    let plaintext = try JSONSerialization.data(withJSONObject: wrapper, options: [ .fragmentsAllowed ])
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
                guard let snodeED25519PublicKey = snode.publicKeySet?.ed25519Key else { return seal.reject(Error.snodePublicKeySetMissing) }
                parameters = [ "destination" : snodeED25519PublicKey ]
            case .server(let host, _):
                parameters = [ "host" : host, "target" : "/loki/v1/lsrpc", "method" : "POST" ]
            }
            parameters["ciphertext"] = previousEncryptionResult.ciphertext.base64EncodedString()
            parameters["ephemeral_key"] = previousEncryptionResult.ephemeralPublicKey.toHexString()
            let x25519PublicKey: String
            switch lhs {
            case .snode(let snode):
                guard let snodeX25519PublicKey = snode.publicKeySet?.x25519Key else { return seal.reject(Error.snodePublicKeySetMissing) }
                x25519PublicKey = snodeX25519PublicKey
            case .server(_, let serverX25519PublicKey):
                x25519PublicKey = serverX25519PublicKey
            }
            do {
                guard JSONSerialization.isValidJSONObject(parameters) else { return seal.reject(HTTP.Error.invalidJSON) }
                let plaintext = try JSONSerialization.data(withJSONObject: parameters, options: [ .fragmentsAllowed ])
                let result = try EncryptionUtilities.encrypt(plaintext, using: x25519PublicKey)
                seal.fulfill(result)
            } catch (let error) {
                seal.reject(error)
            }
        }
        return promise
    }
}
