//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AppExpiry: NSObject {

    @objc
    public static let appExpiredStatusCode: UInt = 499

    private let keyValueStore: KeyValueStore
    private let schedulers: Schedulers

    private struct ExpirationState: Codable, Equatable {
        let version4: String

        enum Mode: String, Codable {
            case `default`
            case immediately
            case atDate
        }
        let mode: Mode

        let expirationDate: Date?

        init(mode: Mode = .default, expirationDate: Date? = nil) {
            self.version4 = AppVersion.shared.currentAppVersion4
            self.mode = mode
            self.expirationDate = expirationDate

            // It'd be great to enforce this with an associated object
            // on the enum, but Codable conformance with associated
            // objects is a very manual process.
            owsAssertDebug(mode != .atDate || expirationDate != nil)
        }
    }
    private let expirationState = AtomicValue<ExpirationState>(.init(mode: .default))

    static let keyValueCollection = "AppExpiry"
    static let keyValueKey = "expirationState"

    public required init(
        keyValueStoreFactory: KeyValueStoreFactory,
        schedulers: Schedulers
    ) {
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: Self.keyValueCollection)
        self.schedulers = schedulers

        super.init()

        SwiftSingletons.register(self)
    }

    private func logExpirationState() {
        if isExpired {
            Logger.info("Build is expired.")
        } else {
            let oneDayInSeconds: TimeInterval = 86400
            let daysUntilExpiry = Int(floor(expirationDate.timeIntervalSinceNow / oneDayInSeconds))
            Logger.info("Build expires in \(daysUntilExpiry) day(s)")
        }
    }

    public func warmCaches(with tx: DBReadTransaction) {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        let persistedExpirationState: ExpirationState? = try? self.keyValueStore.getCodableValue(
            forKey: Self.keyValueKey,
            transaction: tx
        )

        // We only want to restore the persisted state if it's for our current version.
        guard
            let persistedExpirationState,
            persistedExpirationState.version4 == AppVersion.shared.currentAppVersion4
        else {
            return
        }

        expirationState.set(persistedExpirationState)

        logExpirationState()
    }

    private func updateExpirationState(_ state: ExpirationState, db: DB) {
        expirationState.set(state)

        logExpirationState()

        db.asyncWrite { transaction in
            do {
                // Don't write or fire notification if the value hasn't changed.
                let oldState: ExpirationState? = try self.keyValueStore.getCodableValue(
                    forKey: Self.keyValueKey,
                    transaction: transaction
                )
                if let oldState, oldState == state {
                    return
                }
            } catch {
                owsFailDebug("Error reading expiration state \(error)")
            }
            do {
                try self.keyValueStore.setCodable(
                    state,
                    key: Self.keyValueKey,
                    transaction: transaction
                )
            } catch {
                owsFailDebug("Error persisting expiration state \(error)")
            }

            transaction.addAsyncCompletion(on: self.schedulers.global()) {
                NotificationCenter.default.postNotificationNameAsync(
                    Self.AppExpiryDidChange,
                    object: nil
                )
            }
        }
    }

    public func setHasAppExpiredAtCurrentVersion(db: DB) {
        Logger.warn("")

        updateExpirationState(ExpirationState(mode: .immediately), db: db)
    }

    public func setExpirationDateForCurrentVersion(_ newExpirationDate: Date?, db: DB) {
        guard !isExpired else {
            return owsFailDebug("Ignoring expiration date change for expired build.")
        }

        Logger.warn("\(String(describing: newExpirationDate))")

        let newState: ExpirationState
        if let newExpirationDate = newExpirationDate {
            // Ignore any expiration date that is later than when the app expires by default.
            guard newExpirationDate < AppVersion.shared.defaultExpirationDate else { return }
            newState = .init(mode: .atDate, expirationDate: newExpirationDate)
        } else {
            newState = .init(mode: .default)
        }
        updateExpirationState(newState, db: db)
    }

    @objc
    public static let AppExpiryDidChange = Notification.Name("AppExpiryDidChange")

    public var expirationDate: Date {
        let state = expirationState.get()
        switch state.mode {
        case .default:
            return AppVersion.shared.defaultExpirationDate
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
    public var isExpired: Bool {
        return expirationDate < Date()
    }
}

// MARK: - Build time

fileprivate extension AppVersion {
    var defaultExpirationDate: Date { buildDate.addingTimeInterval(90 * kDayInterval) }
}
