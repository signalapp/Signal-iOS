import PromiseKit

public extension FileServerAPI {

    /// Gets the device links associated with the given hex encoded public key from the
    /// server and stores and returns the valid ones.
    ///
    /// - Note: Deprecated.
    public static func getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> Promise<Set<DeviceLink>> {
        return getDeviceLinks(associatedWith: [ hexEncodedPublicKey ])
    }

    /// Gets the device links associated with the given hex encoded public keys from the
    /// server and stores and returns the valid ones.
    ///
    /// - Note: Deprecated.
    public static func getDeviceLinks(associatedWith hexEncodedPublicKeys: Set<String>) -> Promise<Set<DeviceLink>> {
        return Promise.value([])
        /*
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
         */
    }

    /// - Note: Deprecated.
    public static func setDeviceLinks(_ deviceLinks: Set<DeviceLink>) -> Promise<Void> {
        return Promise.value(())
        /*
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
         */
    }

    /// Adds the given device link to the user's device mapping on the server.
    ///
    /// - Note: Deprecated.
    public static func addDeviceLink(_ deviceLink: DeviceLink) -> Promise<Void> {
        return Promise.value(())
        /*
        var deviceLinks: Set<DeviceLink> = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: getUserHexEncodedPublicKey(), in: transaction)
        }
        deviceLinks.insert(deviceLink)
        return setDeviceLinks(deviceLinks).map2 { _ in
            storage.addDeviceLink(deviceLink)
        }
         */
    }

    /// Removes the given device link from the user's device mapping on the server.
    ///
    /// - Note: Deprecated.
    public static func removeDeviceLink(_ deviceLink: DeviceLink) -> Promise<Void> {
        return Promise.value(())
        /*
        var deviceLinks: Set<DeviceLink> = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: getUserHexEncodedPublicKey(), in: transaction)
        }
        deviceLinks.remove(deviceLink)
        return setDeviceLinks(deviceLinks).map2 { _ in
            storage.removeDeviceLink(deviceLink)
        }
         */
    }
}

@objc public extension FileServerAPI {

    /// - Note: Deprecated.
    @objc(getDeviceLinksAssociatedWithHexEncodedPublicKey:)
    public static func objc_getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> AnyPromise {
        return AnyPromise.from(getDeviceLinks(associatedWith: hexEncodedPublicKey))
    }

    /// - Note: Deprecated.
    @objc(getDeviceLinksAssociatedWithHexEncodedPublicKeys:)
    public static func objc_getDeviceLinks(associatedWith hexEncodedPublicKeys: Set<String>) -> AnyPromise {
        return AnyPromise.from(getDeviceLinks(associatedWith: hexEncodedPublicKeys))
    }
}
