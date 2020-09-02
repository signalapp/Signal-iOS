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
            // We don't need to re-warm this cache after a device migration.
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
            return expiredAtVersion == AppVersion.sharedInstance().currentAppVersionLong
        }
        hasAppExpiredAtCurrentVersion.set(value)
    }

    @objc
    public func setHasAppExpiredAtCurrentVersion() {
        Logger.warn("")

        hasAppExpiredAtCurrentVersion.set(true)

        databaseStorage.asyncWrite { transaction in
            self.keyValueStore.setString(AppVersion.sharedInstance().currentAppVersionLong,
                                         key: Self.expiredAtVersionKey,
                                         transaction: transaction)

            transaction.addAsyncCompletion {
                NotificationCenter.default.postNotificationNameAsync(Self.AppExpiryDidChange,
                                                                     object: nil)
            }
        }
    }

    @objc
    public static let AppExpiryDidChange = Notification.Name("AppExpiryDidChange")

    @objc
    public class var shared: AppExpiry {
        SSKEnvironment.shared.appExpiry
    }

    @objc
    public static var daysUntilBuildExpiry: Int {
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
        return daysUntilBuildExpiry <= 10
    }

    @objc
    public static var isExpired: Bool {
        shared.isExpired
    }

    @objc
    public var isExpired: Bool {
        guard !hasAppExpiredAtCurrentVersion.get() else { return true }
        return Self.daysUntilBuildExpiry <= 0
    }
}
