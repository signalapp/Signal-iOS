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

    private struct ExpirationState: Codable {
        let version: String

        enum Mode: String, Codable {
            case `default`
            case immediately
            case atDate
        }
        let mode: Mode

        let expirationDate: Date?

        init(mode: Mode = .default, expirationDate: Date? = nil) {
            self.version = AppVersion.shared().currentAppVersionLong
            self.mode = mode
            self.expirationDate = expirationDate

            // It'd be great to enforce this with an associated object
            // on the enum, but Codable conformance with associated
            // objects is a very manual process.
            owsAssertDebug(mode != .atDate || expirationDate != nil)
        }
    }
    private let expirationState = AtomicValue<ExpirationState>(.init(mode: .default))
    private static let expirationStateKey = "expirationState"

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            // We don't need to re-warm this cache after a device migration.
            self.warmCaches()
        }
    }

    private func logExpirationState() {
        if isExpired {
            Logger.info("Build is expired.")
        } else {
            Logger.info("Build expires in \(daysUntilBuildExpiry) days")
        }
    }

    private func warmCaches() {
        if let persistedExpirationState: ExpirationState = databaseStorage.read(block: { transaction in
            guard let persistedExpirationState: ExpirationState = try? self.keyValueStore.getCodableValue(
                forKey: Self.expirationStateKey,
                transaction: transaction
            ) else {
                return nil
            }

            // We only want to restore the persisted state if it's for our current version.
            guard persistedExpirationState.version == AppVersion.shared().currentAppVersionLong else {
                return nil
            }

            return persistedExpirationState
        }) {
            expirationState.set(persistedExpirationState)
        }

        logExpirationState()
    }

    private func updateExpirationState(_ state: ExpirationState) {
        expirationState.set(state)

        logExpirationState()

        databaseStorage.asyncWrite { transaction in
            do {
                try self.keyValueStore.setCodable(
                    state,
                    key: Self.expirationStateKey,
                    transaction: transaction
                )
            } catch {
                owsFailDebug("Error persisting expiration state \(error)")
            }
            transaction.addAsyncCompletion {
                NotificationCenter.default.postNotificationNameAsync(
                    Self.AppExpiryDidChange,
                    object: nil
                )
            }
        }
    }

    @objc
    public func setHasAppExpiredAtCurrentVersion() {
        Logger.warn("")

        updateExpirationState(ExpirationState(mode: .immediately))
    }

    @objc
    public func setExpirationDateForCurrentVersion(_ newExpirationDate: Date?) {
        guard !isExpired else {
            return owsFailDebug("Ignoring expiration date change for expired build.")
        }

        Logger.warn("\(String(describing: newExpirationDate))")

        if let newExpirationDate = newExpirationDate {
            // Ignore any expiration date that is later than when the app expires by default.
            guard newExpirationDate < defaultExpirationDate else { return }

            updateExpirationState(ExpirationState(mode: .atDate, expirationDate: newExpirationDate))
        } else {
            updateExpirationState(ExpirationState(mode: .default))
        }
    }

    @objc
    public static let AppExpiryDidChange = Notification.Name("AppExpiryDidChange")

    @objc
    public class var shared: AppExpiry {
        SSKEnvironment.shared.appExpiry
    }

    // By default, we expire 90 days after the app was compiled.
    private let defaultExpirationDate = CurrentAppContext().buildTime.addingTimeInterval(90 * kDayInterval)

    public var expirationDate: Date {
        let state = expirationState.get()
        switch state.mode {
        case .default:
            return defaultExpirationDate
        case .atDate:
            guard let expirationDate = state.expirationDate else {
                owsFailDebug("Missing expiration date, expiring immediately")
                return .distantPast
            }
            return expirationDate
        case .immediately:
            return .distantPast
        }
    }

    @objc
    public var daysUntilBuildExpiry: Int {
        guard let daysUntilExpiry = Calendar.current.dateComponents(
            [.day],
            from: Date(),
            to: expirationDate
        ).day else {
            owsFailDebug("Unexpectedly found nil daysUntilExpiry, this should not be possible.")
            return 0
        }
        return daysUntilExpiry
    }

    @objc
    public var isExpiringSoon: Bool {
        return daysUntilBuildExpiry <= 10
    }

    @objc
    public var isExpired: Bool {
        return expirationDate < Date()
    }
}
