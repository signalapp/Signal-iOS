//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AppVersion {
    @objc
    public static let shared: AppVersion = {
        let result = AppVersion()
        result.configure()
        return result
    }()

    // MARK: - Properties

    public static var hardwareInfoString: String {
        let marketingString = UIDevice.current.model
        let machineString = String(sysctlKey: "hw.machine") ?? "nil"
        let modelString = String(sysctlKey: "hw.model") ?? "nil"
        return "\(marketingString) (\(machineString); \(modelString))"
    }

    public static var iosVersionString: String {
        let majorMinor = UIDevice.current.systemVersion
        let buildNumber = String(sysctlKey: "kern.osversion") ?? "nil"
        return "\(majorMinor) (\(buildNumber))"
    }

    // MARK: - Startup logging

    @objc
    func startupLogging() {
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

        let userDefaults = CurrentAppContext().appUserDefaults()
        let databaseCorruptionState = DatabaseCorruptionState(userDefaults: userDefaults)
        Logger.info("Database corruption state: \(databaseCorruptionState)")

        Logger.info("iOS Version: \(Self.iosVersionString)")

        let locale = Locale.current
        Logger.info("Locale Identifier: \(locale.identifier)")
        if let countryCode = (locale as NSLocale).countryCode {
            Logger.info("Country Code: \(countryCode)")
        }
        if let languageCode = locale.languageCode {
            Logger.info("Language Code: \(languageCode)")
        }

        Logger.info("Device Model: \(Self.hardwareInfoString)")

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

    // MARK: - Comparing app versions

    /// Compares the two given version strings. Parses each string as a dot-separated list of
    /// components, and does a pairwise comparison of each string's corresponding components. If any
    /// component is not interpretable as an unsigned integer, the value `0` will be used.
    @objc(compareAppVersion:with:)
    public static func compare(_ lhs: String, with rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.components(separatedBy: ".")
        let rhsComponents = rhs.components(separatedBy: ".")

        let largestCount = max(lhsComponents.count, rhsComponents.count)
        for index in (0..<largestCount) {
            let lhsComponent = parseVersionComponent(lhsComponents[index])
            let rhsComponent = parseVersionComponent(rhsComponents[index])
            if lhsComponent != rhsComponent {
                return (lhsComponent < rhsComponent) ? .orderedAscending : .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func parseVersionComponent(_ versionComponent: String?) -> UInt {
        guard let versionComponent else { return 0 }
        return UInt(versionComponent) ?? 0
    }
}
