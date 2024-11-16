//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - AppExpiry protocol

public protocol AppExpiry {
    var expirationDate: Date { get }
    var isExpired: Bool { get }

    func warmCaches(with: DBReadTransaction)
    func setHasAppExpiredAtCurrentVersion(db: any DB)
    func setExpirationDateForCurrentVersion(_ newExpirationDate: Date?, db: any DB)
}

// MARK: - AppExpiry implementation

public class AppExpiryImpl: AppExpiry {

    @objc
    public static let appExpiredStatusCode: UInt = 499

    private let keyValueStore: KeyValueStore
    private let dateProvider: DateProvider
    private let appVersion: AppVersion
    private let schedulers: Schedulers

    private struct ExpirationState: Codable, Equatable {
        let appVersion: String

        enum Mode: String, Codable {
            case `default`
            case immediately
            case atDate
        }
        let mode: Mode

        let expirationDate: Date?

        init(appVersion: String, mode: Mode = .default, expirationDate: Date? = nil) {
            self.appVersion = appVersion
            self.mode = mode
            self.expirationDate = expirationDate

            // It'd be great to enforce this with an associated object
            // on the enum, but Codable conformance with associated
            // objects is a very manual process.
            owsAssertDebug(mode != .atDate || expirationDate != nil)
        }
    }
    private let expirationState: AtomicValue<ExpirationState>

    static let keyValueCollection = "AppExpiry"
    static let keyValueKey = "expirationState"

    public init(
        dateProvider: @escaping DateProvider,
        appVersion: AppVersion,
        schedulers: Schedulers
    ) {
        self.keyValueStore = KeyValueStore(collection: Self.keyValueCollection)
        self.dateProvider = dateProvider
        self.appVersion = appVersion
        self.schedulers = schedulers

        self.expirationState = AtomicValue(
            .init(appVersion: appVersion.currentAppVersion, mode: .default),
            lock: .sharedGlobal
        )
    }

    public func warmCaches(with tx: DBReadTransaction) {
        let persistedExpirationState: ExpirationState? = try? self.keyValueStore.getCodableValue(
            forKey: Self.keyValueKey,
            transaction: tx
        )

        // We only want to restore the persisted state if it's for our current version.
        guard
            let persistedExpirationState,
            persistedExpirationState.appVersion == appVersion.currentAppVersion
        else {
            return
        }

        expirationState.set(persistedExpirationState)
    }

    private func updateExpirationState(_ state: ExpirationState, db: any DB) {
        expirationState.set(state)

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

    public func setHasAppExpiredAtCurrentVersion(db: any DB) {
        Logger.warn("")

        let newState = ExpirationState(appVersion: appVersion.currentAppVersion, mode: .immediately)
        updateExpirationState(newState, db: db)
    }

    public func setExpirationDateForCurrentVersion(_ newExpirationDate: Date?, db: any DB) {
        guard !isExpired else {
            owsFailDebug("Ignoring expiration date change for expired build.")
            return
        }

        let newState: ExpirationState
        if let newExpirationDate {
            Logger.warn("Considering remote expiration of \(newExpirationDate)")
            // Ignore any expiration date that is later than when the app expires by default.
            guard newExpirationDate < AppVersionImpl.shared.defaultExpirationDate else { return }
            newState = .init(
                appVersion: appVersion.currentAppVersion,
                mode: .atDate,
                expirationDate: newExpirationDate
            )
        } else {
            newState = .init(appVersion: appVersion.currentAppVersion, mode: .default)
        }
        updateExpirationState(newState, db: db)
    }

    @objc
    public static let AppExpiryDidChange = Notification.Name("AppExpiryDidChange")

    public var expirationDate: Date {
        let state = expirationState.get()
        switch state.mode {
        case .default:
            return appVersion.defaultExpirationDate
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
    public var isExpired: Bool { expirationDate < dateProvider() }
}

// MARK: - Build time

fileprivate extension AppVersion {
    var defaultExpirationDate: Date { buildDate.addingTimeInterval(90 * kDayInterval) }
}

// MARK: - Objective-C interop

@objc(AppExpiry)
public class AppExpiryForObjC: NSObject {
    private let appExpiry: AppExpiry

    @objc
    public static let shared = AppExpiryForObjC(DependenciesBridge.shared.appExpiry)

    public init(_ appExpiry: AppExpiry) {
        self.appExpiry = appExpiry
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public var isExpired: Bool { appExpiry.isExpired }
}
