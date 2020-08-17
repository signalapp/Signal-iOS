import PromiseKit
import SessionMetadataKit

/// Base class for `FileServerAPI` and `PublicChatAPI`.
public class DotNetAPI : NSObject {

    internal static var userKeyPair: ECKeyPair { OWSIdentityManager.shared().identityKeyPair()! }

    // MARK: Settings
    private static let attachmentType = "network.loki"
    
    // MARK: Error
    @objc(LKDotNetAPIError)
    public class DotNetAPIError : NSError { // Not called `Error` for Obj-C interoperablity
        
        @objc public static let generic = DotNetAPIError(domain: "DotNetAPIErrorDomain", code: 1, userInfo: [ NSLocalizedDescriptionKey : "An error occurred." ])
        @objc public static let parsingFailed = DotNetAPIError(domain: "DotNetAPIErrorDomain", code: 2, userInfo: [ NSLocalizedDescriptionKey : "Invalid file server response." ])
        @objc public static let signingFailed = DotNetAPIError(domain: "DotNetAPIErrorDomain", code: 3, userInfo: [ NSLocalizedDescriptionKey : "Couldn't sign message." ])
        @objc public static let encryptionFailed = DotNetAPIError(domain: "DotNetAPIErrorDomain", code: 4, userInfo: [ NSLocalizedDescriptionKey : "Couldn't encrypt file." ])
        @objc public static let decryptionFailed = DotNetAPIError(domain: "DotNetAPIErrorDomain", code: 5, userInfo: [ NSLocalizedDescriptionKey : "Couldn't decrypt file." ])
        @objc public static let maxFileSizeExceeded = DotNetAPIError(domain: "DotNetAPIErrorDomain", code: 6, userInfo: [ NSLocalizedDescriptionKey : "Maximum file size exceeded." ])
    }

    // MARK: Storage
    /// To be overridden by subclasses.
    internal class var authTokenCollection: String { preconditionFailure("authTokenCollection is abstract and must be overridden.") }

    internal static func getAuthToken(for server: String) -> Promise<String> {
        if let token = getAuthTokenFromDatabase(for: server) {
            return Promise.value(token)
        } else {
            return requestNewAuthToken(for: server).then2 { submitAuthToken($0, for: server) }.map2 { token in
                try! Storage.writeSync { transaction in
                    setAuthToken(for: server, to: token, in: transaction)
                }
                return token
            }
        }
    }

    private static func getAuthTokenFromDatabase(for server: String) -> String? {
        var result: String? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: server, inCollection: authTokenCollection) as? String
        }
        return result
    }

    private static func setAuthToken(for server: String, to newValue: String, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(newValue, forKey: server, inCollection: authTokenCollection)
    }

    public static func removeAuthToken(for server: String) {
        try! Storage.writeSync { transaction in
            transaction.removeObject(forKey: server, inCollection: authTokenCollection)
        }
    }

    // MARK: Lifecycle
    override private init() { }

    // MARK: Private API
    private static func requestNewAuthToken(for server: String) -> Promise<String> {
        print("[Loki] Requesting auth token for server: \(server).")
        let queryParameters = "pubKey=\(getUserHexEncodedPublicKey())"
        let url = URL(string: "\(server)/loki/v1/get_challenge?\(queryParameters)")!
        let request = TSRequest(url: url)
        let serverPublicKeyPromise = (server == FileServerAPI.server) ? Promise.value(FileServerAPI.fileServerPublicKey)
            : PublicChatAPI.getOpenGroupServerPublicKey(for: server)
        return serverPublicKeyPromise.then2 { serverPublicKey in
            OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey)
        }.map2 { json in
            guard let base64EncodedChallenge = json["cipherText64"] as? String, let base64EncodedServerPublicKey = json["serverPubKey64"] as? String,
                let challenge = Data(base64Encoded: base64EncodedChallenge), var serverPublicKey = Data(base64Encoded: base64EncodedServerPublicKey) else {
                throw DotNetAPIError.parsingFailed
            }
            // Discard the "05" prefix if needed
            if serverPublicKey.count == 33 {
                let hexEncodedServerPublicKey = serverPublicKey.toHexString()
                serverPublicKey = Data.data(fromHex: hexEncodedServerPublicKey.substring(from: 2))!
            }
            // The challenge is prefixed by the 16 bit IV
            guard let tokenAsData = try? DiffieHellman.decrypt(challenge, publicKey: serverPublicKey, privateKey: userKeyPair.privateKey),
                let token = String(bytes: tokenAsData, encoding: .utf8) else {
                throw DotNetAPIError.decryptionFailed
            }
            return token
        }
    }

    private static func submitAuthToken(_ token: String, for server: String) -> Promise<String> {
        print("[Loki] Submitting auth token for server: \(server).")
        let url = URL(string: "\(server)/loki/v1/submit_challenge")!
        let parameters = [ "pubKey" : getUserHexEncodedPublicKey(), "token" : token ]
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        let serverPublicKeyPromise = (server == FileServerAPI.server) ? Promise.value(FileServerAPI.fileServerPublicKey)
            : PublicChatAPI.getOpenGroupServerPublicKey(for: server)
        return serverPublicKeyPromise.then2 { serverPublicKey in
            OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey)
        }.map2 { _ in token }
    }

    // MARK: Public API
    @objc(uploadAttachment:withID:toServer:)
    public static func objc_uploadAttachment(_ attachment: TSAttachmentStream, with attachmentID: String, to server: String) -> AnyPromise {
        return AnyPromise.from(uploadAttachment(attachment, with: attachmentID, to: server))
    }

    public static func uploadAttachment(_ attachment: TSAttachmentStream, with attachmentID: String, to server: String) -> Promise<Void> {
        let isEncryptionRequired = (server == FileServerAPI.server)
        return Promise<Void>() { seal in
            func proceed(with token: String) {
                // Get the attachment
                let data: Data
                guard let unencryptedAttachmentData = try? attachment.readDataFromFile() else {
                    print("[Loki] Couldn't read attachment from disk.")
                    return seal.reject(DotNetAPIError.generic)
                }
                // Encrypt the attachment if needed
                if isEncryptionRequired {
                    var encryptionKey = NSData()
                    var digest = NSData()
                    guard let encryptedAttachmentData = Cryptography.encryptAttachmentData(unencryptedAttachmentData, outKey: &encryptionKey, outDigest: &digest) else {
                        print("[Loki] Couldn't encrypt attachment.")
                        return seal.reject(DotNetAPIError.encryptionFailed)
                    }
                    attachment.encryptionKey = encryptionKey as Data
                    attachment.digest = digest as Data
                    data = encryptedAttachmentData
                } else {
                    data = unencryptedAttachmentData
                }
                // Check the file size if needed
                print("[Loki] File size: \(data.count) bytes.")
                if Double(data.count) > Double(FileServerAPI.maxFileSize) / FileServerAPI.fileSizeORMultiplier {
                    return seal.reject(DotNetAPIError.maxFileSizeExceeded)
                }
                // Create the request
                let url = "\(server)/files"
                let parameters: JSON = [ "type" : attachmentType, "Content-Type" : "application/binary" ]
                var error: NSError?
                var request = AFHTTPRequestSerializer().multipartFormRequest(withMethod: "POST", urlString: url, parameters: parameters, constructingBodyWith: { formData in
                    let uuid = UUID().uuidString
                    print("[Loki] File UUID: \(uuid).")
                    formData.appendPart(withFileData: data, name: "content", fileName: uuid, mimeType: "application/binary")
                }, error: &error)
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let error = error {
                    print("[Loki] Couldn't upload attachment due to error: \(error).")
                    return seal.reject(error)
                }
                // Send the request
                let serverPublicKeyPromise = (server == FileServerAPI.server) ? Promise.value(FileServerAPI.fileServerPublicKey)
                    : PublicChatAPI.getOpenGroupServerPublicKey(for: server)
                attachment.isUploaded = false
                attachment.save()
                let _ = serverPublicKeyPromise.then2 { serverPublicKey in
                    OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey)
                }.done2 { json in
                    // Parse the server ID & download URL
                    guard let data = json["data"] as? JSON, let serverID = data["id"] as? UInt64, let downloadURL = data["url"] as? String else {
                        print("[Loki] Couldn't parse attachment from: \(json).")
                        return seal.reject(DotNetAPIError.parsingFailed)
                    }
                    // Update the attachment
                    attachment.serverId = serverID
                    attachment.isUploaded = true
                    attachment.downloadURL = downloadURL
                    attachment.save()
                    seal.fulfill(())
                }.catch2 { error in
                    seal.reject(error)
                }
            }
            if server == FileServerAPI.server {
                DispatchQueue.global(qos: .userInitiated).async {
                    proceed(with: "loki") // Uploads to the Loki File Server shouldn't include any personally identifiable information so use a dummy auth token
                }
            } else {
                getAuthToken(for: server).done(on: DispatchQueue.global(qos: .userInitiated)) { token in
                    proceed(with: token)
                }.catch2 { error in
                    print("[Loki] Couldn't upload attachment due to error: \(error).")
                    seal.reject(error)
                }
            }
        }
    }
}
