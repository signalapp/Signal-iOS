//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public class AppExpiry: NSObject {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    @objc
    public static let appExpiredStatusCode: UInt = 499

    @objc
    public let keyValueStore = SDSKeyValueStore(collection: "AppExpiry")

    private let hasAppExpiredAtCurrentVersion = AtomicBool(false)
    private static let expiredAtVersionKey = "expiredAtVersionKey"

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.warmCaches()
        }
    }

    private func warmCaches() {
        let value = databaseStorage.read { transaction -> Bool in
            guard let expiredAtVersion = self.keyValueStore.getString(Self.expiredAtVersionKey,
                                                                      transaction: transaction) else {
                                                                        return false
            }
            // "Expired at version"
            return expiredAtVersion == AppVersion.sharedInstance().currentAppVersion
        }
        hasAppExpiredAtCurrentVersion.set(value)
    }

    @objc
    public func setHasAppExpiredAtCurrentVersion() {
        hasAppExpiredAtCurrentVersion.set(true)

        databaseStorage.asyncWrite { transaction in
            self.keyValueStore.setString(AppVersion.sharedInstance().currentAppVersion,
                                         key: Self.expiredAtVersionKey,
                                         transaction: transaction)
        }
    }

    @objc
    public class var shared: AppExpiry {
        SSKEnvironment.shared.appExpiry
    }

    @objc
    public static var daysUntilBuildExpiry: Int {
        shared.daysUntilBuildExpiry
    }

    @objc
    public var daysUntilBuildExpiry: Int {
        guard let buildAge = Calendar.current.dateComponents(
            [.day],
            from: CurrentAppContext().buildTime,
            to: Date()
        ).day else {
            owsFailDebug("Unexpectedly found nil buildAge, this should not be possible.")
            return 0
        }
        return 90 - buildAge
    }

    @objc
    public static var isExpiringSoon: Bool {
        shared.isExpiringSoon
    }

    @objc
    public var isExpiringSoon: Bool {
        guard !isEndOfLifeOSVersion else { return false }
        return daysUntilBuildExpiry <= 10
    }

    @objc
    public static var isExpired: Bool {
        shared.isExpired
    }

    @objc
    public var isExpired: Bool {
        guard !isEndOfLifeOSVersion else { return true }
        guard !hasAppExpiredAtCurrentVersion.get() else { return true }
        return daysUntilBuildExpiry <= 0
    }

    @objc
    public static var isEndOfLifeOSVersion: Bool {
        shared.isEndOfLifeOSVersion
    }

    /// Indicates if this iOS version is no longer supported. If so,
    /// we don't ever expire the build as newer builds will not be
    /// installable on their device and show a special banner
    /// that indicates we will no longer support their device.
    ///
    /// Currently, only iOS 11 and greater are officially supported.
    @objc
    public var isEndOfLifeOSVersion: Bool {
        if #available(iOS 11, *) {
            return false
        } else {
            return true
        }
    }
}
