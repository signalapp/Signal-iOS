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

    public static var serverPublicParams: [UInt8] { shared.serverPublicParams }
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

    var serverPublicParams: [UInt8] { get }
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

private class TSConstantsProduction: TSConstantsProtocol {

    public let mainServiceIdentifiedURL = "https://chat.tapofthink.com"
    public let mainServiceUnidentifiedURL = "https://chat.tapofthink.com"
    public let textSecureCDN0ServerURL = "https://cdn.tapofthink.com"
    public let textSecureCDN2ServerURL = "https://cdn2.tapofthink.com"
    public let textSecureCDN3ServerURL = "https://cdn3.tapofthink.com"
    public let storageServiceURL = "https://storage.tapofthink.com"
    public let sfuURL = "https://sfu.tapofthink.com"
    public let sfuTestURL = "https://sfu-dev.tapofthink.com"
    public let svr2URL = "wss://svr2.tapofthink.com"
    public let registrationCaptchaURL = "https://hcaptcha.tapofthink.com/index.html"
    public let challengeCaptchaURL = "https://hcaptcha.tapofthink.com/index.html"
    public let kUDTrustRoot = "BeSnG+rbeaRzY/4zUxm2Ha12ZZITOs4MD5QuDWPbqqgj"
    public let updatesURL = "https://updates.signal.org"
    public let updates2URL = "https://cdn.tapofthink.com"

    public let censorshipFReflectorHost = "reflector-signal.global.ssl.fastly.net"
    public let censorshipGReflectorHost = "reflector-nrgwuv7kwq-uc.a.run.app"

    public let serviceCensorshipPrefix = "service"
    public let cdn0CensorshipPrefix = "cdn"
    public let cdn2CensorshipPrefix = "cdn2"
    public let cdn3CensorshipPrefix = "cdn3"
    public let storageServiceCensorshipPrefix = "storage"
    public let svr2CensorshipPrefix = "svr2"

    public let svr2Enclave = MrEnclave("38f055c0465b379aef56e3ba9318317eacca9432bdd3b3cab887d09eb84b379f")

    // An array of previously used enclaves that we should try and restore
    // key material from during registration. These must be ordered from
    // newest to oldest, so we check the latest enclaves for backups before
    // checking earlier enclaves.
    public let svr2PreviousEnclaves: [MrEnclave] = [
    ]

    public let applicationGroup = "group." + Bundle.main.bundleIdPrefix + ".com.group"

    /// We *might* need to clear credentials (or perform some other migration)
    /// when this value changes, depending on how it's changing. If you do need
    /// to perform a migration, check out `ZkParamsMigrator`.
    public let serverPublicParams = [UInt8](Data(base64Encoded: "ABAnr3zs35ijDRYRv9oVbKeBBTqf8tq8ZduF32VkpJYMgImd+68d8P7kDk6lcmLcRr/APdO4MkBK9N2e1STqshLCnmh4rjHdc8U7q61f+B2INSpV39KMTNmXsLg8bXTtVHZNJvTKs7lPFfcPnWsev+cdmjdl9AghmVR0V8z5xnRqaqZ8O3XRyPWmFa8z5gkFW2rEDtO3AP2Ah73y/0fa32fuaSD/rEWscXWh2L/KbY/1z0JWy5Ru1LLL8psExN8+Fg41swo1xb64faW6K4Pit1RrO+IS5tAC+q2HWYpZkIYXTmD1zPKHh0RAasFXGVlTKEU/yWTz7oEzbV2CM0/jZz4WhAqT68kbBFeqN6qUphaIrAIMH7sapbkqp5tJFzKZa9Zy8bu21ZV+5abJde5txkVUOOXl3EU2GFed5HN4t+8NMnqJxXN7kI//zWKTeHrkSancOPu3s+dRg8XPw/66BQAqTQi2MqDn3hMbPefFafjEGzJalU+qwZ+8OjFZNmkqT1a/0Bch2VIUoD/lhaoy6UzQgzv3cOrT7KovtDPnQcEJnpAizRezI9JSVtpjIGeYLoFjdmhbp2l/NgajgQaMxTM290NrYO/L3G7Fm9E7J52o6dZeL4Jfq+Uh2wkpsRWVfCbx6kxsyBZR2515p/vmabZvFNEWMAZ+9l1HolWMte4/0Lvd6LPq0U9Y9yf3LRc8qVemrBAM0V+VK+4SlZAdR2IUya5N4/NfHkN+BWB0IZA6oDYVxS1dvSmeh/Keiq5XBLhAofW2tFCOw4o6Obfb4t+Fw/7f7WSjSbXVJVoe9aBn4gQsRkJuJcwXpM7xOKbV9BJ2NYM0WlwTp2kzq0zVxQICDHKWWvCljXttsiAaFovphDbXPK1kNqEc8UrwZTNEBA==")!)

    public let callLinkPublicParams = Data(base64Encoded: "AGLk00y9k8ZdD8rONpj9MCVm0bwPyIo3tfa7Zi59kippDkRVFlaT+192wyVKNIUZmI8/x3a2G4Byc1zRUlPGDEoeUcnnRvF5kYM1/izgssNd0riRsscd8sS2fkv/khY1aSQZHXGED+kyfgr78XT7yl3gsgsuPd/Gz8nJ2dPcZSsx3N8Ckqdy8+ArrOGJFPqnpW77+sVRSuKExjUjKsQodwXo0VF7sphQttqOdtOHJZNk/1EfH5SLtvrBJB0Vy9uBK8Y2rNOZd4JkTlrvnw5a+wNaBHFYZOz6LyiyD0oxghIn")!

    public let backupServerPublicParams = Data(base64Encoded: "AGLk00y9k8ZdD8rONpj9MCVm0bwPyIo3tfa7Zi59kippDkRVFlaT+192wyVKNIUZmI8/x3a2G4Byc1zRUlPGDEoeUcnnRvF5kYM1/izgssNd0riRsscd8sS2fkv/khY1aSQZHXGED+kyfgr78XT7yl3gsgsuPd/Gz8nJ2dPcZSsx3N8Ckqdy8+ArrOGJFPqnpW77+sVRSuKExjUjKsQodwXo0VF7sphQttqOdtOHJZNk/1EfH5SLtvrBJB0Vy9uBK8Y2rNOZd4JkTlrvnw5a+wNaBHFYZOz6LyiyD0oxghIn")!
}

// MARK: - Staging

private class TSConstantsStaging: TSConstantsProtocol {

    public let mainServiceIdentifiedURL = "https://signal-server-dev.tapofthink.com"
    public let mainServiceUnidentifiedURL = "https://signal-server-dev.tapofthink.com"
    public let textSecureCDN0ServerURL = "https://cdn.tapofthink.com"
    public let textSecureCDN2ServerURL = "https://cdn2.tapofthink.com"
    public let textSecureCDN3ServerURL = "https://cdn3.tapofthink.com"
    public let storageServiceURL = "https://storage-dev.tapofthink.com"
    public let sfuURL = "https://sfu-dev.tapofthink.com"
    public let svr2URL = "wss://svr2-dev.tapofthink.com"
    public let registrationCaptchaURL = "https://hcaptcha.tapofthink.com/index.html"
    public let challengeCaptchaURL = "https://hcaptcha.tapofthink.com/index.html"
    // There's no separate test SFU for staging.
    public let sfuTestURL = "https://sfu-dev.tapofthink.com"
    public let kUDTrustRoot = "BeSnG+rbeaRzY/4zUxm2Ha12ZZITOs4MD5QuDWPbqqgj"
    // There's no separate updates endpoint for staging.
    public let updatesURL = "https://updates.signal.org"
    public let updates2URL = "https://cdn.tapofthink.com"

    public let censorshipFReflectorHost = "reflector-staging-signal.global.ssl.fastly.net"
    public let censorshipGReflectorHost = "reflector-nrgwuv7kwq-uc.a.run.app"

    public let serviceCensorshipPrefix = "service-staging"
    public let cdn0CensorshipPrefix = "cdn-staging"
    public let cdn2CensorshipPrefix = "cdn2-staging"
    public let cdn3CensorshipPrefix = "cdn3-staging"
    public let storageServiceCensorshipPrefix = "storage-staging"
    public let svr2CensorshipPrefix = "svr2-staging"

    public let svr2Enclave = MrEnclave("38e01eff4fe357dc0b0e8ef7a44b4abc5489fbccba3a78780f3872c277f62bf3")

    // An array of previously used enclaves that we should try and restore
    // key material from during registration. These must be ordered from
    // newest to oldest, so we check the latest enclaves for backups before
    // checking earlier enclaves.
    public let svr2PreviousEnclaves: [MrEnclave] = [
    ]

    public let applicationGroup = "group." + Bundle.main.bundleIdPrefix + ".group.staging"

    /// We *might* need to clear credentials (or perform some other migration)
    /// when this value changes, depending on how it's changing. If you do need
    /// to perform a migration, check out `ZkParamsMigrator`.
    public let serverPublicParams = [UInt8](Data(base64Encoded: "ABAnr3zs35ijDRYRv9oVbKeBBTqf8tq8ZduF32VkpJYMgImd+68d8P7kDk6lcmLcRr/APdO4MkBK9N2e1STqshLCnmh4rjHdc8U7q61f+B2INSpV39KMTNmXsLg8bXTtVHZNJvTKs7lPFfcPnWsev+cdmjdl9AghmVR0V8z5xnRqaqZ8O3XRyPWmFa8z5gkFW2rEDtO3AP2Ah73y/0fa32fuaSD/rEWscXWh2L/KbY/1z0JWy5Ru1LLL8psExN8+Fg41swo1xb64faW6K4Pit1RrO+IS5tAC+q2HWYpZkIYXTmD1zPKHh0RAasFXGVlTKEU/yWTz7oEzbV2CM0/jZz4WhAqT68kbBFeqN6qUphaIrAIMH7sapbkqp5tJFzKZa9Zy8bu21ZV+5abJde5txkVUOOXl3EU2GFed5HN4t+8NMnqJxXN7kI//zWKTeHrkSancOPu3s+dRg8XPw/66BQAqTQi2MqDn3hMbPefFafjEGzJalU+qwZ+8OjFZNmkqT1a/0Bch2VIUoD/lhaoy6UzQgzv3cOrT7KovtDPnQcEJnpAizRezI9JSVtpjIGeYLoFjdmhbp2l/NgajgQaMxTM290NrYO/L3G7Fm9E7J52o6dZeL4Jfq+Uh2wkpsRWVfCbx6kxsyBZR2515p/vmabZvFNEWMAZ+9l1HolWMte4/0Lvd6LPq0U9Y9yf3LRc8qVemrBAM0V+VK+4SlZAdR2IUya5N4/NfHkN+BWB0IZA6oDYVxS1dvSmeh/Keiq5XBLhAofW2tFCOw4o6Obfb4t+Fw/7f7WSjSbXVJVoe9aBn4gQsRkJuJcwXpM7xOKbV9BJ2NYM0WlwTp2kzq0zVxQICDHKWWvCljXttsiAaFovphDbXPK1kNqEc8UrwZTNEBA==")!)
    
    public let callLinkPublicParams = Data(base64Encoded: "AGLk00y9k8ZdD8rONpj9MCVm0bwPyIo3tfa7Zi59kippDkRVFlaT+192wyVKNIUZmI8/x3a2G4Byc1zRUlPGDEoeUcnnRvF5kYM1/izgssNd0riRsscd8sS2fkv/khY1aSQZHXGED+kyfgr78XT7yl3gsgsuPd/Gz8nJ2dPcZSsx3N8Ckqdy8+ArrOGJFPqnpW77+sVRSuKExjUjKsQodwXo0VF7sphQttqOdtOHJZNk/1EfH5SLtvrBJB0Vy9uBK8Y2rNOZd4JkTlrvnw5a+wNaBHFYZOz6LyiyD0oxghIn")!

    public let backupServerPublicParams = Data(base64Encoded: "AGLk00y9k8ZdD8rONpj9MCVm0bwPyIo3tfa7Zi59kippDkRVFlaT+192wyVKNIUZmI8/x3a2G4Byc1zRUlPGDEoeUcnnRvF5kYM1/izgssNd0riRsscd8sS2fkv/khY1aSQZHXGED+kyfgr78XT7yl3gsgsuPd/Gz8nJ2dPcZSsx3N8Ckqdy8+ArrOGJFPqnpW77+sVRSuKExjUjKsQodwXo0VF7sphQttqOdtOHJZNk/1EfH5SLtvrBJB0Vy9uBK8Y2rNOZd4JkTlrvnw5a+wNaBHFYZOz6LyiyD0oxghIn")!

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
