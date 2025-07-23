//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: -

import Foundation
public import LibSignalClient

public class TSConstants {

    private enum Environment {
        case production, staging
    }
    private static let environment: Environment = {
        // You can set "USE_STAGING=1" in your Xcode Scheme. This allows you to
        // prepare a series of commits without accidentally committing the change
        // to the environment.
        #if DEBUG
        if ProcessInfo.processInfo.environment["USE_STAGING"] == "1" {
            return .staging
        }
        #endif

        // If you do want to make a build that will always connect to staging,
        // change this value. (Scheme environment variables are only set when
        // launching via Xcode, so this approach is still quite useful.)
        return .production
    }()

    public static var isUsingProductionService: Bool {
        return environment == .production
    }

    // Never instantiate this class.
    private init() {}

    public static let legalTermsUrl = URL(string: "https://signal.org/legal/")!
    public static let donateUrl = URL(string: "https://signal.org/donate/")!
    public static let appStoreUrl = URL(string: "https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8")!

    public static var mainServiceIdentifiedURL: String { shared.mainServiceIdentifiedURL }
    public static var mainServiceUnidentifiedURL: String { shared.mainServiceUnidentifiedURL }

    public static var textSecureCDN0ServerURL: String { shared.textSecureCDN0ServerURL }
    public static var textSecureCDN2ServerURL: String { shared.textSecureCDN2ServerURL }
    public static var textSecureCDN3ServerURL: String { shared.textSecureCDN3ServerURL }
    public static var storageServiceURL: String { shared.storageServiceURL }
    public static var sfuURL: String { shared.sfuURL }
    public static var sfuTestURL: String { shared.sfuTestURL }
    public static var svr2URL: String { shared.svr2URL }
    public static var registrationCaptchaURL: String { shared.registrationCaptchaURL }
    public static var challengeCaptchaURL: String { shared.challengeCaptchaURL }
    public static var kUDTrustRoot: String { shared.kUDTrustRoot }
    public static var updatesURL: String { shared.updatesURL }
    public static var updates2URL: String { shared.updates2URL }

    public static var censorshipFReflectorHost: String { shared.censorshipFReflectorHost }
    public static var censorshipGReflectorHost: String { shared.censorshipGReflectorHost }

    public static var serviceCensorshipPrefix: String { shared.serviceCensorshipPrefix }
    public static var cdn0CensorshipPrefix: String { shared.cdn0CensorshipPrefix }
    public static var cdn2CensorshipPrefix: String { shared.cdn2CensorshipPrefix }
    public static var cdn3CensorshipPrefix: String { shared.cdn3CensorshipPrefix }
    public static var storageServiceCensorshipPrefix: String { shared.storageServiceCensorshipPrefix }
    public static var svr2CensorshipPrefix: String { shared.svr2CensorshipPrefix }

    static var svr2Enclave: MrEnclave { shared.svr2Enclave }
    static var svr2PreviousEnclaves: [MrEnclave] { shared.svr2PreviousEnclaves }

    public static var applicationGroup: String { shared.applicationGroup }

    public static var serverPublicParams: Data { shared.serverPublicParams }
    public static var callLinkPublicParams: Data { shared.callLinkPublicParams }
    public static var backupServerPublicParams: Data { shared.backupServerPublicParams }

    public static let shared: TSConstantsProtocol = {
        switch environment {
        case .production:
            return TSConstantsProduction()
        case .staging:
            return TSConstantsStaging()
        }
    }()

    public static let libSignalEnv: Net.Environment = {
        switch environment {
        case .production:
            return .production
        case .staging:
            return .staging
        }
    }()
}

// MARK: -

public protocol TSConstantsProtocol: AnyObject {
    var mainServiceIdentifiedURL: String { get }
    var mainServiceUnidentifiedURL: String { get }
    var textSecureCDN0ServerURL: String { get }
    var textSecureCDN2ServerURL: String { get }
    var textSecureCDN3ServerURL: String { get }
    var storageServiceURL: String { get }
    var sfuURL: String { get }
    var sfuTestURL: String { get }
    var svr2URL: String { get }
    var registrationCaptchaURL: String { get }
    var challengeCaptchaURL: String { get }
    var kUDTrustRoot: String { get }
    var updatesURL: String { get }
    var updates2URL: String { get }

    var censorshipFReflectorHost: String { get }
    var censorshipGReflectorHost: String { get }

    var serviceCensorshipPrefix: String { get }
    var cdn0CensorshipPrefix: String { get }
    var cdn2CensorshipPrefix: String { get }
    var cdn3CensorshipPrefix: String { get }
    var storageServiceCensorshipPrefix: String { get }
    var svr2CensorshipPrefix: String { get }

    var svr2Enclave: MrEnclave { get }
    var svr2PreviousEnclaves: [MrEnclave] { get }

    var applicationGroup: String { get }

    var serverPublicParams: Data { get }
    var callLinkPublicParams: Data { get }
    var backupServerPublicParams: Data { get }
}

public struct MrEnclave: Equatable {
    public let dataValue: Data
    public let stringValue: String

    init(_ stringValue: StaticString) {
        self.stringValue = String(describing: stringValue)
        // This is a constant -- it should never fail to parse.
        self.dataValue = Data.data(fromHex: self.stringValue)!
        // All of our MrEnclave values are currently 32 bytes.
        owsPrecondition(self.dataValue.count == 32)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.dataValue == rhs.dataValue
    }
}

// MARK: - Production

public class TSConstantsProduction: TSConstantsProtocol {

    public init() {}

    public let mainServiceIdentifiedURL = "https://chat.signal.org"
    public let mainServiceUnidentifiedURL = "https://ud-chat.signal.org"
    public let textSecureCDN0ServerURL = "https://cdn.signal.org"
    public let textSecureCDN2ServerURL = "https://cdn2.signal.org"
    public let textSecureCDN3ServerURL = "https://cdn3.signal.org"
    public let storageServiceURL = "https://storage.signal.org"
    public let sfuURL = "https://sfu.voip.signal.org"
    public let sfuTestURL = "https://sfu.test.voip.signal.org"
    public let svr2URL = "wss://svr2.signal.org"
    public let registrationCaptchaURL = "https://signalcaptchas.org/registration/generate.html"
    public let challengeCaptchaURL = "https://signalcaptchas.org/challenge/generate.html"
    public let kUDTrustRoot = "BXu6QIKVz5MA8gstzfOgRQGqyLqOwNKHL6INkv3IHWMF"
    public let updatesURL = "https://updates.signal.org"
    public let updates2URL = "https://updates2.signal.org"

    public let censorshipFReflectorHost = "reflector-signal.global.ssl.fastly.net"
    public let censorshipGReflectorHost = "reflector-nrgwuv7kwq-uc.a.run.app"

    public let serviceCensorshipPrefix = "service"
    public let cdn0CensorshipPrefix = "cdn"
    public let cdn2CensorshipPrefix = "cdn2"
    public let cdn3CensorshipPrefix = "cdn3"
    public let storageServiceCensorshipPrefix = "storage"
    public let svr2CensorshipPrefix = "svr2"

    public let svr2Enclave = MrEnclave("29cd63c87bea751e3bfd0fbd401279192e2e5c99948b4ee9437eafc4968355fb")

    // An array of previously used enclaves that we should try and restore
    // key material from during registration. These must be ordered from
    // newest to oldest, so we check the latest enclaves for backups before
    // checking earlier enclaves.
    public let svr2PreviousEnclaves: [MrEnclave] = [
        MrEnclave("093be9ea32405e85ae28dbb48eb668aebeb7dbe29517b9b86ad4bec4dfe0e6a6"),
        MrEnclave("9314436a9a144992bb3680770ea5fd7934a7ffd29257844a33763a238903d570"),
    ]

    public let applicationGroup = "group." + Bundle.main.bundleIdPrefix + ".signal.group"

    /// We *might* need to clear credentials (or perform some other migration)
    /// when this value changes, depending on how it's changing. If you do need
    /// to perform a migration, check out `ZkParamsMigrator`.
    public let serverPublicParams = Data(base64Encoded: "AMhf5ywVwITZMsff/eCyudZx9JDmkkkbV6PInzG4p8x3VqVJSFiMvnvlEKWuRob/1eaIetR31IYeAbm0NdOuHH8Qi+Rexi1wLlpzIo1gstHWBfZzy1+qHRV5A4TqPp15YzBPm0WSggW6PbSn+F4lf57VCnHF7p8SvzAA2ZZJPYJURt8X7bbg+H3i+PEjH9DXItNEqs2sNcug37xZQDLm7X36nOoGPs54XsEGzPdEV+itQNGUFEjY6X9Uv+Acuks7NpyGvCoKxGwgKgE5XyJ+nNKlyHHOLb6N1NuHyBrZrgtY/JYJHRooo5CEqYKBqdFnmbTVGEkCvJKxLnjwKWf+fEPoWeQFj5ObDjcKMZf2Jm2Ae69x+ikU5gBXsRmoF94GXTLfN0/vLt98KDPnxwAQL9j5V1jGOY8jQl6MLxEs56cwXN0dqCnImzVH3TZT1cJ8SW1BRX6qIVxEzjsSGx3yxF3suAilPMqGRp4ffyopjMD1JXiKR2RwLKzizUe5e8XyGOy9fplzhw3jVzTRyUZTRSZKkMLWcQ/gv0E4aONNqs4P+NameAZYOD12qRkxosQQP5uux6B2nRyZ7sAV54DgFyLiRcq1FvwKw2EPQdk4HDoePrO/RNUbyNddnM/mMgj4FW65xCoT1LmjrIjsv/Ggdlx46ueczhMgtBunx1/w8k8V+l8LVZ8gAT6wkU5J+DPQalQguMg12Jzug3q4TbdHiGCmD9EunCwOmsLuLJkz6EcSYXtrlDEnAM+hicw7iergYLLlMXpfTdGxJCWJmP4zqUFeTTmsmhsjGBt7NiEB/9pFFEB3pSbf4iiUukw63Eo8Aqnf4iwob6X1QviCWuc8t0LUlT9vALgh/f2DPVOOmR0RW6bgRvc7DSF20V/omg+YBw==")!

    public let callLinkPublicParams = Data(base64Encoded: "AByD873dTilmOSG0TjKrvpeaKEsUmIO8Vx9BeMmftwUs9v7ikPwM8P3OHyT0+X3EUMZrSe9VUp26Wai51Q9I8mdk0hX/yo7CeFGJyzoOqn8e/i4Ygbn5HoAyXJx5eXfIbqpc0bIxzju4H/HOQeOpt6h742qii5u/cbwOhFZCsMIbElZTaeU+BWMBQiZHIGHT5IE0qCordQKZ5iPZom0HeFa8Yq0ShuEyAl0WINBiY6xE3H/9WnvzXBbMuuk//eRxXgzO8ieCeK8FwQNxbfXqZm6Ro1cMhCOF3u7xoX83QhpN")!

    public let backupServerPublicParams = Data(base64Encoded: "AJwNSU55fsFCbgaxGRD11wO1juAs8Yr5GF8FPlGzzvdJJIKH5/4CC7ZJSOe3yL2vturVaRU2Cx0n751Vt8wkj1bozK3CBV1UokxV09GWf+hdVImLGjXGYLLhnI1J2TWEe7iWHyb553EEnRb5oxr9n3lUbNAJuRmFM7hrr0Al0F0wrDD4S8lo2mGaXe0MJCOM166F8oYRQqpFeEHfiLnxA1O8ZLh7vMdv4g9jI5phpRBTsJ5IjiJrWeP0zdIGHEssUeprDZ9OUJ14m0v61eYJMKsf59Bn+mAT2a7YfB+Don9O")!
}

// MARK: - Staging

public class TSConstantsStaging: TSConstantsProtocol {

    public init() {}

    public let mainServiceIdentifiedURL = "https://chat.staging.signal.org"
    public let mainServiceUnidentifiedURL = "https://ud-chat.staging.signal.org"
    public let textSecureCDN0ServerURL = "https://cdn-staging.signal.org"
    public let textSecureCDN2ServerURL = "https://cdn2-staging.signal.org"
    public let textSecureCDN3ServerURL = "https://cdn3-staging.signal.org"
    public let storageServiceURL = "https://storage-staging.signal.org"
    public let sfuURL = "https://sfu.staging.voip.signal.org"
    public let svr2URL = "wss://svr2.staging.signal.org"
    public let registrationCaptchaURL = "https://signalcaptchas.org/staging/registration/generate.html"
    public let challengeCaptchaURL = "https://signalcaptchas.org/staging/challenge/generate.html"
    // There's no separate test SFU for staging.
    public let sfuTestURL = "https://sfu.test.voip.signal.org"
    public let kUDTrustRoot = "BbqY1DzohE4NUZoVF+L18oUPrK3kILllLEJh2UnPSsEx"
    // There's no separate updates endpoint for staging.
    public let updatesURL = "https://updates.signal.org"
    public let updates2URL = "https://updates2.signal.org"

    public let censorshipFReflectorHost = "reflector-staging-signal.global.ssl.fastly.net"
    public let censorshipGReflectorHost = "reflector-nrgwuv7kwq-uc.a.run.app"

    public let serviceCensorshipPrefix = "service-staging"
    public let cdn0CensorshipPrefix = "cdn-staging"
    public let cdn2CensorshipPrefix = "cdn2-staging"
    public let cdn3CensorshipPrefix = "cdn3-staging"
    public let storageServiceCensorshipPrefix = "storage-staging"
    public let svr2CensorshipPrefix = "svr2-staging"

    public let svr2Enclave = MrEnclave("a75542d82da9f6914a1e31f8a7407053b99cc99a0e7291d8fbd394253e19b036")

    // An array of previously used enclaves that we should try and restore
    // key material from during registration. These must be ordered from
    // newest to oldest, so we check the latest enclaves for backups before
    // checking earlier enclaves.
    public let svr2PreviousEnclaves: [MrEnclave] = [
        MrEnclave("2e8cefe6e3f389d8426adb24e9b7fb7adf10902c96f06f7bbcee36277711ed91"),
        MrEnclave("38e01eff4fe357dc0b0e8ef7a44b4abc5489fbccba3a78780f3872c277f62bf3"),
    ]

    public let applicationGroup = "group." + Bundle.main.bundleIdPrefix + ".signal.group.staging"

    /// We *might* need to clear credentials (or perform some other migration)
    /// when this value changes, depending on how it's changing. If you do need
    /// to perform a migration, check out `ZkParamsMigrator`.
    public let serverPublicParams = Data(base64Encoded: "ABSY21VckQcbSXVNCGRYJcfWHiAMZmpTtTELcDmxgdFbtp/bWsSxZdMKzfCp8rvIs8ocCU3B37fT3r4Mi5qAemeGeR2X+/YmOGR5ofui7tD5mDQfstAI9i+4WpMtIe8KC3wU5w3Inq3uNWVmoGtpKndsNfwJrCg0Hd9zmObhypUnSkfYn2ooMOOnBpfdanRtrvetZUayDMSC5iSRcXKpdlukrpzzsCIvEwjwQlJYVPOQPj4V0F4UXXBdHSLK05uoPBCQG8G9rYIGedYsClJXnbrgGYG3eMTG5hnx4X4ntARBgELuMWWUEEfSK0mjXg+/2lPmWcTZWR9nkqgQQP0tbzuiPm74H2wMO4u1Wafe+UwyIlIT9L7KLS19Aw8r4sPrXZSSsOZ6s7M1+rTJN0bI5CKY2PX29y5Ok3jSWufIKcgKOnWoP67d5b2du2ZVJjpjfibNIHbT/cegy/sBLoFwtHogVYUewANUAXIaMPyCLRArsKhfJ5wBtTminG/PAvuBdJ70Z/bXVPf8TVsR292zQ65xwvWTejROW6AZX6aqucUjlENAErBme1YHmOSpU6tr6doJ66dPzVAWIanmO/5mgjNEDeK7DDqQdB1xd03HT2Qs2TxY3kCK8aAb/0iM0HQiXjxZ9HIgYhbtvGEnDKW5ILSUydqH/KBhW4Pb0jZWnqN/YgbWDKeJxnDbYcUob5ZY5Lt5ZCMKuaGUvCJRrCtuugSMaqjowCGRempsDdJEt+cMaalhZ6gczklJB/IbdwENW9KeVFPoFNFzhxWUIS5ML9riVYhAtE6JE5jX0xiHNVIIPthb458cfA8daR0nYfYAUKogQArm0iBezOO+mPk5vCNWI+wwkyFCqNDXz/qxl1gAntuCJtSfq9OC3NkdhQlgYQ==")!

    public let callLinkPublicParams = Data(base64Encoded: "AHILOIrFPXX9laLbalbA9+L1CXpSbM/bTJXZGZiuyK1JaI6dK5FHHWL6tWxmHKYAZTSYmElmJ5z2A5YcirjO/yfoemE03FItyaf8W1fE4p14hzb5qnrmfXUSiAIVrhaXVwIwSzH6RL/+EO8jFIjJ/YfExfJ8aBl48CKHgu1+A6kWynhttonvWWx6h7924mIzW0Czj2ROuh4LwQyZypex4GuOPW8sgIT21KNZaafgg+KbV7XM1x1tF3XA17B4uGUaDbDw2O+nR1+U5p6qHPzmJ7ggFjSN6Utu+35dS1sS0P9N")!

    public let backupServerPublicParams = Data(base64Encoded: "AHYrGb9IfugAAJiPKp+mdXUx+OL9zBolPYHYQz6GI1gWjpEu5me3zVNSvmYY4zWboZHif+HG1sDHSuvwFd0QszSwuSF4X4kRP3fJREdTZ5MCR0n55zUppTwfHRW2S4sdQ0JGz7YDQIJCufYSKh0pGNEHL6hv79Agrdnr4momr3oXdnkpVBIp3HWAQ6IbXQVSG18X36GaicI1vdT0UFmTwU2KTneluC2eyL9c5ff8PcmiS+YcLzh0OKYQXB5ZfQ06d6DiINvDQLy75zcfUOniLAj0lGJiHxGczin/RXisKSR8")!

}

#if TESTABLE_BUILD

public class TSConstantsMock: TSConstantsProtocol {

    public init() {}

    private let defaultValues = TSConstantsProduction()

    public lazy var mainServiceIdentifiedURL = defaultValues.mainServiceIdentifiedURL

    public lazy var mainServiceUnidentifiedURL = defaultValues.mainServiceUnidentifiedURL

    public lazy var textSecureCDN0ServerURL = defaultValues.textSecureCDN0ServerURL

    public lazy var textSecureCDN2ServerURL = defaultValues.textSecureCDN2ServerURL

    public lazy var textSecureCDN3ServerURL = defaultValues.textSecureCDN3ServerURL

    public lazy var storageServiceURL = defaultValues.storageServiceURL

    public lazy var sfuURL = defaultValues.sfuURL

    public lazy var sfuTestURL = defaultValues.sfuTestURL

    public lazy var svr2URL = defaultValues.svr2URL

    public lazy var registrationCaptchaURL = defaultValues.registrationCaptchaURL

    public lazy var challengeCaptchaURL = defaultValues.challengeCaptchaURL

    public lazy var kUDTrustRoot = defaultValues.kUDTrustRoot

    public lazy var updatesURL = defaultValues.updatesURL

    public lazy var updates2URL = defaultValues.updates2URL

    public lazy var censorshipFReflectorHost = defaultValues.censorshipFReflectorHost
    public lazy var censorshipGReflectorHost = defaultValues.censorshipGReflectorHost

    public lazy var serviceCensorshipPrefix = defaultValues.serviceCensorshipPrefix

    public lazy var cdn0CensorshipPrefix = defaultValues.cdn0CensorshipPrefix

    public lazy var cdn2CensorshipPrefix = defaultValues.cdn2CensorshipPrefix

    public lazy var cdn3CensorshipPrefix = defaultValues.cdn3CensorshipPrefix

    public lazy var storageServiceCensorshipPrefix = defaultValues.storageServiceCensorshipPrefix

    public lazy var svr2CensorshipPrefix = defaultValues.svr2CensorshipPrefix

    public lazy var svr2Enclave = defaultValues.svr2Enclave

    public lazy var svr2PreviousEnclaves = defaultValues.svr2PreviousEnclaves

    public lazy var applicationGroup = defaultValues.applicationGroup

    public lazy var serverPublicParams = defaultValues.serverPublicParams

    public lazy var callLinkPublicParams = defaultValues.callLinkPublicParams

    public lazy var backupServerPublicParams = defaultValues.backupServerPublicParams
}

#endif
