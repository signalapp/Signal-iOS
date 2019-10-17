import PromiseKit

@objc(LKStorageAPI)
public final class LokiStorageAPI : LokiDotNetAPI {

    // MARK: Settings
//    #if DEBUG
//    private static let server = "http://file-dev.lokinet.org"
//    #else
    private static let server = "https://file.lokinet.org"
//    #endif
    private static let deviceLinkType = "network.loki.messenger.devicemapping"
    private static let attachmentType = "network.loki"

    // MARK: Database
    override internal class var authTokenCollection: String { return "LokiStorageAuthTokenCollection" }
    
    // MARK: Device Links (Public API)
    /// Gets the device links associated with the given hex encoded public key from the
    /// server and stores and returns the valid ones.
    public static func getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> Promise<Set<DeviceLink>> {
        print("[Loki] Getting device links for: \(hexEncodedPublicKey).")
        return getAuthToken(for: server).then { token -> Promise<Set<DeviceLink>> in
            let queryParameters = "include_user_annotations=1"
            let url = URL(string: "\(server)/users/@\(hexEncodedPublicKey)?\(queryParameters)")!
            let request = TSRequest(url: url)
            return TSNetworkManager.shared().makePromise(request: request).map { $0.responseObject }.map { rawResponse -> Set<DeviceLink> in
                guard let json = rawResponse as? JSON, let data = json["data"] as? JSON,
                    let annotations = data["annotations"] as? [JSON] else {
                    print("[Loki] Couldn't parse device links for user: \(hexEncodedPublicKey) from: \(rawResponse).")
                    throw Error.parsingFailed
                }
                guard !annotations.isEmpty else { return [] }
                guard let annotation = annotations.first(where: { $0["type"] as? String == deviceLinkType }),
                    let value = annotation["value"] as? JSON, let rawDeviceLinks = value["authorisations"] as? [JSON] else {
                    print("[Loki] Couldn't parse device links for user: \(hexEncodedPublicKey) from: \(rawResponse).")
                    throw Error.parsingFailed
                }
                return Set(rawDeviceLinks.flatMap { rawDeviceLink in
                    guard let masterHexEncodedPublicKey = rawDeviceLink["primaryDevicePubKey"] as? String, let slaveHexEncodedPublicKey = rawDeviceLink["secondaryDevicePubKey"] as? String,
                        let base64EncodedSlaveSignature = rawDeviceLink["requestSignature"] as? String else {
                        print("[Loki] Couldn't parse device link for user: \(hexEncodedPublicKey) from: \(rawResponse).")
                        return nil
                    }
                    let masterSignature: Data?
                    if let base64EncodedMasterSignature = rawDeviceLink["grantSignature"] as? String {
                        masterSignature = Data(base64Encoded: base64EncodedMasterSignature)
                    } else {
                        masterSignature = nil
                    }
                    let slaveSignature = Data(base64Encoded: base64EncodedSlaveSignature)
                    let master = DeviceLink.Device(hexEncodedPublicKey: masterHexEncodedPublicKey, signature: masterSignature)
                    let slave = DeviceLink.Device(hexEncodedPublicKey: slaveHexEncodedPublicKey, signature: slaveSignature)
                    let deviceLink = DeviceLink(between: master, and: slave)
                    if let masterSignature = masterSignature {
                        guard DeviceLinkingUtilities.hasValidMasterSignature(deviceLink) else {
                            print("[Loki] Received a device link with an invalid master signature.")
                            return nil
                        }
                    }
                    guard DeviceLinkingUtilities.hasValidSlaveSignature(deviceLink) else {
                        print("[Loki] Received a device link with an invalid slave signature.")
                        return nil
                    }
                    return deviceLink
                })
            }.map { deviceLinks -> Set<DeviceLink> in
                storage.dbReadWriteConnection.readWrite { transaction in
                    storage.setDeviceLinks(deviceLinks, in: transaction)
                }
                return deviceLinks
            }
        }
    }
    
    public static func setDeviceLinks(_ deviceLinks: Set<DeviceLink>) -> Promise<Void> {
        print("[Loki] Updating device links.")
        return getAuthToken(for: server).then { token -> Promise<Void> in
            let isMaster = deviceLinks.contains { $0.master.hexEncodedPublicKey == userHexEncodedPublicKey }
            let deviceLinksAsJSON = deviceLinks.map { $0.toJSON() }
            let value = !deviceLinksAsJSON.isEmpty ? [ "isPrimary" : isMaster ? 1 : 0, "authorisations" : deviceLinksAsJSON ] : nil
            let annotation: JSON = [ "type" : deviceLinkType, "value" : value ]
            let parameters: JSON = [ "annotations" : [ annotation ] ]
            let url = URL(string: "\(server)/users/me")!
            let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return TSNetworkManager.shared().makePromise(request: request).map { _ in }.recover { error in
                print("Couldn't update device links due to error: \(error).")
                throw error
            }
        }
    }
    
    /// Adds the given device link to the user's device mapping on the server.
    public static func addDeviceLink(_ deviceLink: DeviceLink) -> Promise<Void> {
        var deviceLinks: Set<DeviceLink> = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: userHexEncodedPublicKey, in: transaction)
        }
        deviceLinks.insert(deviceLink)
        return setDeviceLinks(deviceLinks).map {
            storage.dbReadWriteConnection.readWrite { transaction in
                storage.addDeviceLink(deviceLink, in: transaction)
            }
        }
    }

    /// Removes the given device link from the user's device mapping on the server.
    public static func removeDeviceLink(_ deviceLink: DeviceLink) -> Promise<Void> {
        var deviceLinks: Set<DeviceLink> = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: userHexEncodedPublicKey, in: transaction)
        }
        deviceLinks.remove(deviceLink)
        return setDeviceLinks(deviceLinks).map {
            storage.dbReadWriteConnection.readWrite { transaction in
                storage.removeDeviceLink(deviceLink, in: transaction)
            }
        }
    }
    
    // MARK: Device Links (Public Obj-C API)
    @objc(getDeviceLinksAssociatedWith:)
    public static func objc_getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> AnyPromise {
        return AnyPromise.from(getDeviceLinks(associatedWith: hexEncodedPublicKey))
    }
    
    // MARK: Attachments (Public API)
    public static func uploadAttachment(_ attachment: TSAttachmentStream, attachmentID: String) -> Promise<Void> {
        return Promise<Void>() { seal in
            getAuthToken(for: server).done { token in
                // Encrypt the attachment
                guard let unencryptedAttachmentData = try? attachment.readDataFromFile() else {
                    print("[Loki] Couldn't read attachment data from disk.")
                    return seal.reject(Error.generic)
                }
                var encryptionKey = NSData()
                var digest = NSData()
                guard let encryptedAttachmentData = Cryptography.encryptAttachmentData(unencryptedAttachmentData, outKey: &encryptionKey, outDigest: &digest) else {
                    print("[Loki] Couldn't encrypt attachment.")
                    return seal.reject(Error.encryptionFailed)
                }
                attachment.encryptionKey = encryptionKey as Data
                attachment.digest = digest as Data
                // Create the request
                let url = "\(server)/files"
                let parameters: JSON = [ "type" : attachmentType, "Content-Type" : "application/binary" ]
                var error: NSError?
                var request = AFHTTPRequestSerializer().multipartFormRequest(withMethod: "POST", urlString: url, parameters: parameters, constructingBodyWith: { formData in
                    formData.appendPart(withFileData: encryptedAttachmentData, name: "content", fileName: UUID().uuidString, mimeType: "application/binary")
                }, error: &error)
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let error = error {
                    print("[Loki] Couldn't upload attachment due to error: \(error).")
                    throw error
                }
                // Send the request
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
                        return seal.reject(Error.generic)
                    }
                    // Parse the server ID & download URL
                    guard let json = responseObject as? JSON, let data = json["data"] as? JSON, let serverID = data["id"] as? UInt64, let downloadURL = data["url"] as? String else {
                        print("[Loki] Couldn't parse attachment from: \(responseObject).")
                        return seal.reject(Error.parsingFailed)
                    }
                    // Update the attachment
                    attachment.serverId = serverID
                    attachment.isUploaded = true
                    attachment.downloadURL = downloadURL
                    attachment.save()
                    return seal.fulfill(())
                })
                task.resume()
            }.catch { error in
                print("[Loki] Couldn't upload attachment.")
                seal.reject(error)
            }
        }
    }
    
    // MARK: Attachments (Public Obj-C API)
    @objc(uploadAttachment:withID:)
    public static func objc_uploadAttachment(_ attachment: TSAttachmentStream, attachmentID: String) -> AnyPromise {
        return AnyPromise.from(uploadAttachment(attachment, attachmentID: attachmentID))
    }
}
