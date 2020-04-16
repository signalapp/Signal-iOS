//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

private protocol TSConstantsProtocol: class {
    var textSecureWebSocketAPI: String { get }
    var textSecureServerURL: String { get }
    var textSecureCDNServerURL: String { get }
    var contactDiscoveryURL: String { get }
    var keyBackupURL: String { get }
    var storageServiceURL: String { get }
    var kUDTrustRoot: String { get }

    var censorshipReflectorHost: String { get }

    var serviceCensorshipPrefix: String { get }
    var cdnCensorshipPrefix: String { get }
    var contactDiscoveryCensorshipPrefix: String { get }
    var keyBackupCensorshipPrefix: String { get }
    var storageServiceCensorshipPrefix: String { get }

    var contactDiscoveryEnclaveName: String { get }
    var contactDiscoveryMrEnclave: String { get }

    var keyBackupEnclaveName: String { get }
    var keyBackupMrEnclave: String { get }
    var keyBackupServiceId: String { get }

    var applicationGroup: String { get }

    var serverPublicParamsBase64: String { get }
}

// MARK: -

@objc
public class TSConstants: NSObject {

    @objc
    public static let EnvironmentDidChange = Notification.Name("EnvironmentDidChange")

    // Never instantiate this class.
    private override init() {}

    @objc
    public static var textSecureWebSocketAPI: String { return shared.textSecureWebSocketAPI }
    @objc
    public static var textSecureServerURL: String { return shared.textSecureServerURL }
    @objc
    public static var textSecureCDNServerURL: String { return shared.textSecureCDNServerURL }
    @objc
    public static var contactDiscoveryURL: String { return shared.contactDiscoveryURL }
    @objc
    public static var keyBackupURL: String { return shared.keyBackupURL }
    @objc
    public static var storageServiceURL: String { return shared.storageServiceURL }
    @objc
    public static var kUDTrustRoot: String { return shared.kUDTrustRoot }

    @objc
    public static var censorshipReflectorHost: String { return shared.censorshipReflectorHost }

    @objc
    public static var serviceCensorshipPrefix: String { return shared.serviceCensorshipPrefix }
    @objc
    public static var cdnCensorshipPrefix: String { return shared.cdnCensorshipPrefix }
    @objc
    public static var contactDiscoveryCensorshipPrefix: String { return shared.contactDiscoveryCensorshipPrefix }
    @objc
    public static var keyBackupCensorshipPrefix: String { return shared.keyBackupCensorshipPrefix }
    @objc
    public static var storageServiceCensorshipPrefix: String { return shared.storageServiceCensorshipPrefix }

    @objc
    public static var contactDiscoveryEnclaveName: String { return shared.contactDiscoveryEnclaveName }
    @objc
    public static var contactDiscoveryMrEnclave: String { return shared.contactDiscoveryMrEnclave }

    @objc
    public static var keyBackupEnclaveName: String { return shared.keyBackupEnclaveName }
    @objc
    public static var keyBackupMrEnclave: String { return shared.keyBackupMrEnclave }
    @objc
    public static var keyBackupServiceId: String { return shared.keyBackupServiceId }

    @objc
    public static var applicationGroup: String { return shared.applicationGroup }

    @objc
    public static var serverPublicParamsBase64: String { return shared.serverPublicParamsBase64 }

    @objc
    public static var isUsingProductionService: Bool {
        return environment == .production
    }

    private enum Environment {
        case production, staging
    }

    private static let serialQueue = DispatchQueue(label: "TSConstants")
    private static var _forceEnvironment: Environment?
    private static var forceEnvironment: Environment? {
        get {
            return serialQueue.sync {
                return _forceEnvironment
            }
        }
        set {
            serialQueue.sync {
                _forceEnvironment = newValue
            }
        }
    }

    private static var environment: Environment {
        if let environment = forceEnvironment {
            return environment
        }
        return FeatureFlags.isUsingProductionService ? .production : .staging
    }

    @objc
    public class func forceStaging() {
        forceEnvironment = .staging
    }

    @objc
    public class func forceProduction() {
        forceEnvironment = .production
    }

    private static var shared: TSConstantsProtocol {
        switch environment {
        case .production:
            return TSConstantsProduction()
        case .staging:
            return TSConstantsStaging()
        }
    }
}

// MARK: -

private class TSConstantsProduction: TSConstantsProtocol {

    public let textSecureWebSocketAPI = "wss://textsecure-service.whispersystems.org/v1/websocket/"
    public let textSecureServerURL = "https://textsecure-service.whispersystems.org/"
    public let textSecureCDNServerURL = "https://cdn.signal.org"
    public let contactDiscoveryURL = "https://api.directory.signal.org"
    public let keyBackupURL = "https://api.backup.signal.org"
    public let storageServiceURL = "https://storage.signal.org"
    public let kUDTrustRoot = "BXu6QIKVz5MA8gstzfOgRQGqyLqOwNKHL6INkv3IHWMF"

    public let censorshipReflectorHost = "europe-west1-signal-cdn-reflector.cloudfunctions.net"

    public let serviceCensorshipPrefix = "service"
    public let cdnCensorshipPrefix = "cdn"
    public let contactDiscoveryCensorshipPrefix = "directory"
    public let keyBackupCensorshipPrefix = "backup"
    public let storageServiceCensorshipPrefix = "storage"

    public let contactDiscoveryEnclaveName = "cd6cfc342937b23b1bdd3bbf9721aa5615ac9ff50a75c5527d441cd3276826c9"
    public var contactDiscoveryMrEnclave: String {
        return contactDiscoveryEnclaveName
    }

    public let keyBackupEnclaveName = "fe7c1bfae98f9b073d220366ea31163ee82f6d04bead774f71ca8e5c40847bfe"
    public let keyBackupMrEnclave = "a3baab19ef6ce6f34ab9ebb25ba722725ae44a8872dc0ff08ad6d83a9489de87"
    public var keyBackupServiceId: String {
        return keyBackupEnclaveName
    }

    public let applicationGroup = "group.org.whispersystems.signal.group"

    // We need to discard all profile key credentials if these values ever change.
    // See: GroupsV2Impl.verifyServerPublicParams(...)
    public let serverPublicParamsBase64 = "DDZM414H2QbA3brAa6NCMaZIN1ZRY+B46PWDvw4LmwrY6CEQArF4OF/yHdBL7HW/JPgjjauzJau+cpikvqH3dDZQ7KFKgx/MGsbw49ATUj6fhBXko9iyPwVwC3+kjNY6PGZuSoYpD4SJJIgzTJ8Gnuk23tSbX1aQWAWNlc8WiyWIHm/A+22w/D1zQmGuFCEGImU4blMK+HhNfC7jM5leBQ=="
}

// MARK: -

private class TSConstantsStaging: TSConstantsProtocol {

    public let textSecureWebSocketAPI = "wss://textsecure-service-staging.whispersystems.org/v1/websocket/"
    public let textSecureServerURL = "https://textsecure-service-staging.whispersystems.org/"
    public let textSecureCDNServerURL = "https://cdn-staging.signal.org"
    public let contactDiscoveryURL = "https://api-staging.directory.signal.org"
    public let keyBackupURL = "https://api-staging.backup.signal.org"
    public let storageServiceURL = "https://storage-staging.signal.org"
    public let kUDTrustRoot = "BbqY1DzohE4NUZoVF+L18oUPrK3kILllLEJh2UnPSsEx"

    public let censorshipReflectorHost = "europe-west1-signal-cdn-reflector.cloudfunctions.net"

    public let serviceCensorshipPrefix = "service-staging"
    public let cdnCensorshipPrefix = "cdn-staging"
    public let contactDiscoveryCensorshipPrefix = "directory-staging"
    public let keyBackupCensorshipPrefix = "backup-staging"
    public let storageServiceCensorshipPrefix = "storage-staging"

    // CDS uses the same EnclaveName and MrEnclave
    public let contactDiscoveryEnclaveName = "bad2158b530c977e3ea43f64fb85f1cf7a646832d9b34b329920f02cab7f5b34"
    public var contactDiscoveryMrEnclave: String {
        return contactDiscoveryEnclaveName
    }

    public let keyBackupEnclaveName = "823a3b2c037ff0cbe305cc48928cfcc97c9ed4a8ca6d49af6f7d6981fb60a4e9"
    public let keyBackupMrEnclave = "a3baab19ef6ce6f34ab9ebb25ba722725ae44a8872dc0ff08ad6d83a9489de87"
    public var keyBackupServiceId: String {
        return keyBackupEnclaveName
    }

    public let applicationGroup = "group.org.whispersystems.signal.group.staging"

    // We need to discard all profile key credentials if these values ever change.
    // See: GroupsV2Impl.verifyServerPublicParams(...)
    public let serverPublicParamsBase64 = "ZFt6K+dFE23BsKZMqTroFbbxOXDhDHXcIeCFlWeOIjXeNPrpm9pGwwcQ1AiENlEM1xOaQ2EW48s++quhVv1TEkKormac7WM6Z01kWn/FH2zVcXJxQmsKfYWmAa6lnLhIHO8MXCfllR9uDW2Jfj++8SEzn6oD3+wmzqOzPqiOPAtQxuqWsVTFk4bt7ChuiVWjF7PVZ37deUH/mKhV0flvFA=="
}
