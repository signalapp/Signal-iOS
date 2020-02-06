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

    private static let serialQueue = DispatchQueue(label: "SystemContactsFetcherQueue")
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

    // GroupsV2 TODO: This is for staging. We need the production values.
    //
    // We need to discard all profile key credentials if these values ever change.
    // See: VersionedProfiles.clearProfileKeyCredentials(...)
    public let serverPublicParamsBase64 = "Mmngo/SFRpC5kRLUKE8sXnpUx0QhQGcxUGI3b5eQXUX0kgK6SSL7XWcmjQv2ZsL5qKqyADTfhBakDSSfVEr2dHheAw/6JYMjgXnYZAn1845KOk9gHwWGaISIZWR55u4xpHdqZhZBdUyQ2MuDpIurLWifw8Jq/W6pumywOTg6zAeegHWx9MwyGaQD4R35nAAcPgqWuKrlIBX/z7kCYDwEFCaZwW+KmB0HluyEN362MzuzgGv+zK1SZR2aIpBmtsFYeG7FAV7aXXwB0aqB+5kDBJYCdhrzxWAqnWHC0Gm0JFASX3yaxmIWElacrfYtqLAP9KZcfViLRa4IiBIx3w9OAQ=="
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
    public let contactDiscoveryEnclaveName = "e0f7dee77dc9d705ccc1376859811da12ecec3b6119a19dc39bdfbf97173aa18"
    public var contactDiscoveryMrEnclave: String {
        return contactDiscoveryEnclaveName
    }

    public let keyBackupEnclaveName = "a1e9c1d3f352b5c4f0fc7a421b98119e60e5ff703c28fbea85c66bfa7306deab"
    public let keyBackupMrEnclave = "a3baab19ef6ce6f34ab9ebb25ba722725ae44a8872dc0ff08ad6d83a9489de87"
    public var keyBackupServiceId: String {
        return keyBackupEnclaveName
    }

    public let applicationGroup = "group.org.whispersystems.signal.group.staging"

    // We need to discard all profile key credentials if these values ever change.
    // See: VersionedProfiles.clearProfileKeyCredentials(...)
    public let serverPublicParamsBase64 = "Mmngo/SFRpC5kRLUKE8sXnpUx0QhQGcxUGI3b5eQXUX0kgK6SSL7XWcmjQv2ZsL5qKqyADTfhBakDSSfVEr2dHheAw/6JYMjgXnYZAn1845KOk9gHwWGaISIZWR55u4xpHdqZhZBdUyQ2MuDpIurLWifw8Jq/W6pumywOTg6zAeegHWx9MwyGaQD4R35nAAcPgqWuKrlIBX/z7kCYDwEFCaZwW+KmB0HluyEN362MzuzgGv+zK1SZR2aIpBmtsFYeG7FAV7aXXwB0aqB+5kDBJYCdhrzxWAqnWHC0Gm0JFASX3yaxmIWElacrfYtqLAP9KZcfViLRa4IiBIx3w9OAQ=="
}
