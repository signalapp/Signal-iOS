//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AppVersion {

    var hardwareInfoString: String { get }
    var iosVersionString: String { get }

    /// The version of the app when it was first launched. If this is the first launch, this will
    /// match `currentAppReleaseVersion`.
    var firstAppVersion: String { get }

    /// The version of the app the last time it was launched. `nil` if the app hasn't been launched.
    var lastAppVersion: String? { get }

    /// Internally, we use a version format with 4 dotted values
    /// to uniquely identify builds. The first three values are the
    /// the release version, the fourth value is the last value from
    /// the build version.
    ///
    /// For example, `3.4.5.6`.
    var currentAppVersion4: String { get }

    /// Uniquely identifies the build within the release track, in the format specified by Apple.
    /// For example, `6`.
    ///
    /// See:
    ///
    /// * https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleshortversionstring
    /// * https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleversion
    /// * https://developer.apple.com/library/archive/technotes/tn2420/_index.html
    var currentAppBuildVersion: String { get }

    /// The release track, such as `3.4.5`.
    var currentAppReleaseVersion: String { get }

    var lastCompletedLaunchAppVersion: String? { get }
    var lastCompletedLaunchMainAppVersion: String? { get }
    var lastCompletedLaunchSAEAppVersion: String? { get }
    var lastCompletedLaunchNSEAppVersion: String? { get }

    var buildDate: Date { get }

    /// Compares the two given version strings. Parses each string as a dot-separated list of
    /// components, and does a pairwise comparison of each string's corresponding components. If any
    /// component is not interpretable as an unsigned integer, the value `0` will be used.
    func compare(_ lhs: String, with rhs: String) -> ComparisonResult

    func mainAppLaunchDidComplete()
    func saeLaunchDidComplete()
    func nseLaunchDidComplete()
}

public class AppVersionImpl: AppVersion {
    private let firstVersionKey = "kNSUserDefaults_FirstAppVersion"
    private let lastVersionKey = "kNSUserDefaults_LastVersion"
    private let lastCompletedLaunchVersionKey = "kNSUserDefaults_LastCompletedLaunchAppVersion"
    private let lastCompletedMainAppLaunchVersionKey = "kNSUserDefaults_LastCompletedLaunchAppVersion_MainApp"
    private let lastCompletedSAELaunchVersionKey = "kNSUserDefaults_LastCompletedLaunchAppVersion_SAE"
    private let lastCompletedNSELaunchVersionKey = "kNSUserDefaults_LastCompletedLaunchAppVersion_NSE"

    public static let shared: AppVersion = {
        let result = AppVersionImpl(
            bundle: Bundle.main,
            userDefaults: CurrentAppContext().appUserDefaults()
        )
        result.save()
        result.startupLogging()
        return result
    }()

    // MARK: - Properties

    public var hardwareInfoString: String {
        let marketingString = UIDevice.current.model
        let machineString = String(sysctlKey: "hw.machine") ?? "nil"
        let modelString = String(sysctlKey: "hw.model") ?? "nil"
        return "\(marketingString) (\(machineString); \(modelString))"
    }

    public var iosVersionString: String {
        let majorMinor = UIDevice.current.systemVersion
        let buildNumber = String(sysctlKey: "kern.osversion") ?? "nil"
        return "\(majorMinor) (\(buildNumber))"
    }

    private let userDefaults: UserDefaults

    /// The version of the app when it was first launched. If this is the first launch, this will
    /// match `currentAppReleaseVersion`.
    public var firstAppVersion: String {
        return userDefaults.string(forKey: firstVersionKey) ?? currentAppReleaseVersion
    }

    /// The version of the app the last time it was launched. `nil` if the app hasn't been launched.
    public var lastAppVersion: String? { userDefaults.string(forKey: lastVersionKey) }

    /// Internally, we use a version format with 4 dotted values
    /// to uniquely identify builds. The first three values are the
    /// the release version, the fourth value is the last value from
    /// the build version.
    ///
    /// For example, `3.4.5.6`.
    public let currentAppVersion4: String

    /// Uniquely identifies the build within the release track, in the format specified by Apple.
    /// For example, `6`.
    ///
    /// See:
    ///
    /// * https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleshortversionstring
    /// * https://developer.apple.com/documentation/bundleresources/information_property_list/cfbundleversion
    /// * https://developer.apple.com/library/archive/technotes/tn2420/_index.html
    public let currentAppBuildVersion: String

    /// The release track, such as `3.4.5`.
    public let currentAppReleaseVersion: String

    public var lastCompletedLaunchAppVersion: String? {
        return userDefaults.string(forKey: lastCompletedLaunchVersionKey)
    }
    public private(set) var lastCompletedLaunchMainAppVersion: String? {
        get { userDefaults.string(forKey: lastCompletedMainAppLaunchVersionKey) }
        set {
            userDefaults.setOrRemove(newValue, forKey: lastCompletedLaunchVersionKey)
            userDefaults.setOrRemove(newValue, forKey: lastCompletedMainAppLaunchVersionKey)
        }
    }
    public private(set) var lastCompletedLaunchSAEAppVersion: String? {
        get { userDefaults.string(forKey: lastCompletedSAELaunchVersionKey) }
        set {
            userDefaults.setOrRemove(newValue, forKey: lastCompletedLaunchVersionKey)
            userDefaults.setOrRemove(newValue, forKey: lastCompletedSAELaunchVersionKey)
        }
    }
    public private(set) var lastCompletedLaunchNSEAppVersion: String? {
        get { userDefaults.string(forKey: lastCompletedNSELaunchVersionKey) }
        set {
            userDefaults.setOrRemove(newValue, forKey: lastCompletedLaunchVersionKey)
            userDefaults.setOrRemove(newValue, forKey: lastCompletedNSELaunchVersionKey)
        }
    }

    public let buildDate: Date

    // MARK: - Setup

    private init(bundle: Bundle, userDefaults: UserDefaults) {
        self.currentAppReleaseVersion = bundle.string(forInfoDictionaryKey: "CFBundleShortVersionString")
        self.currentAppBuildVersion = bundle.string(forInfoDictionaryKey: "CFBundleVersion")
        self.currentAppVersion4 = bundle.string(forInfoDictionaryKey: "OWSBundleVersion4")

        if
            let rawBuildDetails = bundle.app.object(forInfoDictionaryKey: "BuildDetails"),
            let buildDetails = rawBuildDetails as? [String: Any],
            let buildTimestamp = buildDetails["Timestamp"] as? TimeInterval {
            self.buildDate = Date(timeIntervalSince1970: buildTimestamp)
        } else {
            #if !TESTABLE_BUILD
            owsFailBeta("Expected a build date to be defined. Assuming build date is right now")
            #endif
            self.buildDate = Date()
        }

        self.userDefaults = userDefaults
    }

    private func save() {
        if userDefaults.string(forKey: firstVersionKey) == nil {
            userDefaults.set(currentAppReleaseVersion, forKey: firstVersionKey)
        }
        userDefaults.set(currentAppReleaseVersion, forKey: lastVersionKey)
    }

    private func startupLogging() {
        Logger.info("firstAppVersion: \(firstAppVersion)")
        Logger.info("lastAppVersion: \(lastAppVersion ?? "none")")
        Logger.info("currentAppReleaseVersion: \(currentAppReleaseVersion)")
        Logger.info("currentAppBuildVersion: \(currentAppBuildVersion)")

        // The long version string looks like an IPv4 address. To prevent the log scrubber from
        // scrubbing it, we replace `.` with `_`.
        let currentAppVersion4Formatted = currentAppVersion4.replacingOccurrences(of: ".", with: "_")
        Logger.info("currentAppVersion4: \(currentAppVersion4Formatted)")

        Logger.info("lastCompletedLaunchAppVersion: \(lastCompletedLaunchAppVersion ?? "none")")
        Logger.info("lastCompletedLaunchMainAppVersion: \(lastCompletedLaunchMainAppVersion ?? "none")")
        Logger.info("lastCompletedLaunchSAEAppVersion: \(lastCompletedLaunchSAEAppVersion ?? "none")")
        Logger.info("lastCompletedLaunchNSEAppVersion: \(lastCompletedLaunchNSEAppVersion ?? "none")")

        let databaseCorruptionState = DatabaseCorruptionState(userDefaults: userDefaults)
        Logger.info("Database corruption state: \(databaseCorruptionState)")

        Logger.info("iOS Version: \(iosVersionString)")

        let locale = Locale.current
        Logger.info("Locale Identifier: \(locale.identifier)")
        if let countryCode = (locale as NSLocale).countryCode {
            Logger.info("Country Code: \(countryCode)")
        }
        if let languageCode = locale.languageCode {
            Logger.info("Language Code: \(languageCode)")
        }

        Logger.info("Device Model: \(hardwareInfoString)")

        if DebugFlags.internalLogging {
            if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
                Logger.info("Bundle Name: \(bundleName)")
            }
            if let bundleDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                Logger.info("Bundle Display Name: \(bundleDisplayName)")
            }
        }

        if let buildDetails = Bundle.main.object(forInfoDictionaryKey: "BuildDetails") as? [String: Any] {
            if let signalCommit = buildDetails["SignalCommit"] as? String {
                Logger.info("Signal Commit: \(signalCommit)")
            }
            if let xcodeVersion = buildDetails["XCodeVersion"] as? String {
                Logger.info("Build XCode Version: \(xcodeVersion)")
            }
            if let buildTime = buildDetails["DateTime"] as? String {
                Logger.info("Build Date/Time: \(buildTime)")
            }
        }

        Logger.info("Core count: \(LocalDevice.allCoreCount) (active: \(LocalDevice.activeCoreCount)")
    }

    // MARK: - Events

    public func mainAppLaunchDidComplete() {
        Logger.info("")
        lastCompletedLaunchMainAppVersion = currentAppReleaseVersion
    }

    public func saeLaunchDidComplete() {
        Logger.info("")
        lastCompletedLaunchSAEAppVersion = currentAppReleaseVersion
    }

    public func nseLaunchDidComplete() {
        Logger.info("")
        lastCompletedLaunchNSEAppVersion = currentAppReleaseVersion
    }

    // MARK: - Comparing app versions

    /// Compares the two given version strings. Parses each string as a dot-separated list of
    /// components, and does a pairwise comparison of each string's corresponding components. If any
    /// component is not interpretable as an unsigned integer, the value `0` will be used.
    public func compare(_ lhs: String, with rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.components(separatedBy: ".")
        let rhsComponents = rhs.components(separatedBy: ".")

        let largestCount = max(lhsComponents.count, rhsComponents.count)
        for index in (0..<largestCount) {
            let lhsComponent = parseVersionComponent(lhsComponents[safe: index])
            let rhsComponent = parseVersionComponent(rhsComponents[safe: index])
            if lhsComponent != rhsComponent {
                return (lhsComponent < rhsComponent) ? .orderedAscending : .orderedDescending
            }
        }

        return .orderedSame
    }

    private func parseVersionComponent(_ versionComponent: String?) -> UInt {
        guard let versionComponent else { return 0 }
        return UInt(versionComponent) ?? 0
    }
}

// MARK: - Objective-C interop

@objc(AppVersion)
@objcMembers
public class AppVersionForObjC: NSObject {
    public static var shared: AppVersionForObjC { .init(AppVersionImpl.shared) }

    private var appVersion: AppVersion

    public var lastCompletedLaunchAppVersion: String? { appVersion.lastCompletedLaunchAppVersion }
    public var lastCompletedLaunchMainAppVersion: String? { appVersion.lastCompletedLaunchMainAppVersion }
    public var currentAppReleaseVersion: String { appVersion.currentAppReleaseVersion }

    private init(_ appVersion: AppVersion) {
        self.appVersion = appVersion
    }

    public func mainAppLaunchDidComplete() { appVersion.mainAppLaunchDidComplete() }

    public func saeLaunchDidComplete() { appVersion.saeLaunchDidComplete() }

    public func nseLaunchDidComplete() { appVersion.nseLaunchDidComplete() }
}

// MARK: - Helpers

fileprivate extension Bundle {
    func string(forInfoDictionaryKey key: String) -> String {
        guard let result = object(forInfoDictionaryKey: key) as? String else {
            owsFail("Couldn't fetch string from \(key)")
        }
        if result.isEmpty {
            owsFail("String is unexpectedly empty")
        }
        return result
    }
}

fileprivate extension UserDefaults {
    func setOrRemove(_ str: String?, forKey key: String) {
        if let str {
            set(str, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

// MARK: - Mock

#if TESTABLE_BUILD

public class MockAppVerion: AppVersion {

    public init() {}

    public var hardwareInfoString: String = ""

    public var iosVersionString: String = "16.0"

    public var firstAppVersion: String = "1.0"

    public var lastAppVersion: String? = "1.0"

    public var currentAppVersion4: String = "1.0.0.0"

    public var currentAppBuildVersion: String = "1"

    public var currentAppReleaseVersion: String = "1.0.0"

    public var lastCompletedLaunchAppVersion: String?

    public var lastCompletedLaunchMainAppVersion: String?

    public var lastCompletedLaunchSAEAppVersion: String?

    public var lastCompletedLaunchNSEAppVersion: String?

    public var buildDate: Date = Date()

    public func compare(_ lhs: String, with rhs: String) -> ComparisonResult {
        // TODO: Stub for testing
        return .orderedSame
    }

    public func mainAppLaunchDidComplete() {}

    public func saeLaunchDidComplete() {}

    public func nseLaunchDidComplete() {}
}

#endif
