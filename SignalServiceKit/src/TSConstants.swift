//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

// MARK: -

@objc
public class TSConstants: NSObject {

    private enum Environment {
        case production, staging
    }
    private static var environment: Environment = .production

    @objc
    public static var isUsingProductionService: Bool {
        return environment == .production
    }

    // Never instantiate this class.
    private override init() {}

    public static let legalTermsUrl = URL(string: "https://signal.org/legal/")!

    @objc
    public static var mainServiceWebSocketAPI_identified: String { shared.mainServiceWebSocketAPI_identified }
    @objc
    public static var mainServiceWebSocketAPI_unidentified: String { shared.mainServiceWebSocketAPI_unidentified }
    @objc
    public static var mainServiceURL: String { shared.mainServiceURL }
    @objc
    public static var textSecureCDN0ServerURL: String { shared.textSecureCDN0ServerURL }
    @objc
    public static var textSecureCDN2ServerURL: String { shared.textSecureCDN2ServerURL }
    @objc
    public static var contactDiscoverySGXURL: String { shared.contactDiscoverySGXURL }
    @objc
    public static var contactDiscoveryHSMURL: String { shared.contactDiscoveryHSMURL }
    @objc
    public static var keyBackupURL: String { shared.keyBackupURL }
    @objc
    public static var storageServiceURL: String { shared.storageServiceURL }
    @objc
    public static var sfuURL: String { shared.sfuURL }
    @objc
    public static var sfuTestURL: String { shared.sfuTestURL }
    @objc
    public static var kUDTrustRoot: String { shared.kUDTrustRoot }
    @objc
    public static var updatesURL: String { shared.updatesURL }
    @objc
    public static var updates2URL: String { shared.updates2URL }

    @objc
    public static var censorshipReflectorHost: String { shared.censorshipReflectorHost }

    @objc
    public static var serviceCensorshipPrefix: String { shared.serviceCensorshipPrefix }
    @objc
    public static var cdn0CensorshipPrefix: String { shared.cdn0CensorshipPrefix }
    @objc
    public static var cdn2CensorshipPrefix: String { shared.cdn2CensorshipPrefix }
    @objc
    public static var contactDiscoveryCensorshipPrefix: String { shared.contactDiscoveryCensorshipPrefix }
    @objc
    public static var keyBackupCensorshipPrefix: String { shared.keyBackupCensorshipPrefix }
    @objc
    public static var storageServiceCensorshipPrefix: String { shared.storageServiceCensorshipPrefix }

    @objc
    public static var contactDiscoveryEnclaveName: String { shared.contactDiscoveryEnclaveName }
    @objc
    public static var contactDiscoveryMrEnclave: String { shared.contactDiscoveryMrEnclave }
    @objc
    public static var contactDiscoveryPublicKey: String { shared.contactDiscoveryPublicKey }
    @objc
    public static var contactDiscoveryCodeHashes: [String] { shared.contactDiscoveryCodeHashes }

    static var keyBackupEnclave: KeyBackupEnclave { shared.keyBackupEnclave }
    static var keyBackupPreviousEnclaves: [KeyBackupEnclave] { shared.keyBackupPreviousEnclaves }

    @objc
    public static var applicationGroup: String { shared.applicationGroup }

    @objc
    public static var serverPublicParamsBase64: String { shared.serverPublicParamsBase64 }

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

private protocol TSConstantsProtocol: AnyObject {
    var mainServiceWebSocketAPI_identified: String { get }
    var mainServiceWebSocketAPI_unidentified: String { get }
    var mainServiceURL: String { get }
    var textSecureCDN0ServerURL: String { get }
    var textSecureCDN2ServerURL: String { get }
    var contactDiscoverySGXURL: String { get }
    var contactDiscoveryHSMURL: String { get }
    var keyBackupURL: String { get }
    var storageServiceURL: String { get }
    var sfuURL: String { get }
    var sfuTestURL: String { get }
    var kUDTrustRoot: String { get }
    var updatesURL: String { get }
    var updates2URL: String { get }

    var censorshipReflectorHost: String { get }

    var serviceCensorshipPrefix: String { get }
    var cdn0CensorshipPrefix: String { get }
    var cdn2CensorshipPrefix: String { get }
    var contactDiscoveryCensorshipPrefix: String { get }
    var keyBackupCensorshipPrefix: String { get }
    var storageServiceCensorshipPrefix: String { get }

    // SGX Backed Contact Discovery
    var contactDiscoveryEnclaveName: String { get }
    var contactDiscoveryMrEnclave: String { get }

    // HSM Backed Contact Discovery
    var contactDiscoveryPublicKey: String { get }
    var contactDiscoveryCodeHashes: [String] { get }

    var keyBackupEnclave: KeyBackupEnclave { get }
    var keyBackupPreviousEnclaves: [KeyBackupEnclave] { get }

    var applicationGroup: String { get }

    var serverPublicParamsBase64: String { get }
}

public struct KeyBackupEnclave: Equatable {
    let name: String
    let mrenclave: String
    let serviceId: String
}

// MARK: - Production

private class TSConstantsProduction: TSConstantsProtocol {

    public let mainServiceWebSocketAPI_identified = "wss://chat.signal.org/v1/websocket/"
    public let mainServiceWebSocketAPI_unidentified = "wss://ud-chat.signal.org/v1/websocket/"
    public let mainServiceURL = "https://chat.signal.org/"
    public let textSecureCDN0ServerURL = "https://cdn.signal.org"
    public let textSecureCDN2ServerURL = "https://cdn2.signal.org"
    public let contactDiscoverySGXURL = "https://api.directory.signal.org"
    public let contactDiscoveryHSMURL = "wss://cdsh.signal.org/discovery/"
    public let keyBackupURL = "https://api.backup.signal.org"
    public let storageServiceURL = "https://storage.signal.org"
    public let sfuURL = "https://sfu.voip.signal.org"
    public let sfuTestURL = "https://sfu.test.voip.signal.org"
    public let kUDTrustRoot = "BXu6QIKVz5MA8gstzfOgRQGqyLqOwNKHL6INkv3IHWMF"
    public let updatesURL = "https://updates.signal.org"
    public let updates2URL = "https://updates2.signal.org"

    public let censorshipReflectorHost = "europe-west1-signal-cdn-reflector.cloudfunctions.net"

    public let serviceCensorshipPrefix = "service"
    public let cdn0CensorshipPrefix = "cdn"
    public let cdn2CensorshipPrefix = "cdn2"
    public let contactDiscoveryCensorshipPrefix = "directory"
    public let keyBackupCensorshipPrefix = "backup"
    public let storageServiceCensorshipPrefix = "storage"

    public let contactDiscoveryEnclaveName = "c98e00a4e3ff977a56afefe7362a27e4961e4f19e211febfbb19b897e6b80b15"
    public var contactDiscoveryMrEnclave: String {
        return contactDiscoveryEnclaveName
    }

    public var contactDiscoveryPublicKey: String {
        owsFailDebug("CDSH unsupported in production")
        return ""
    }
    public var contactDiscoveryCodeHashes: [String] {
        owsFailDebug("CDSH unsupported in production")
        return []
    }

    public let keyBackupEnclave = KeyBackupEnclave(
        name: "0cedba03535b41b67729ce9924185f831d7767928a1d1689acb689bc079c375f",
        mrenclave: "ee19f1965b1eefa3dc4204eb70c04f397755f771b8c1909d080c04dad2a6a9ba",
        serviceId: "187d2739d22be65e74b65f0055e74d31310e4267e5fac2b1246cc8beba81af39"
    )

    // An array of previously used enclaves that we should try and restore
    // key material from during registration. These must be ordered from
    // newest to oldest, so we check the latest enclaves for backups before
    // checking earlier enclaves.
    public let keyBackupPreviousEnclaves = [
        KeyBackupEnclave(
            name: "fe7c1bfae98f9b073d220366ea31163ee82f6d04bead774f71ca8e5c40847bfe",
            mrenclave: "a3baab19ef6ce6f34ab9ebb25ba722725ae44a8872dc0ff08ad6d83a9489de87",
            serviceId: "fe7c1bfae98f9b073d220366ea31163ee82f6d04bead774f71ca8e5c40847bfe"
        )
    ]

    public let applicationGroup = "group.org.whispersystems.signal.group"

    // We need to discard all profile key credentials if these values ever change.
    // See: GroupsV2Impl.verifyServerPublicParams(...)
    public let serverPublicParamsBase64 = "AMhf5ywVwITZMsff/eCyudZx9JDmkkkbV6PInzG4p8x3VqVJSFiMvnvlEKWuRob/1eaIetR31IYeAbm0NdOuHH8Qi+Rexi1wLlpzIo1gstHWBfZzy1+qHRV5A4TqPp15YzBPm0WSggW6PbSn+F4lf57VCnHF7p8SvzAA2ZZJPYJURt8X7bbg+H3i+PEjH9DXItNEqs2sNcug37xZQDLm7X36nOoGPs54XsEGzPdEV+itQNGUFEjY6X9Uv+Acuks7NpyGvCoKxGwgKgE5XyJ+nNKlyHHOLb6N1NuHyBrZrgtY/JYJHRooo5CEqYKBqdFnmbTVGEkCvJKxLnjwKWf+fEPoWeQFj5ObDjcKMZf2Jm2Ae69x+ikU5gBXsRmoF94GXQ=="
}

// MARK: - Staging

private class TSConstantsStaging: TSConstantsProtocol {

    public let mainServiceWebSocketAPI_identified = "wss://chat.staging.signal.org/v1/websocket/"
    public let mainServiceWebSocketAPI_unidentified = "wss://ud-chat.staging.signal.org/v1/websocket/"
    public let mainServiceURL = "https://chat.staging.signal.org/"
    public let textSecureCDN0ServerURL = "https://cdn-staging.signal.org"
    public let textSecureCDN2ServerURL = "https://cdn2-staging.signal.org"
    public let contactDiscoverySGXURL = "https://api-staging.directory.signal.org"
    public let contactDiscoveryHSMURL = "wss://cdsh.staging.signal.org/discovery/"
    public let keyBackupURL = "https://api-staging.backup.signal.org"
    public let storageServiceURL = "https://storage-staging.signal.org"
    public let sfuURL = "https://sfu.staging.voip.signal.org"
    // There's no separate test SFU for staging.
    public let sfuTestURL = "https://sfu.test.voip.signal.org"
    public let kUDTrustRoot = "BbqY1DzohE4NUZoVF+L18oUPrK3kILllLEJh2UnPSsEx"
    // There's no separate updates endpoint for staging.
    public let updatesURL = "https://updates.signal.org"
    public let updates2URL = "https://updates2.signal.org"

    public let censorshipReflectorHost = "europe-west1-signal-cdn-reflector.cloudfunctions.net"

    public let serviceCensorshipPrefix = "service-staging"
    public let cdn0CensorshipPrefix = "cdn-staging"
    public let cdn2CensorshipPrefix = "cdn2-staging"
    public let contactDiscoveryCensorshipPrefix = "directory-staging"
    public let keyBackupCensorshipPrefix = "backup-staging"
    public let storageServiceCensorshipPrefix = "storage-staging"

    // CDS uses the same EnclaveName and MrEnclave
    public let contactDiscoveryEnclaveName = "c98e00a4e3ff977a56afefe7362a27e4961e4f19e211febfbb19b897e6b80b15"
    public var contactDiscoveryMrEnclave: String {
        return contactDiscoveryEnclaveName
    }

    public let contactDiscoveryPublicKey = "2fe57da347cd62431528daac5fbb290730fff684afc4cfc2ed90995f58cb3b74"
    public let contactDiscoveryCodeHashes = [
        "2f79dc6c1599b71c70fc2d14f3ea2e3bc65134436eb87011c88845b137af673a"
    ]

    public let keyBackupEnclave = KeyBackupEnclave(
        name: "dd6f66d397d9e8cf6ec6db238e59a7be078dd50e9715427b9c89b409ffe53f99",
        mrenclave: "ee19f1965b1eefa3dc4204eb70c04f397755f771b8c1909d080c04dad2a6a9ba",
        serviceId: "4200003414528c151e2dccafbc87aa6d3d66a5eb8f8c05979a6e97cb33cd493a"
    )

    // An array of previously used enclaves that we should try and restore
    // key material from during registration. These must be ordered from
    // newest to oldest, so we check the latest enclaves for backups before
    // checking earlier enclaves.
    public let keyBackupPreviousEnclaves = [
        KeyBackupEnclave(
            name: "dcd2f0b7b581068569f19e9ccb6a7ab1a96912d09dde12ed1464e832c63fa948",
            mrenclave: "9db0568656c53ad65bb1c4e1b54ee09198828699419ec0f63cf326e79827ab23",
            serviceId: "446a6e51956e0eed502c6d9626476cea5b7278829098c34ca0cdce329753a8ee"
        ),
        KeyBackupEnclave(
            name: "823a3b2c037ff0cbe305cc48928cfcc97c9ed4a8ca6d49af6f7d6981fb60a4e9",
            mrenclave: "a3baab19ef6ce6f34ab9ebb25ba722725ae44a8872dc0ff08ad6d83a9489de87",
            serviceId: "16b94ac6d2b7f7b9d72928f36d798dbb35ed32e7bb14c42b4301ad0344b46f29"
        )
    ]

    public let applicationGroup = "group.org.whispersystems.signal.group.staging"

    // We need to discard all profile key credentials if these values ever change.
    // See: GroupsV2Impl.verifyServerPublicParams(...)
    public let serverPublicParamsBase64 = "ABSY21VckQcbSXVNCGRYJcfWHiAMZmpTtTELcDmxgdFbtp/bWsSxZdMKzfCp8rvIs8ocCU3B37fT3r4Mi5qAemeGeR2X+/YmOGR5ofui7tD5mDQfstAI9i+4WpMtIe8KC3wU5w3Inq3uNWVmoGtpKndsNfwJrCg0Hd9zmObhypUnSkfYn2ooMOOnBpfdanRtrvetZUayDMSC5iSRcXKpdlukrpzzsCIvEwjwQlJYVPOQPj4V0F4UXXBdHSLK05uoPBCQG8G9rYIGedYsClJXnbrgGYG3eMTG5hnx4X4ntARBgELuMWWUEEfSK0mjXg+/2lPmWcTZWR9nkqgQQP0tbzuiPm74H2wMO4u1Wafe+UwyIlIT9L7KLS19Aw8r4sPrXQ=="
}
