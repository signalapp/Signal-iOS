//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Thrown when a request isn't sent because the app is already expired.
public struct AppExpiredError: Error, IsRetryableProvider {
    public let isRetryableProvider: Bool = false
}

public final class AppExpiry {

    public static let appExpiredStatusCode: UInt = 499

    private let keyValueStore: KeyValueStore

    private let appVersion: AppVersionNumber4
    private let buildDate: Date

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

    public convenience init(appVersion: any AppVersion) {
        self.init(appVersion: appVersion.currentAppVersion4, buildDate: appVersion.buildDate)
    }

#if TESTABLE_BUILD

    public static func forUnitTests(buildDate: Date = Date()) -> Self {
        return Self(appVersion: try! AppVersionNumber4(AppVersionNumber("1.2.3.4")), buildDate: buildDate)
    }

#endif

    public init(
        appVersion: AppVersionNumber4,
        buildDate: Date,
    ) {
        self.keyValueStore = KeyValueStore(collection: Self.keyValueCollection)
        self.appVersion = appVersion
        self.buildDate = buildDate

        self.expirationState = AtomicValue(
            .init(appVersion: appVersion.wrappedValue.rawValue, mode: .default),
            lock: .sharedGlobal,
        )
    }

    public func warmCaches(with tx: DBReadTransaction) {
        let persistedExpirationState: ExpirationState? = try? self.keyValueStore.getCodableValue(
            forKey: Self.keyValueKey,
            failDebugOnParseError: false,
            transaction: tx,
        )

        // We only want to restore the persisted state if it's for our current version.
        guard
            let persistedExpirationState,
            persistedExpirationState.appVersion == appVersion.wrappedValue.rawValue
        else {
            return
        }

        expirationState.set(persistedExpirationState)
    }

    private func updateExpirationState(_ state: ExpirationState, db: any DB) async {
        expirationState.set(state)

        await db.awaitableWrite { transaction in
            do {
                // Don't write or fire notification if the value hasn't changed.
                let oldState: ExpirationState? = try self.keyValueStore.getCodableValue(
                    forKey: Self.keyValueKey,
                    transaction: transaction,
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
                    transaction: transaction,
                )
            } catch {
                owsFailDebug("Error persisting expiration state \(error)")
            }
        }

        await didUpdateExpirationState()
    }

    @MainActor
    private func didUpdateExpirationState() {
        _refreshExpirationTimerIfStarted()
        NotificationCenter.default.post(name: Self.AppExpiryDidChange, object: nil)
    }

    public func setHasAppExpiredAtCurrentVersion(db: any DB) async {
        Logger.warn("")

        let newState = ExpirationState(appVersion: appVersion.wrappedValue.rawValue, mode: .immediately)
        await updateExpirationState(newState, db: db)
    }

    public func setExpirationDateForCurrentVersion(_ newExpirationDate: Date?, now: Date, db: any DB) async {
        guard !isExpired(now: now) else {
            Logger.warn("Ignoring expiration date change for expired build.")
            return
        }

        let newState: ExpirationState
        if let newExpirationDate {
            Logger.warn("Considering remote expiration of \(newExpirationDate)")
            // Ignore any expiration date that is later than when the app expires by default.
            guard newExpirationDate < defaultExpirationDate else { return }
            newState = .init(
                appVersion: appVersion.wrappedValue.rawValue,
                mode: .atDate,
                expirationDate: newExpirationDate,
            )
        } else {
            newState = .init(appVersion: appVersion.wrappedValue.rawValue, mode: .default)
        }
        await updateExpirationState(newState, db: db)
    }

    public static let AppExpiryDidChange = Notification.Name("AppExpiryDidChange")

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

    public func isExpired(now: Date) -> Bool { expirationDate < now }

    public static let defaultExpirationInterval: TimeInterval = 90 * .day

    private var defaultExpirationDate: Date {
        return buildDate.addingTimeInterval(Self.defaultExpirationInterval)
    }

    @MainActor
    private var expirationWorkItem: DispatchWorkItem?

    @MainActor
    private func _refreshExpirationTimerIfStarted() {
        if self.expirationWorkItem != nil {
            self.refreshExpirationTimer()
        }
    }

    @MainActor
    public func refreshExpirationTimer() {
        let now = Date()
        let expirationDate = self.expirationDate

        self.expirationWorkItem?.cancel()
        self.expirationWorkItem = nil

        guard now < expirationDate else {
            return
        }

        let expirationDelay = self.expirationDate.timeIntervalSince(now)
        let wallDeadline: DispatchWallTime = .now() + expirationDelay

        // This is a DispatchWorkItem so that we can use the wall clock.
        let expirationWorkItem = DispatchWorkItem(block: { [weak self] in
            NotificationCenter.default.post(name: Self.AppExpiryDidChange, object: nil)
            self?.refreshExpirationTimer()
        })
        self.expirationWorkItem = expirationWorkItem
        DispatchQueue.main.asyncAfter(wallDeadline: wallDeadline, execute: expirationWorkItem)
    }
}
