import AFNetworking
import CryptoSwift
import PromiseKit
import SessionProtocolKit
import SessionSnodeKit
import SessionUtilitiesKit
import SignalCoreKit

/// Base class for `FileServerAPI` and `OpenGroupAPI`.
public class DotNetAPI : NSObject {

    // MARK: Settings
    private static let attachmentType = "network.loki"
    private static let maxRetryCount: UInt = 4
    
    // MARK: Error
    public enum Error : LocalizedError {
        case generic
        case parsingFailed
        case signingFailed
        case encryptionFailed
        case decryptionFailed
        case maxFileSizeExceeded

        public var errorDescription: String? {
            switch self {
            case .generic: return "An error occurred."
            case .parsingFailed: return "Invalid file server response."
            case .signingFailed: return "Couldn't sign message."
            case .encryptionFailed: return "Couldn't encrypt file."
            case .decryptionFailed: return "Couldn't decrypt file."
            case .maxFileSizeExceeded: return "Maximum file size exceeded."
            }
        }
    }

    // MARK: Lifecycle
    override private init() { }

    // MARK: Private API
    private static func requestNewAuthToken(for server: String) -> Promise<String> {
        SNLog("Requesting auth token for server: \(server).")
        guard let userKeyPair = Configuration.shared.storage.getUserKeyPair() else { return Promise(error: Error.generic) }
        let queryParameters = "pubKey=\(userKeyPair.publicKey.toHexString())"
        let url = URL(string: "\(server)/loki/v1/get_challenge?\(queryParameters)")!
        let request = TSRequest(url: url)
        let serverPublicKeyPromise = (server == FileServerAPI.server) ? Promise.value(FileServerAPI.publicKey)
            : OpenGroupAPI.getOpenGroupServerPublicKey(for: server)
        return serverPublicKeyPromise.then(on: DispatchQueue.global(qos: .userInitiated)) { serverPublicKey in
            OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey)
        }.map(on: DispatchQueue.global(qos: .userInitiated)) { json in
            guard let base64EncodedChallenge = json["cipherText64"] as? String, let base64EncodedServerPublicKey = json["serverPubKey64"] as? String,
                let challenge = Data(base64Encoded: base64EncodedChallenge), var serverPublicKey = Data(base64Encoded: base64EncodedServerPublicKey) else {
                throw Error.parsingFailed
            }
            // Discard the "05" prefix if needed
            if serverPublicKey.count == 33 {
                let hexEncodedServerPublicKey = serverPublicKey.toHexString()
                let startIndex = hexEncodedServerPublicKey.index(hexEncodedServerPublicKey.startIndex, offsetBy: 2)
                serverPublicKey = Data(hex: String(hexEncodedServerPublicKey[startIndex..<hexEncodedServerPublicKey.endIndex]))
            }
            // The challenge is prefixed by the 16 bit IV
            guard let tokenAsData = try? DiffieHellman.decrypt(challenge, publicKey: serverPublicKey, privateKey: userKeyPair.privateKey),
                let token = String(bytes: tokenAsData, encoding: .utf8) else {
                throw Error.decryptionFailed
            }
            return token
        }
    }

    private static func submitAuthToken(_ token: String, for server: String) -> Promise<String> {
        SNLog("Submitting auth token for server: \(server).")
        let url = URL(string: "\(server)/loki/v1/submit_challenge")!
        guard let userPublicKey = Configuration.shared.storage.getUserPublicKey() else { return Promise(error: Error.generic) }
        let parameters = [ "pubKey" : userPublicKey, "token" : token ]
        let request = TSRequest(url: url, method: "POST", parameters: parameters)
        let serverPublicKeyPromise = (server == FileServerAPI.server) ? Promise.value(FileServerAPI.publicKey)
            : OpenGroupAPI.getOpenGroupServerPublicKey(for: server)
        return serverPublicKeyPromise.then(on: DispatchQueue.global(qos: .userInitiated)) { serverPublicKey in
            OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey)
        }.map(on: DispatchQueue.global(qos: .userInitiated)) { _ in token }
    }

    // MARK: Public API
    public static func getAuthToken(for server: String) -> Promise<String> {
        let storage = Configuration.shared.storage
        if let token = storage.getAuthToken(for: server) {
            return Promise.value(token)
        } else {
            return requestNewAuthToken(for: server).then(on: DispatchQueue.global(qos: .userInitiated)) { submitAuthToken($0, for: server) }.map(on: DispatchQueue.global(qos: .userInitiated)) { token in
                storage.with { transaction in
                    storage.setAuthToken(for: server, to: token, using: transaction)
                }
                return token
            }
        }
    }

    @objc(downloadAttachmentFrom:)
    public static func objc_downloadAttachment(from url: String) -> AnyPromise {
        return AnyPromise.from(downloadAttachment(from: url))
    }

    public static func downloadAttachment(from url: String) -> Promise<Data> {
        var host = "https://\(URL(string: url)!.host!)"
        let sanitizedURL: String
        if FileServerAPI.fileStorageBucketURL.contains(host) {
            sanitizedURL = url.replacingOccurrences(of: FileServerAPI.fileStorageBucketURL, with: "\(FileServerAPI.server)/loki/v1")
            host = FileServerAPI.server
        } else {
            sanitizedURL = url.replacingOccurrences(of: host, with: "\(host)/loki/v1")
        }
        let request: NSMutableURLRequest
        do {
            request = try AFHTTPRequestSerializer().request(withMethod: "GET", urlString: sanitizedURL, parameters: nil)
        } catch {
            SNLog("Couldn't download attachment due to error: \(error).")
            return Promise(error: error)
        }
        let serverPublicKeyPromise = FileServerAPI.server.contains(host) ? Promise.value(FileServerAPI.publicKey)
            : OpenGroupAPI.getOpenGroupServerPublicKey(for: host)
        return attempt(maxRetryCount: maxRetryCount, recoveringOn: DispatchQueue.global(qos: .userInitiated)) {
            serverPublicKeyPromise.then(on: DispatchQueue.global(qos: .userInitiated)) { serverPublicKey in
                return OnionRequestAPI.sendOnionRequest(request, to: host, using: serverPublicKey, isJSONRequired: false).map(on: DispatchQueue.global(qos: .userInitiated)) { json in
                    guard let body = json["result"] as? String, let data = Data(base64Encoded: body) else {
                        SNLog("Couldn't parse attachment from: \(json).")
                        throw Error.parsingFailed
                    }
                    return data
                }
            }
        }
    }

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
                    SNLog("Couldn't read attachment from disk.")
                    return seal.reject(Error.generic)
                }
                // Encrypt the attachment if needed
                if isEncryptionRequired {
                    var encryptionKey = NSData()
                    var digest = NSData()
                    guard let encryptedAttachmentData = Cryptography.encryptAttachmentData(unencryptedAttachmentData, shouldPad: true, outKey: &encryptionKey, outDigest: &digest) else {
                        SNLog("Couldn't encrypt attachment.")
                        return seal.reject(Error.encryptionFailed)
                    }
                    attachment.encryptionKey = encryptionKey as Data
                    attachment.digest = digest as Data
                    data = encryptedAttachmentData
                } else {
                    data = unencryptedAttachmentData
                }
                // Check the file size if needed
                SNLog("File size: \(data.count) bytes.")
                if Double(data.count) > Double(FileServerAPI.maxFileSize) / FileServerAPI.fileSizeORMultiplier {
                    return seal.reject(Error.maxFileSizeExceeded)
                }
                // Create the request
                let url = "\(server)/files"
                let parameters: JSON = [ "type" : attachmentType, "Content-Type" : "application/binary" ]
                var error: NSError?
                let request = AFHTTPRequestSerializer().multipartFormRequest(withMethod: "POST", urlString: url, parameters: parameters, constructingBodyWith: { formData in
                    let uuid = UUID().uuidString
                    SNLog("File UUID: \(uuid).")
                    formData.appendPart(withFileData: data, name: "content", fileName: uuid, mimeType: "application/binary")
                }, error: &error)
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let error = error {
                    SNLog("Couldn't upload attachment due to error: \(error).")
                    return seal.reject(error)
                }
                // Send the request
                let serverPublicKeyPromise = (server == FileServerAPI.server) ? Promise.value(FileServerAPI.publicKey)
                    : OpenGroupAPI.getOpenGroupServerPublicKey(for: server)
                attachment.isUploaded = false
                attachment.save()
                let _ = serverPublicKeyPromise.then(on: DispatchQueue.global(qos: .userInitiated)) { serverPublicKey in
                    OnionRequestAPI.sendOnionRequest(request, to: server, using: serverPublicKey)
                }.done(on: DispatchQueue.global(qos: .userInitiated)) { json in
                    // Parse the server ID & download URL
                    guard let data = json["data"] as? JSON, let serverID = data["id"] as? UInt64, let downloadURL = data["url"] as? String else {
                        SNLog("Couldn't parse attachment from: \(json).")
                        return seal.reject(Error.parsingFailed)
                    }
                    // Update the attachment
                    attachment.serverId = serverID
                    attachment.isUploaded = true
                    attachment.downloadURL = downloadURL
                    attachment.save()
                    seal.fulfill(())
                }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
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
                }.catch(on: DispatchQueue.global(qos: .userInitiated)) { error in
                    SNLog("Couldn't upload attachment due to error: \(error).")
                    seal.reject(error)
                }
            }
        }
    }
}
