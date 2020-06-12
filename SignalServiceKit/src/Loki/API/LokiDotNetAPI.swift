import PromiseKit
import SessionMetadataKit

/// Base class for `LokiFileServerAPI` and `LokiPublicChatAPI`.
public class LokiDotNetAPI : NSObject {

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }
    internal static var userKeyPair: ECKeyPair { OWSIdentityManager.shared().identityKeyPair()! }

    // MARK: Settings
    private static let attachmentType = "network.loki"
    
    // MARK: Error
    @objc public class LokiDotNetAPIError : NSError { // Not called `Error` for Obj-C interoperablity
        
        @objc public static let generic = LokiDotNetAPIError(domain: "LokiDotNetAPIErrorDomain", code: 1, userInfo: [ NSLocalizedDescriptionKey : "An error occurred." ])
        @objc public static let parsingFailed = LokiDotNetAPIError(domain: "LokiDotNetAPIErrorDomain", code: 2, userInfo: [ NSLocalizedDescriptionKey : "Invalid file server response." ])
        @objc public static let signingFailed = LokiDotNetAPIError(domain: "LokiDotNetAPIErrorDomain", code: 3, userInfo: [ NSLocalizedDescriptionKey : "Couldn't sign message." ])
        @objc public static let encryptionFailed = LokiDotNetAPIError(domain: "LokiDotNetAPIErrorDomain", code: 4, userInfo: [ NSLocalizedDescriptionKey : "Couldn't encrypt file." ])
        @objc public static let decryptionFailed = LokiDotNetAPIError(domain: "LokiDotNetAPIErrorDomain", code: 5, userInfo: [ NSLocalizedDescriptionKey : "Couldn't decrypt file." ])
        @objc public static let maxFileSizeExceeded = LokiDotNetAPIError(domain: "LokiDotNetAPIErrorDomain", code: 6, userInfo: [ NSLocalizedDescriptionKey : "Maximum file size exceeded." ])
    }

    // MARK: Database
    /// To be overridden by subclasses.
    internal class var authTokenCollection: String { preconditionFailure("authTokenCollection is abstract and must be overridden.") }

    private static func getAuthTokenFromDatabase(for server: String) -> String? {
        var result: String? = nil
        storage.dbReadConnection.read { transaction in
            result = transaction.object(forKey: server, inCollection: authTokenCollection) as! String?
        }
        return result
    }
    
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

    private static func setAuthToken(for server: String, to newValue: String, in transaction: YapDatabaseReadWriteTransaction) {
        transaction.setObject(newValue, forKey: server, inCollection: authTokenCollection)
    }

    public static func clearAuthToken(for server: String) {
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
        return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global(qos: .default)).map2 { rawResponse in
            guard let json = rawResponse as? JSON, let base64EncodedChallenge = json["cipherText64"] as? String, let base64EncodedServerPublicKey = json["serverPubKey64"] as? String,
                let challenge = Data(base64Encoded: base64EncodedChallenge), var serverPublicKey = Data(base64Encoded: base64EncodedServerPublicKey) else {
                throw LokiDotNetAPIError.parsingFailed
            }
            // Discard the "05" prefix if needed
            if serverPublicKey.count == 33 {
                let hexEncodedServerPublicKey = serverPublicKey.toHexString()
                serverPublicKey = Data.data(fromHex: hexEncodedServerPublicKey.substring(from: 2))!
            }
            // The challenge is prefixed by the 16 bit IV
            guard let tokenAsData = try? DiffieHellman.decrypt(challenge, publicKey: serverPublicKey, privateKey: userKeyPair.privateKey),
                let token = String(bytes: tokenAsData, encoding: .utf8) else {
                throw LokiDotNetAPIError.decryptionFailed
            }
            return token
        }
    }

    private static func submitAuthToken(_ token: String, for server: String) -> Promise<String> {
        print("[Loki] Submitting auth token for server: \(server).")
        let url = URL(string: "\(server)/loki/v1/submit_challenge")!
        let parameters = [ "pubKey" : getUserHexEncodedPublicKey(), "token" : token ]
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        return LokiFileServerProxy(for: server).perform(request, withCompletionQueue: DispatchQueue.global(qos: .default)).map2 { _ in token }
    }

    // MARK: Public API
    @objc(uploadAttachment:withID:toServer:)
    public static func objc_uploadAttachment(_ attachment: TSAttachmentStream, with attachmentID: String, to server: String) -> AnyPromise {
        return AnyPromise.from(uploadAttachment(attachment, with: attachmentID, to: server))
    }

    public static func uploadAttachment(_ attachment: TSAttachmentStream, with attachmentID: String, to server: String) -> Promise<Void> {
        let isEncryptionRequired = (server == LokiFileServerAPI.server)
        return Promise<Void>() { seal in
            func proceed(with token: String) {
                // Get the attachment
                let data: Data
                guard let unencryptedAttachmentData = try? attachment.readDataFromFile() else {
                    print("[Loki] Couldn't read attachment from disk.")
                    return seal.reject(LokiDotNetAPIError.generic)
                }
                // Encrypt the attachment if needed
                if isEncryptionRequired {
                    var encryptionKey = NSData()
                    var digest = NSData()
                    guard let encryptedAttachmentData = Cryptography.encryptAttachmentData(unencryptedAttachmentData, outKey: &encryptionKey, outDigest: &digest) else {
                        print("[Loki] Couldn't encrypt attachment.")
                        return seal.reject(LokiDotNetAPIError.encryptionFailed)
                    }
                    attachment.encryptionKey = encryptionKey as Data
                    attachment.digest = digest as Data
                    data = encryptedAttachmentData
                } else {
                    data = unencryptedAttachmentData
                }
                // Check the file size if needed
                let isLokiFileServer = (server == LokiFileServerAPI.server)
                if isLokiFileServer && data.count > LokiFileServerAPI.maxFileSize {
                    return seal.reject(LokiDotNetAPIError.maxFileSizeExceeded)
                }
                // Create the request
                let url = "\(server)/files"
                let parameters: JSON = [ "type" : attachmentType, "Content-Type" : "application/binary" ]
                var error: NSError?
                var request = AFHTTPRequestSerializer().multipartFormRequest(withMethod: "POST", urlString: url, parameters: parameters, constructingBodyWith: { formData in
                    formData.appendPart(withFileData: data, name: "content", fileName: UUID().uuidString, mimeType: "application/binary")
                }, error: &error)
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let error = error {
                    print("[Loki] Couldn't upload attachment due to error: \(error).")
                    return seal.reject(error)
                }
                // Send the request
                func parseResponse(_ responseObject: Any) {
                    // Parse the server ID & download URL
                    guard let json = responseObject as? JSON, let data = json["data"] as? JSON, let serverID = data["id"] as? UInt64, let downloadURL = data["url"] as? String else {
                        print("[Loki] Couldn't parse attachment from: \(responseObject).")
                        return seal.reject(LokiDotNetAPIError.parsingFailed)
                    }
                    // Update the attachment
                    attachment.serverId = serverID
                    attachment.isUploaded = true
                    attachment.downloadURL = downloadURL
                    attachment.save()
                    seal.fulfill(())
                }
                let isProxyingRequired = (server == LokiFileServerAPI.server) // Don't proxy open group requests for now
                if isProxyingRequired {
                    attachment.isUploaded = false
                    attachment.save()
                    let _ = LokiFileServerProxy(for: server).performLokiFileServerNSURLRequest(request as NSURLRequest).done2 { responseObject in
                        parseResponse(responseObject)
                    }.catch2 { error in
                        seal.reject(error)
                    }
                } else {
                    let task = AFURLSessionManager(sessionConfiguration: .default).uploadTask(withStreamedRequest: request as URLRequest, progress: { rawProgress in
                        // Broadcast progress updates
                        let progress = max(0.1, rawProgress.fractionCompleted)
                        let userInfo: [String:Any] = [ kAttachmentUploadProgressKey : progress, kAttachmentUploadAttachmentIDKey : attachmentID ]
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .attachmentUploadProgress, object: nil, userInfo: userInfo)
                        }
                    }, completionHandler: { response, responseObject, error in
                        if let error = error {
                            print("[Loki] Couldn't upload attachment due to error: \(error).")
                            return seal.reject(error)
                        }
                        let statusCode = (response as! HTTPURLResponse).statusCode
                        let isSuccessful = (200...299) ~= statusCode
                        guard isSuccessful else {
                            print("[Loki] Couldn't upload attachment.")
                            return seal.reject(LokiDotNetAPIError.generic)
                        }
                        parseResponse(responseObject)
                    })
                    task.resume()
                }
            }
            if server == LokiFileServerAPI.server {
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

// MARK: Error Handling
internal extension Promise {

    internal func handlingInvalidAuthTokenIfNeeded(for server: String) -> Promise<T> {
        return recover2 { error -> Promise<T> in
            if let error = error as? NetworkManagerError, (error.statusCode == 401 || error.statusCode == 403) {
                print("[Loki] Group chat auth token for: \(server) expired; dropping it.")
                LokiDotNetAPI.clearAuthToken(for: server)
            }
            throw error
        }
    }
}
