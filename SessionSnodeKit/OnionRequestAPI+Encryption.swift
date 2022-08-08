// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import CryptoSwift
import PromiseKit
import SessionUtilitiesKit

internal extension OnionRequestAPI {

    static func encode(ciphertext: Data, json: JSON) throws -> Data {
        // The encoding of V2 onion requests looks like: | 4 bytes: size N of ciphertext | N bytes: ciphertext | json as utf8 |
        guard JSONSerialization.isValidJSONObject(json) else { throw HTTP.Error.invalidJSON }
        let jsonAsData = try JSONSerialization.data(withJSONObject: json, options: [ .fragmentsAllowed ])
        let ciphertextSize = Int32(ciphertext.count).littleEndian
        let ciphertextSizeAsData = withUnsafePointer(to: ciphertextSize) { Data(bytes: $0, count: MemoryLayout<Int32>.size) }
        return ciphertextSizeAsData + ciphertext + jsonAsData
    }

    /// Encrypts `payload` for `destination` and returns the result. Use this to build the core of an onion request.
    static func encrypt(_ payload: Data, for destination: OnionRequestAPIDestination) -> Promise<AESGCM.EncryptionResult> {
        let (promise, seal) = Promise<AESGCM.EncryptionResult>.pending()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                switch destination {
                    case .snode(let snode):
                        // Need to wrap the payload for snode requests
                        let data: Data = try encode(ciphertext: payload, json: [ "headers" : "" ])
                        let result: AESGCM.EncryptionResult = try AESGCM.encrypt(data, for: snode.x25519PublicKey)
                        seal.fulfill(result)
                        
                    case .server(_, _, let serverX25519PublicKey, _, _):
                        let result: AESGCM.EncryptionResult = try AESGCM.encrypt(payload, for: serverX25519PublicKey)
                        seal.fulfill(result)
                }
            }
            catch (let error) {
                seal.reject(error)
            }
        }
        
        return promise
    }

    /// Encrypts the previous encryption result (i.e. that of the hop after this one) for this hop. Use this to build the layers of an onion request.
    static func encryptHop(from lhs: OnionRequestAPIDestination, to rhs: OnionRequestAPIDestination, using previousEncryptionResult: AESGCM.EncryptionResult) -> Promise<AESGCM.EncryptionResult> {
        let (promise, seal) = Promise<AESGCM.EncryptionResult>.pending()
        
        DispatchQueue.global(qos: .userInitiated).async {
            var parameters: JSON
            
            switch rhs {
                case .snode(let snode):
                    let snodeED25519PublicKey = snode.ed25519PublicKey
                    parameters = [ "destination" : snodeED25519PublicKey ]
                    
                case .server(let host, let target, _, let scheme, let port):
                    let scheme = scheme ?? "https"
                    let port = port ?? (scheme == "https" ? 443 : 80)
                    parameters = [ "host" : host, "target" : target, "method" : "POST", "protocol" : scheme, "port" : port ]
            }
            
            parameters["ephemeral_key"] = previousEncryptionResult.ephemeralPublicKey.toHexString()
            
            let x25519PublicKey: String
            
            switch lhs {
                case .snode(let snode):
                    let snodeX25519PublicKey = snode.x25519PublicKey
                    x25519PublicKey = snodeX25519PublicKey
                    
                case .server(_, _, let serverX25519PublicKey, _, _):
                    x25519PublicKey = serverX25519PublicKey
            }
            
            do {
                let plaintext = try encode(ciphertext: previousEncryptionResult.ciphertext, json: parameters)
                let result = try AESGCM.encrypt(plaintext, for: x25519PublicKey)
                seal.fulfill(result)
            }
            catch (let error) {
                seal.reject(error)
            }
        }
        
        return promise
    }
}
