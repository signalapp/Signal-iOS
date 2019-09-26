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

    // MARK: Database
    override internal class var authTokenCollection: String { return "LokiStorageAuthTokenCollection" }
    
    // MARK: Public API
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
                    let rawDeviceLinks = annotation["authorisations"] as? [JSON] else {
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

    // MARK: Public API (Obj-C)
    @objc(getDeviceLinksAssociatedWith:)
    public static func objc_getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> AnyPromise {
        return AnyPromise.from(getDeviceLinks(associatedWith: hexEncodedPublicKey))
    }

    // MARK: Private API
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
}
