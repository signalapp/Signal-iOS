//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Represents an "inactive" linked device.
/// - SeeAlso ``InactiveLinkedDeviceFinder``
public struct InactiveLinkedDevice: Equatable {
    public let displayName: String
    public let expirationDate: Date

    init(displayName: String, expirationDate: Date) {
        self.displayName = displayName
        self.expirationDate = expirationDate
    }
}

/// Responsible for finding "inactive" linked devices, or those who have not
/// come online in a long time and are at risk of expiring (and being unlinked)
/// soon.
public protocol InactiveLinkedDeviceFinder {
    /// At most once per day, re-fetch our linked device state.
    ///
    /// - Note
    /// This method does nothing if invoked from a linked device.
    func refreshLinkedDeviceStateIfNecessary() async

    /// Find the user's "least active" linked device, i.e. their linked device
    /// that was last seen longest ago.
    ///
    /// - Note
    /// A linked device's expiration time (when it is unlinked) is a function of
    /// its "last seen" time. Consequently, the least-active linked device
    /// returned by this method will also be the next-expiring device.
    ///
    /// - Note
    /// This method returns `nil` if the current device is a linked device.
    func findLeastActiveLinkedDevice(tx: DBReadTransaction) -> InactiveLinkedDevice?

    /// Permanently disables this and any future inactive linked device finders.
    ///
    /// - Important
    /// This is irreversible for the life of this app install. Use with care.
    func permanentlyDisableFinders(tx: DBWriteTransaction)

    #if TESTABLE_BUILD
    func reenablePermanentlyDisabledFinders(tx: DBWriteTransaction)
    #endif
}

public extension InactiveLinkedDeviceFinder {
    /// Whether the user has an "inactive" linked device.
    func hasInactiveLinkedDevice(tx: DBReadTransaction) -> Bool {
        return findLeastActiveLinkedDevice(tx: tx) != nil
    }
}

class InactiveLinkedDeviceFinderImpl: InactiveLinkedDeviceFinder {
    private enum Constants {
        /// How long we should wait between device state refreshes.
        static let intervalForDeviceRefresh: TimeInterval = kDayInterval

        /// How long before a device expires it is considered "inactive".
        static let intervalBeforeExpirationConsideredInactive = kWeekInterval
    }

    private enum StoreKeys {
        static let lastRefreshedDate: String = "lastRefreshedDate"
        static let isPermanentlyDisabled: String = "isPermanentlyDisabled"
    }

    private let dateProvider: DateProvider
    private let db: any DB
    private let deviceNameDecrypter: Shims.OWSDeviceNameDecrypter
    private let deviceService: OWSDeviceService
    private let deviceStore: OWSDeviceStore
    private let kvStore: KeyValueStore
    private let remoteConfigProvider: any RemoteConfigProvider
    private let tsAccountManager: TSAccountManager

    private var intervalForDeviceExpiration: TimeInterval {
        return remoteConfigProvider.currentConfig().messageQueueTime
    }

    private var intervalForDeviceInactivity: TimeInterval {
        return max(0, remoteConfigProvider.currentConfig().messageQueueTime - Constants.intervalBeforeExpirationConsideredInactive)
    }

    private let logger = PrefixedLogger(prefix: "InactiveLinkedDeviceFinder")

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        deviceNameDecrypter: Shims.OWSDeviceNameDecrypter,
        deviceService: OWSDeviceService,
        deviceStore: OWSDeviceStore,
        remoteConfigProvider: any RemoteConfigProvider,
        tsAccountManager: TSAccountManager
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.deviceNameDecrypter = deviceNameDecrypter
        self.deviceService = deviceService
        self.deviceStore = deviceStore
        self.kvStore = KeyValueStore(collection: "InactiveLinkedDeviceFinderImpl")
        self.remoteConfigProvider = remoteConfigProvider
        self.tsAccountManager = tsAccountManager
    }

    func refreshLinkedDeviceStateIfNecessary() async {
        struct SkipRefreshError: Error {}

        let shouldSkip = db.read { tx -> Bool in
            if kvStore.hasValue(StoreKeys.isPermanentlyDisabled, transaction: tx) {
                // Finder is permanently disabled, no need to refresh.
                return true
            }

            if !tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice {
                // Only refresh state on primaries.
                return true
            }

            if
                let lastRefreshedDate = kvStore.getDate(StoreKeys.lastRefreshedDate, transaction: tx),
                lastRefreshedDate.addingTimeInterval(Constants.intervalForDeviceRefresh) > dateProvider()
            {
                // Checked less than a day ago, skip.
                return true
            }

            return false
        }

        if shouldSkip {
            return
        }

        do {
            _ = try await deviceService.refreshDevices()

            await db.awaitableWrite { tx in
                self.kvStore.setDate(
                    self.dateProvider(),
                    key: StoreKeys.lastRefreshedDate,
                    transaction: tx
                )
            }
        } catch {
            logger.warn("Failed to refresh devices!")
        }
    }

    func findLeastActiveLinkedDevice(tx: DBReadTransaction) -> InactiveLinkedDevice? {
        if !kvStore.hasValue(StoreKeys.lastRefreshedDate, transaction: tx) {
            /// Short-circuit if we've never refreshed device state. Otherwise,
            /// we'll be querying stale data from who knows when.
            return nil
        }

        if kvStore.hasValue(StoreKeys.isPermanentlyDisabled, transaction: tx) {
            // Short-circuit if we've been disabled.
            return nil
        }

        if !tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice {
            // Only report linked devices if we are a primary.
            return nil
        }

        let allInactiveLinkedDevices = deviceStore.fetchAll(tx: tx)
            .filter { !$0.isPrimaryDevice }
            .filter { device in
                // Only keep devices whose inactivity date has passed.
                let inactivityDate = device.lastSeenAt.addingTimeInterval(intervalForDeviceInactivity)
                return inactivityDate < dateProvider()
            }

        return allInactiveLinkedDevices
            .min { lhs, rhs in
                return lhs.lastSeenAt < rhs.lastSeenAt
            }
            .map { device -> InactiveLinkedDevice in
                return InactiveLinkedDevice(
                    displayName: deviceNameDecrypter.decryptName(
                        device: device, tx: tx
                    ),
                    expirationDate: device.lastSeenAt.addingTimeInterval(
                        intervalForDeviceExpiration
                    )
                )
            }
    }

    func permanentlyDisableFinders(tx: DBWriteTransaction) {
        kvStore.setBool(true, key: StoreKeys.isPermanentlyDisabled, transaction: tx)
    }

    #if TESTABLE_BUILD
    func reenablePermanentlyDisabledFinders(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.isPermanentlyDisabled, transaction: tx)
    }
    #endif
}

// MARK: - Shims

extension InactiveLinkedDeviceFinderImpl {
    enum Shims {
        typealias OWSDeviceNameDecrypter = InactiveLinkedDeviceFinderImpl_OWSDeviceNameDecrypter_Shim
    }

    enum Wrappers {
        typealias OWSDeviceNameDecrypter = InactiveLinkedDeviceFinderImpl_OWSDeviceNameDecrypter_Wrapper
    }
}

// MARK: OWSDeviceNameDecrypter

protocol InactiveLinkedDeviceFinderImpl_OWSDeviceNameDecrypter_Shim {
    func decryptName(device: OWSDevice, tx: DBReadTransaction) -> String
}

class InactiveLinkedDeviceFinderImpl_OWSDeviceNameDecrypter_Wrapper: InactiveLinkedDeviceFinderImpl_OWSDeviceNameDecrypter_Shim {
    private let identityManager: OWSIdentityManager

    init(identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    func decryptName(device: OWSDevice, tx: DBReadTransaction) -> String {
        return device.displayName(
            identityManager: identityManager, tx: tx
        )
    }
}
