//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AppVersion {

    var hardwareInfoString: String { get }
    var iosVersionString: String { get }

    /// The version of the app when it was first launched. If this is the first
    /// launch, this will match `currentAppVersion`.
    var firstAppVersion: String { get }

    /// The version of the app that was first launched, of the app instance that generated the backup
    /// this app instance restored from, or nil if not restored from a backup.
    /// Version string may have originated from a non-iOS client.
    var firstBackupAppVersion: String? { get }

    /// The version of the app the last time it was launched. `nil` if the app
    /// hasn't been launched.
    var lastAppVersion: String? { get }

    /// Internally, we use a version format with 4 dotted values to uniquely
    /// identify builds. The first three values are the the release version, the
    /// fourth value is the last value from the build version.
    ///
    /// For example, `3.4.5.6`.
    var currentAppVersion: String { get }

    /// A user-visible "pretty" version number.
    ///
    /// Never sort or compare using this version number.
    var prettyAppVersion: String { get }

    var lastCompletedLaunchAppVersion: String? { get }
    var lastCompletedLaunchMainAppVersion: String? { get }
    var lastCompletedLaunchSAEAppVersion: String? { get }
    var lastCompletedLaunchNSEAppVersion: String? { get }
    var firstMainAppLaunchDateAfterUpdate: Date? { get }

    var buildDate: Date { get }

    func mainAppLaunchDidComplete()
    func saeLaunchDidComplete()
    func nseLaunchDidComplete()
    func didRestoreFromBackup(
        backupCurrentAppVersion: String?,
        backupFirstAppVersion: String?
    )
}

extension AppVersion {
    public var currentAppVersion4: AppVersionNumber4 {
        return try! AppVersionNumber4(AppVersionNumber(currentAppVersion))
    }
}

public struct AppVersionNumber: Comparable, CustomDebugStringConvertible, Decodable, Equatable {
    public var rawValue: String
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue.compare(rhs.rawValue, options: .numeric) == .orderedAscending
    }

    public var debugDescription: String {
        return formatForLogging(rawValue)
    }
}

public struct AppVersionNumber4: Comparable, CustomDebugStringConvertible, Decodable, Equatable {
    public let wrappedValue: AppVersionNumber
    public init(_ wrappedValue: AppVersionNumber) throws {
        let components = wrappedValue.rawValue.components(separatedBy: ".")
        guard components.count == 4, components.lazy.compactMap(Int.init(_:)).count == 4 else {
            throw OWSGenericError("Version number doesn't have 4 integer parts.")
        }
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(AppVersionNumber.self))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.wrappedValue < rhs.wrappedValue
    }

    public var debugDescription: String {
        return wrappedValue.debugDescription
    }
}

private func formatForLogging(_ versionNumber: String?) -> String {
    if let versionNumber {
        // The long version string looks like an IPv4 address. To prevent the log
        // scrubber from scrubbing it, we replace `.` with `_`.
        return versionNumber.replacingOccurrences(of: ".", with: "_")
    } else {
        return "none"
    }
}

public class AppVersionImpl: AppVersion {
    private let firstVersionKey = "kNSUserDefaults_FirstAppVersion"
    private let backupAppVersionKey = "kNSUserDefaults_BackupAppVersion"
    private let firstBackupAppVersionKey = "kNSUserDefaults_FirstBackupAppVersion"
    private let lastVersionKey = "kNSUserDefaults_LastVersion"
    private let lastCompletedLaunchVersionKey = "kNSUserDefaults_LastCompletedLaunchAppVersion"
    private let lastCompletedMainAppLaunchVersionKey = "kNSUserDefaults_LastCompletedLaunchAppVersion_MainApp"
    private let lastCompletedSAELaunchVersionKey = "kNSUserDefaults_LastCompletedLaunchAppVersion_SAE"
    private let lastCompletedNSELaunchVersionKey = "kNSUserDefaults_LastCompletedLaunchAppVersion_NSE"
    private let firstMainAppLaunchDateAfterUpdateKey = "FirstMainAppLaunchDateAfterUpdate"

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

    /// The version of the app when it was first launched. If this is the first
    /// launch, this will match `currentAppVersion`.
    public var firstAppVersion: String {
        return userDefaults.string(forKey: firstVersionKey) ?? currentAppVersion
    }

    /// The app version string of the app instance that generated the backup this app instance restored from,
    /// or nil if not restored from a backup.
    /// Version string may have originated from a non-iOS client.
    private var backupAppVersion: String? {
        return userDefaults.string(forKey: backupAppVersionKey)
    }

    /// The version of the app that was first launched, of the app instance that generated the backup
    /// this app instance restored from, or nil if not restored from a backup.
    /// Version string may have originated from a non-iOS client.
    public var firstBackupAppVersion: String? {
        return userDefaults.string(forKey: firstBackupAppVersionKey)
    }

    /// The version of the app the last time it was launched. `nil` if the app
    /// hasn't been launched.
    public var lastAppVersion: String? { userDefaults.string(forKey: lastVersionKey) }

    /// Internally, we use a version format with 4 dotted values to uniquely
    /// identify builds. The first three values are the the release version, the
    /// fourth value is the last value from the build version.
    ///
    /// For example, `3.4.5.6`.
    public let currentAppVersion: String

    public let prettyAppVersion: String

    public var lastCompletedLaunchAppVersion: String? {
        return userDefaults.string(forKey: lastCompletedLaunchVersionKey)
    }
    public private(set) var lastCompletedLaunchMainAppVersion: String? {
        get { userDefaults.string(forKey: lastCompletedMainAppLaunchVersionKey) }
        set {
            let didChange = lastCompletedLaunchMainAppVersion != newValue
            userDefaults.setOrRemove(newValue, forKey: lastCompletedLaunchVersionKey)
            userDefaults.setOrRemove(newValue, forKey: lastCompletedMainAppLaunchVersionKey)
            if didChange { userDefaults.set(Date(), forKey: firstMainAppLaunchDateAfterUpdateKey) }
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
    public var firstMainAppLaunchDateAfterUpdate: Date? {
        return userDefaults.object(forKey: firstMainAppLaunchDateAfterUpdateKey) as? Date
    }

    public let buildDate: Date

    // MARK: - Setup

    private init(bundle: Bundle, userDefaults: UserDefaults) {
        let marketingVersion = bundle.string(forInfoDictionaryKey: "CFBundleShortVersionString")
        var marketingVersionComponents = marketingVersion.components(separatedBy: ".")
        while marketingVersionComponents.count < 3 {
            marketingVersionComponents.append("0")
        }
        let buildNumber = bundle.string(forInfoDictionaryKey: "CFBundleVersion")
        self.currentAppVersion = "\(marketingVersionComponents.joined(separator: ".")).\(buildNumber)"
        self.prettyAppVersion = "\(marketingVersion) (\(buildNumber))"

        if
            let rawBuildDetails = bundle.app.object(forInfoDictionaryKey: "BuildDetails"),
            let buildDetails = rawBuildDetails as? [String: Any],
            let buildTimestamp = buildDetails["Timestamp"] as? TimeInterval {
            self.buildDate = Date(timeIntervalSince1970: buildTimestamp)
        } else {
            #if !TESTABLE_BUILD
            Logger.warn("Expected a build date to be defined. Assuming build date is right now")
            #endif
            self.buildDate = Date()
        }

        self.userDefaults = userDefaults
    }

    private func save() {
        if userDefaults.string(forKey: firstVersionKey) == nil {
            userDefaults.set(currentAppVersion, forKey: firstVersionKey)
        }
        userDefaults.set(currentAppVersion, forKey: lastVersionKey)
    }

    private func startupLogging() {
        Logger.info("firstAppVersion: \(formatForLogging(firstAppVersion))")
        if let backupAppVersion {
            Logger.info("backupAppVersion: \(formatForLogging(backupAppVersion))")
        }
        if let firstBackupAppVersion {
            Logger.info("firstBackupAppVersion: \(formatForLogging(firstBackupAppVersion))")
        }
        Logger.info("lastAppVersion: \(formatForLogging(lastAppVersion))")
        Logger.info("currentAppVersion: \(formatForLogging(currentAppVersion))")
        Logger.info("lastCompletedLaunchAppVersion: \(formatForLogging(lastCompletedLaunchAppVersion))")
        Logger.info("lastCompletedLaunchMainAppVersion: \(formatForLogging(lastCompletedLaunchMainAppVersion))")
        Logger.info("lastCompletedLaunchSAEAppVersion: \(formatForLogging(lastCompletedLaunchSAEAppVersion))")
        Logger.info("lastCompletedLaunchNSEAppVersion: \(formatForLogging(lastCompletedLaunchNSEAppVersion))")

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
    }

    // MARK: - Events

    public func mainAppLaunchDidComplete() {
        Logger.info("")
        lastCompletedLaunchMainAppVersion = currentAppVersion
    }

    public func saeLaunchDidComplete() {
        Logger.info("")
        lastCompletedLaunchSAEAppVersion = currentAppVersion
    }

    public func nseLaunchDidComplete() {
        Logger.info("")
        lastCompletedLaunchNSEAppVersion = currentAppVersion
    }

    public func didRestoreFromBackup(
        backupCurrentAppVersion: String?,
        backupFirstAppVersion: String?
    ) {
        if let backupCurrentAppVersion {
            userDefaults.set(backupCurrentAppVersion, forKey: backupAppVersionKey)
        }
        if let backupFirstAppVersion {
            userDefaults.set(backupFirstAppVersion, forKey: firstBackupAppVersionKey)
        }
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
    public var currentAppVersion: String { appVersion.currentAppVersion }

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

    public var firstBackupAppVersion: String?

    public var lastAppVersion: String? = "1.0"

    public var currentAppVersion: String = "1.0.0.0"

    public var prettyAppVersion: String = "1.0 (0)"

    public var lastCompletedLaunchAppVersion: String?

    public var lastCompletedLaunchMainAppVersion: String?

    public var lastCompletedLaunchSAEAppVersion: String?

    public var lastCompletedLaunchNSEAppVersion: String?

    public var firstMainAppLaunchDateAfterUpdate: Date?

    public var buildDate: Date = Date()

    public func mainAppLaunchDidComplete() {}

    public func saeLaunchDidComplete() {}

    public func nseLaunchDidComplete() {}

    public func didRestoreFromBackup(
        backupCurrentAppVersion: String?,
        backupFirstAppVersion: String?
    ) {}
}

#endif
