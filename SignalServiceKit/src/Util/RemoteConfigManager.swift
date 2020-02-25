//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public class RemoteConfig: NSObject {

    init(_ config: [String: Bool]) {
        self.config = config
    }

    // rather than interact with `config` directly, prefer encoding any string constants
    // into a getter below...
    private let config: [String: Bool]

    @objc
    public static var pinsForEveryone: Bool {
        // If we've turned off the KBS feature we don't want to present the
        // pins for everyone migration even if this user is in the bucket.
        guard kbs else { return false }
        return isEnabled(.pinsForEveryone)
    }

    @objc
    public static var mandatoryPins: Bool {
        guard pinsForEveryone else { return false }
        return isEnabled(.mandatoryPins)
    }

    @objc
    public static var profileNameReminder: Bool {
        return isEnabled(.profileNameReminder)
    }

    @objc
    public static var messageRequests: Bool {
        return isEnabled(.messageRequests)
    }

    @objc
    public static var kbs: Bool {
        // This feature latches "on" – once they have a master key in KBS,
        // even if we turn it off on the server they will keep using KBS.
        guard !KeyBackupService.hasMasterKey else { return true }
        return isEnabled(.kbs)
    }

    @objc
    public static var storageService: Bool { isEnabled(.storageService) }

    private static func isEnabled(_ flag: Flags.Supported, defaultValue: Bool = false) -> Bool {
        guard let remoteConfig = SSKEnvironment.shared.remoteConfigManager.cachedConfig else {
            return defaultValue
        }
        return remoteConfig.config[flag.rawFlag] ?? defaultValue
    }
}

private struct Flags {
    static let prefix = "ios."

    // Values defined in this array remain forever true once they are
    // marked true regardless of the remote state.
    enum Sticky: String, FlagType {
        case pinsForEveryone
    }

    // We filter the received config down to just the supported flags.
    // This ensures if we have a sticky flag it doesn't get inadvertently
    // set because we cached a value before it went public. e.g. if we set
    // a sticky flag to 100% in beta then turn it back to 0% before going
    // to production.
    enum Supported: String, FlagType {
        case pinsForEveryone
        case kbs
        case profileNameReminder
        case mandatoryPins
        case messageRequests
        case storageService
    }
}

private protocol FlagType: CaseIterable {
    var rawValue: String { get }
    var rawFlag: String { get }
    static var allRawFlags: [String] { get }
}

private extension FlagType {
    var rawFlag: String { Flags.prefix + rawValue }
    static var allRawFlags: [String] { allCases.map { $0.rawFlag } }
}

@objc
public protocol RemoteConfigManager: AnyObject {
    var cachedConfig: RemoteConfig? { get }
}

@objc
public class StubbableRemoteConfigManager: NSObject, RemoteConfigManager {
    public var cachedConfig: RemoteConfig?
}

@objc
public class ServiceRemoteConfigManager: NSObject, RemoteConfigManager {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var grdbStorage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    private var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    private let serviceClient: SignalServiceClient = SignalServiceRestClient()

    let keyValueStore: SDSKeyValueStore = SDSKeyValueStore(collection: "RemoteConfigManager")

    // MARK: -

    @objc
    public private(set) var cachedConfig: RemoteConfig?

    @objc
    public override init() {
        super.init()

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.cacheCurrent()
        }

        // The fetched config won't take effect until the *next* launch.
        // That's not ideal, but we can't risk changing configs in the middle
        // of an app lifetime.
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            guard self.tsAccountManager.isRegistered else {
                return
            }
            self.refreshIfReady()
        }

        // Listen for registration state changes so we can fetch the config
        // when the user registers. This will still not take effect until
        // the *next* launch, but we'll have it ready to apply at that point.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .RegistrationStateDidChange,
            object: nil
        )
    }

    // MARK: -

    @objc func registrationStateDidChange() {
        guard self.tsAccountManager.isRegistered else { return }
        self.refreshIfReady()
    }

    private func cacheCurrent() {
        AssertIsOnMainThread()

        // set only once
        assert(self.cachedConfig == nil)

        if let storedConfig = self.databaseStorage.read(block: { transaction in
            self.keyValueStore.getRemoteConfig(transaction: transaction)
        }) {
            Logger.info("loaded stored config: \(storedConfig)")
            self.cachedConfig = RemoteConfig(storedConfig)
            do {
                try ensureMessageRequestInteractionIdEpochState()
            } catch {
                owsFailDebug("error: \(error)")
            }
        } else {
            Logger.info("no stored remote config")
        }
    }

    func ensureMessageRequestInteractionIdEpochState() throws {
        guard cachedConfig != nil else {
            owsFailDebug("cachedConfig was unexpectedly nil")
            return
        }

        let hasEpoch = try grdbStorage.read { SSKPreferences.messageRequestInteractionIdEpoch(transaction: $0) } != nil

        if RemoteConfig.messageRequests {
            guard hasEpoch else {
                try grdbStorage.write { transaction in
                    let maxId = GRDBInteractionFinder.maxRowId(transaction: transaction)
                    SSKPreferences.setMessageRequestInteractionIdEpoch(maxId, transaction: transaction)
                }
                return
            }
        } else {
            guard !hasEpoch else {
                // Possible the flag was toggled on and then back off. We want to clear the recorded
                // epoch so it can be reset the *next* time the flag is toggled back on.
                try grdbStorage.write {
                    SSKPreferences.setMessageRequestInteractionIdEpoch(nil, transaction: $0)
                }
                return
            }
        }
    }

    private func refreshIfReady() {
        guard let lastFetched = (databaseStorage.read { transaction in
            self.keyValueStore.getLastFetched(transaction: transaction)
        }) else {
            refresh()
            return
        }

        if abs(lastFetched.timeIntervalSinceNow) > 2 * kHourInterval {
            refresh()
        } else {
            Logger.info("skipping due to recent fetch.")
        }
    }

    private func refresh() {
        return firstly {
            self.serviceClient.getRemoteConfig()
        }.done(on: .global()) { fetchedConfig in
            var configToStore = fetchedConfig.filter { Flags.Supported.allRawFlags.contains($0.key) }
            self.databaseStorage.write { transaction in
                // Update fetched config to reflect any sticky flags.
                if let existingConfig = self.keyValueStore.getRemoteConfig(transaction: transaction) {
                    existingConfig.lazy.filter { Flags.Sticky.allRawFlags.contains($0.key) }.forEach {
                        configToStore[$0.key] = $0.value || (fetchedConfig[$0.key] ?? false)
                    }
                }

                self.keyValueStore.setRemoteConfig(configToStore, transaction: transaction)
                self.keyValueStore.setLastFetched(Date(), transaction: transaction)
            }
            Logger.info("stored new remoteConfig: \(configToStore)")
        }.catch { error in
            Logger.error("error: \(error)")
        }.retainUntilComplete()
    }
}

private extension SDSKeyValueStore {

    // MARK: - Remote Config

    var remoteConfigKey: String { "remoteConfigKey" }

    func getRemoteConfig(transaction: SDSAnyReadTransaction) -> [String: Bool]? {
        guard let object = getObject(remoteConfigKey, transaction: transaction) else {
            return nil
        }

        guard let remoteConfig = object as? [String: Bool] else {
            owsFailDebug("unexpected object: \(object)")
            return nil
        }

        return remoteConfig
    }

    func setRemoteConfig(_ newValue: [String: Bool], transaction: SDSAnyWriteTransaction) {
        return setObject(newValue, key: remoteConfigKey, transaction: transaction)
    }

    // MARK: - Last Fetched

    var lastFetchedKey: String { "lastFetchedKey" }

    func getLastFetched(transaction: SDSAnyReadTransaction) -> Date? {
        return getDate(lastFetchedKey, transaction: transaction)
    }

    func setLastFetched(_ newValue: Date, transaction: SDSAnyWriteTransaction) {
        return setDate(newValue, key: lastFetchedKey, transaction: transaction)
    }
}
