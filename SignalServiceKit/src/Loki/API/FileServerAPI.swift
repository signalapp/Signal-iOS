import PromiseKit

@objc(LKFileServerAPI)
public final class FileServerAPI : DotNetAPI {

    // MARK: Settings
    private static let attachmentType = "net.app.core.oembed"
    private static let deviceLinkType = "network.loki.messenger.devicemapping"
    
    internal static let fileServerPublicKey = "62509D59BDEEC404DD0D489C1E15BA8F94FD3D619B01C1BF48A9922BFCB7311C"

    public static let maxFileSize = 10_000_000 // 10 MB
    /// The file server has a file size limit of `maxFileSize`, which the Service Nodes try to enforce as well. However, the limit applied by the Service Nodes
    /// is on the **HTTP request** and not the file size. Because of onion request encryption, a file that's about 4 MB will result in a request that's about 18 MB.
    /// On average the multiplier appears to be about 4.4, so when checking whether the file will exceed the file size limit when uploading a file we just divide
    /// the size of the file by this number. The alternative would be to actually check the size of the HTTP request but that's only possible after proof of work
    /// has been calculated and the onion request encryption has happened, which takes several seconds.
    public static let fileSizeORMultiplier = 4.4

    @objc public static let server = "https://file.getsession.org"

    // MARK: Storage
    override internal class var authTokenCollection: String { return "LokiStorageAuthTokenCollection" }
    
    // MARK: Device Links
    /// - Note: Deprecated.
    @objc(getDeviceLinksAssociatedWithHexEncodedPublicKey:)
    public static func objc_getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> AnyPromise {
        return AnyPromise.from(getDeviceLinks(associatedWith: hexEncodedPublicKey))
    }

    /// Gets the device links associated with the given hex encoded public key from the
    /// server and stores and returns the valid ones.
    ///
    /// - Note: Deprecated.
    public static func getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> Promise<Set<DeviceLink>> {
        return getDeviceLinks(associatedWith: [ hexEncodedPublicKey ])
    }

    /// - Note: Deprecated.
    @objc(getDeviceLinksAssociatedWithHexEncodedPublicKeys:)
    public static func objc_getDeviceLinks(associatedWith hexEncodedPublicKeys: Set<String>) -> AnyPromise {
        return AnyPromise.from(getDeviceLinks(associatedWith: hexEncodedPublicKeys))
    }
    
    /// Gets the device links associated with the given hex encoded public keys from the
    /// server and stores and returns the valid ones.
    ///
    /// - Note: Deprecated.
    public static func getDeviceLinks(associatedWith hexEncodedPublicKeys: Set<String>) -> Promise<Set<DeviceLink>> {
        let hexEncodedPublicKeysDescription = "[ \(hexEncodedPublicKeys.joined(separator: ", ")) ]"
        print("[Loki] Getting device links for: \(hexEncodedPublicKeysDescription).")
        return getAuthToken(for: server).then2 { token -> Promise<Set<DeviceLink>> in
            let queryParameters = "ids=\(hexEncodedPublicKeys.map { "@\($0)" }.joined(separator: ","))&include_user_annotations=1"
            let url = URL(string: "\(server)/users?\(queryParameters)")!
            let request = TSRequest(url: url)
            return OnionRequestAPI.sendOnionRequest(request, to: server, using: fileServerPublicKey).map2 { rawResponse -> Set<DeviceLink> in
                guard let data = rawResponse["data"] as? [JSON] else {
                    print("[Loki] Couldn't parse device links for users: \(hexEncodedPublicKeys) from: \(rawResponse).")
                    throw DotNetAPIError.parsingFailed
                }
                return Set(data.flatMap { data -> [DeviceLink] in
                    guard let annotations = data["annotations"] as? [JSON], !annotations.isEmpty else { return [] }
                    guard let annotation = annotations.first(where: { $0["type"] as? String == deviceLinkType }),
                        let value = annotation["value"] as? JSON, let rawDeviceLinks = value["authorisations"] as? [JSON],
                        let hexEncodedPublicKey = data["username"] as? String else {
                        print("[Loki] Couldn't parse device links from: \(rawResponse).")
                        return []
                    }
                    return rawDeviceLinks.compactMap { rawDeviceLink in
                        guard let masterPublicKey = rawDeviceLink["primaryDevicePubKey"] as? String, let slavePublicKey = rawDeviceLink["secondaryDevicePubKey"] as? String,
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
                        let master = DeviceLink.Device(publicKey: masterPublicKey, signature: masterSignature)
                        let slave = DeviceLink.Device(publicKey: slavePublicKey, signature: slaveSignature)
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
                    }
                })
            }.map2 { deviceLinks in
                storage.setDeviceLinks(deviceLinks)
                return deviceLinks
            }
        }.handlingInvalidAuthTokenIfNeeded(for: server)
    }

    /// - Note: Deprecated.
    public static func setDeviceLinks(_ deviceLinks: Set<DeviceLink>) -> Promise<Void> {
        print("[Loki] Updating device links.")
        return getAuthToken(for: server).then2 { token -> Promise<Void> in
            let isMaster = deviceLinks.contains { $0.master.publicKey == getUserHexEncodedPublicKey() }
            let deviceLinksAsJSON = deviceLinks.map { $0.toJSON() }
            let value = !deviceLinksAsJSON.isEmpty ? [ "isPrimary" : isMaster ? 1 : 0, "authorisations" : deviceLinksAsJSON ] : nil
            let annotation: JSON = [ "type" : deviceLinkType, "value" : value ]
            let parameters: JSON = [ "annotations" : [ annotation ] ]
            let url = URL(string: "\(server)/users/me")!
            let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return attempt(maxRetryCount: 8, recoveringOn: SnodeAPI.workQueue) {
                OnionRequestAPI.sendOnionRequest(request, to: server, using: fileServerPublicKey).map2 { _ in }
            }.handlingInvalidAuthTokenIfNeeded(for: server).recover2 { error in
                print("[Loki] Couldn't update device links due to error: \(error).")
                throw error
            }
        }
    }
    
    /// Adds the given device link to the user's device mapping on the server.
    ///
    /// - Note: Deprecated.
    public static func addDeviceLink(_ deviceLink: DeviceLink) -> Promise<Void> {
        var deviceLinks: Set<DeviceLink> = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: getUserHexEncodedPublicKey(), in: transaction)
        }
        deviceLinks.insert(deviceLink)
        return setDeviceLinks(deviceLinks).map2 { _ in
            storage.addDeviceLink(deviceLink)
        }
    }

    /// Removes the given device link from the user's device mapping on the server.
    ///
    /// - Note: Deprecated.
    public static func removeDeviceLink(_ deviceLink: DeviceLink) -> Promise<Void> {
        var deviceLinks: Set<DeviceLink> = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: getUserHexEncodedPublicKey(), in: transaction)
        }
        deviceLinks.remove(deviceLink)
        return setDeviceLinks(deviceLinks).map2 { _ in
            storage.removeDeviceLink(deviceLink)
        }
    }
    
    // MARK: Profile Pictures
    @objc(uploadProfilePicture:)
    public static func objc_uploadProfilePicture(_ profilePicture: Data) -> AnyPromise {
        return AnyPromise.from(uploadProfilePicture(profilePicture))
    }

    public static func uploadProfilePicture(_ profilePicture: Data) -> Promise<String> {
        guard Double(profilePicture.count) < Double(maxFileSize) / fileSizeORMultiplier else { return Promise(error: DotNetAPIError.maxFileSizeExceeded) }
        let url = "\(server)/files"
        let parameters: JSON = [ "type" : attachmentType, "Content-Type" : "application/binary" ]
        var error: NSError?
        var request = AFHTTPRequestSerializer().multipartFormRequest(withMethod: "POST", urlString: url, parameters: parameters, constructingBodyWith: { formData in
            formData.appendPart(withFileData: profilePicture, name: "content", fileName: UUID().uuidString, mimeType: "application/binary")
        }, error: &error)
        // Uploads to the Loki File Server shouldn't include any personally identifiable information so use a dummy auth token
        request.addValue("Bearer loki", forHTTPHeaderField: "Authorization")
        if let error = error {
            print("[Loki] Couldn't upload profile picture due to error: \(error).")
            return Promise(error: error)
        }
        return OnionRequestAPI.sendOnionRequest(request, to: server, using: fileServerPublicKey).map2 { json in
            guard let data = json["data"] as? JSON, let downloadURL = data["url"] as? String else {
                print("[Loki] Couldn't parse profile picture from: \(json).")
                throw DotNetAPIError.parsingFailed
            }
            UserDefaults.standard[.lastProfilePictureUpload] = Date()
            return downloadURL
        }
    }
    
    // MARK: Open Group Server Public Key
    public static func getPublicKey(for openGroupServer: String) -> Promise<String> {
        let url = URL(string: "\(server)/loki/v1/getOpenGroupKey/\(URL(string: openGroupServer)!.host!)")!
        let request = TSRequest(url: url)
        let token = "loki" // Tokenless request; use a dummy token
        request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
        return OnionRequestAPI.sendOnionRequest(request, to: server, using: fileServerPublicKey).map2 { json in
            guard let bodyAsString = json["data"] as? String, let bodyAsData = bodyAsString.data(using: .utf8),
                let body = try JSONSerialization.jsonObject(with: bodyAsData, options: [ .fragmentsAllowed ]) as? JSON else { throw HTTP.Error.invalidJSON }
            guard let base64EncodedPublicKey = body["data"] as? String else {
                print("[Loki] Couldn't parse open group public key from: \(body).")
                throw DotNetAPIError.parsingFailed
            }
            let prefixedPublicKey = Data(base64Encoded: base64EncodedPublicKey)!
            let hexEncodedPrefixedPublicKey = prefixedPublicKey.toHexString()
            return hexEncodedPrefixedPublicKey.removing05PrefixIfNeeded()
        }
    }
}
