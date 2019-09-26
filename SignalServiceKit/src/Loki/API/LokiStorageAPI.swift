import PromiseKit

@objc(LKStorageAPI)
public final class LokiStorageAPI : LokiDotNetAPI {

    // MARK: Settings
    private static let server = ""

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
        return setDeviceLinks(deviceLinks)
    }

    /// Removes the given device link from the user's device mapping on the server.
    public static func removeDeviceLink(_ deviceLink: DeviceLink) -> Promise<Void> {
        var deviceLinks: Set<DeviceLink> = []
        storage.dbReadConnection.read { transaction in
            deviceLinks = storage.getDeviceLinks(for: userHexEncodedPublicKey, in: transaction)
        }
        deviceLinks.remove(deviceLink)
        return setDeviceLinks(deviceLinks)
    }

    /// Gets the device links associated with the given hex encoded public key from the
    /// server and stores and returns the valid ones.
    public static func getDeviceLinks(associatedWith hexEncodedPublicKey: String) -> Promise<Set<DeviceLink>> {
        return Promise.value(Set<DeviceLink>()) // TODO: Implement
    }

    // MARK: Private API
    public static func setDeviceLinks(_ deviceLinks: Set<DeviceLink>) -> Promise<Void> {
        return getAuthToken(for: server).then { token -> Promise<Void> in
            let isMaster = deviceLinks.contains { $0.master.hexEncodedPublicKey == userHexEncodedPublicKey }
            let deviceLinksAsJSON = deviceLinks.map { $0.toJSON() }
            let value = !deviceLinksAsJSON.isEmpty ? [ "isPrimary" : isMaster ? 1 : 0, "authorisations" : deviceLinksAsJSON ] : nil
            let annotation: JSON = [ "type" : "network.loki.messenger.devicemapping", "value" : value ]
            let parameters: JSON = [ "annotations" : [ annotation ] ]
            let url = URL(string: "\(server)/users/me")!
            let request = TSRequest(url: url, method: "PATCH", parameters: parameters)
            request.allHTTPHeaderFields = [ "Content-Type" : "application/json", "Authorization" : "Bearer \(token)" ]
            return TSNetworkManager.shared().makePromise(request: request).map { _ in }
        }

    }
}
