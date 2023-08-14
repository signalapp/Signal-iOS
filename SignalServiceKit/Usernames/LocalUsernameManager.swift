//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

/// Manages the local username and username link.
public protocol LocalUsernameManager {

    // MARK: Local state

    /// Returns the state of the local username.
    func usernameState(tx: DBReadTransaction) -> Usernames.LocalUsernameState

    /// Sets the local username and username link.
    func setLocalUsername(
        username: String,
        usernameLink: Usernames.UsernameLink,
        tx: DBWriteTransaction
    )

    /// Sets the local username, and marks that the local username link is
    /// corrupted.
    ///
    /// Corruption indicates that the username link values we have locally may
    /// or do not decrypt the encrypted username stored by the service. This may
    /// occur due to an interrupted "update my username link" request, race
    /// between two devices simultaneously updating our username, and possibly
    /// other reasons.
    func setLocalUsernameWithCorruptedLink(
        username: String,
        tx: DBWriteTransaction
    )

    /// Sets that the local username and username link are corrupted.
    ///
    /// Corruption indicates that the username value we have locally may or does
    /// not match the hash of our username stored by the service. This may occur
    /// due to an interrupted "update my username" request, race between two
    /// devices simultaneously updating our username, and possibly other
    /// reasons.
    func setLocalUsernameCorrupted(tx: DBWriteTransaction)

    /// Clears the local username and username link, whether they were corrupted
    /// or not.
    func clearLocalUsername(tx: DBWriteTransaction)

    /// Returns the color to be used for the local user's username link QR code.
    func usernameLinkQRCodeColor(tx: DBReadTransaction) -> Usernames.QRCodeColor

    /// Sets the color to be used for the local user's username link QR code.
    func setUsernameLinkQRCodeColor(
        color: Usernames.QRCodeColor,
        tx: DBWriteTransaction
    )

    // MARK: Usernames and the service

    /// Reserve a username from the given set of candidates.
    func reserveUsername(
        usernameCandidates: Usernames.HashedUsername.GeneratedCandidates
    ) -> Promise<Usernames.ReservationResult>

    /// Set the local user's username to the given reserved username, on the
    /// service and locally. Note that setting a new username also sets a
    /// corresponding username link.
    func confirmUsername(
        reservedUsername: Usernames.HashedUsername,
        tx: DBWriteTransaction
    ) -> Promise<Usernames.ConfirmationResult>

    /// Delete the local user's username and username link.
    func deleteUsername(tx: DBWriteTransaction) -> Promise<Void>

    // MARK: Username links and the service

    /// Rotate the local user's username link, without modifying their username.
    func rotateUsernameLink(tx: DBWriteTransaction) -> Promise<Usernames.UsernameLink>
}

public extension Usernames {
    static let localUsernameStateChangedNotification = NSNotification.Name(
        "localUsernameStateChanged"
    )

    /// Represents the states that the local user's username and username link
    /// can be in.
    enum LocalUsernameState: Equatable {
        /// The user deliberately has no username nor username link.
        case unset
        /// The user has both a username and username link.
        case available(username: String, usernameLink: UsernameLink)
        /// The user has a username, but something is wrong with the
        /// corresponding username link and it cannot be used.
        case linkCorrupted(username: String)
        /// The user has a username, but something is wrong with it and neither
        /// it nor the corresponding username link can be used.
        case usernameAndLinkCorrupted

        /// Whether the user explicitly does not have a username set.
        public var isExplicitlyUnset: Bool {
            switch self {
            case .unset:
                return true
            case .available, .linkCorrupted, .usernameAndLinkCorrupted:
                return false
            }
        }

        /// The username, if there is one available.
        public var username: String? {
            switch self {
            case let .available(username, _):
                return username
            case let .linkCorrupted(username):
                return username
            case .unset, .usernameAndLinkCorrupted:
                return nil
            }
        }

        /// The username link, if there is one available.
        public var usernameLink: Usernames.UsernameLink? {
            switch self {
            case let .available(_, usernameLink):
                return usernameLink
            case .unset, .linkCorrupted, .usernameAndLinkCorrupted:
                return nil
            }
        }
    }

    typealias ReservationResult = ApiClientReservationResult

    enum ConfirmationResult: Equatable {
        case success(
            username: String,
            usernameLink: UsernameLink
        )
        case rejected
        case rateLimited
    }
}

// MARK: - Impl

class LocalUsernameManagerImpl: LocalUsernameManager {
    private struct CorruptionStore {
        private enum Constants {
            static let collection = "LocalUsernameCorruption"
            static let usernameKey = "username"
            static let usernameLinkKey = "link"
        }

        private let kvStore: KeyValueStore

        init(kvStoreFactory: KeyValueStoreFactory) {
            kvStore = kvStoreFactory.keyValueStore(collection: Constants.collection)
        }

        func isUsernameCorrupted(tx: DBReadTransaction) -> Bool {
            return kvStore.getBool(Constants.usernameKey, defaultValue: false, transaction: tx)
        }

        func isUsernameLinkCorrupted(tx: DBReadTransaction) -> Bool {
            return kvStore.getBool(Constants.usernameLinkKey, defaultValue: false, transaction: tx)
        }

        func setUsernameCorrupted(_ value: Bool, tx: DBWriteTransaction) {
            kvStore.setBool(value, key: Constants.usernameKey, transaction: tx)
        }

        func setUsernameLinkCorrupted(_ value: Bool, tx: DBWriteTransaction) {
            kvStore.setBool(value, key: Constants.usernameLinkKey, transaction: tx)
        }
    }

    private struct UsernameStore {
        private enum Constants {
            static let collection = "LocalUsername"
            static let usernameKey = "username"
            static let usernameLinkHandleKey = "linkHandle"
            static let usernameLinkEntropyKey = "linkEntropy"
            static let usernameLinkQRCodeColorKey = "linkColor"
        }

        private let kvStore: KeyValueStore

        init(kvStoreFactory: KeyValueStoreFactory) {
            kvStore = kvStoreFactory.keyValueStore(collection: Constants.collection)
        }

        func username(tx: DBReadTransaction) -> String? {
            return kvStore.getString(Constants.usernameKey, transaction: tx)
        }

        func usernameLink(tx: DBReadTransaction) -> Usernames.UsernameLink? {
            if
                let linkHandleData = kvStore.getData(Constants.usernameLinkHandleKey, transaction: tx),
                let linkHandle = UUID(data: linkHandleData),
                let linkEntropy = kvStore.getData(Constants.usernameLinkEntropyKey, transaction: tx),
                let link = Usernames.UsernameLink(handle: linkHandle, entropy: linkEntropy)
            {
                return link
            }

            return nil
        }

        func usernameLinkColor(tx: DBReadTransaction) -> Usernames.QRCodeColor {
            return (try? kvStore.getCodableValue(
                forKey: Constants.usernameLinkQRCodeColorKey,
                transaction: tx
            )) ?? .unknown
        }

        func setUsername(username: String?, tx: DBWriteTransaction) {
            kvStore.setString(username, key: Constants.usernameKey, transaction: tx)
        }

        func setUsernameLink(usernameLink: Usernames.UsernameLink?, tx: DBWriteTransaction) {
            kvStore.setData(usernameLink?.handle.data, key: Constants.usernameLinkHandleKey, transaction: tx)
            kvStore.setData(usernameLink?.entropy, key: Constants.usernameLinkEntropyKey, transaction: tx)
        }

        func setUsernameLinkColor(color: Usernames.QRCodeColor, tx: DBWriteTransaction) {
            try? kvStore.setCodable(color, key: Constants.usernameLinkQRCodeColorKey, transaction: tx)
        }
    }

    private let db: DB
    private let schedulers: Schedulers
    private let storageServiceManager: StorageServiceManager
    private let usernameApiClient: UsernameApiClient
    private let usernameLinkManager: UsernameLinkManager

    private let corruptionStore: CorruptionStore
    private let usernameStore: UsernameStore

    init(
        db: DB,
        kvStoreFactory: KeyValueStoreFactory,
        schedulers: Schedulers,
        storageServiceManager: StorageServiceManager,
        usernameApiClient: UsernameApiClient,
        usernameLinkManager: UsernameLinkManager
    ) {
        self.db = db
        self.schedulers = schedulers
        self.storageServiceManager = storageServiceManager
        self.usernameApiClient = usernameApiClient
        self.usernameLinkManager = usernameLinkManager

        corruptionStore = CorruptionStore(kvStoreFactory: kvStoreFactory)
        usernameStore = UsernameStore(kvStoreFactory: kvStoreFactory)
    }

    // MARK: - Local state

    func usernameState(
        tx: DBReadTransaction
    ) -> Usernames.LocalUsernameState {
        if corruptionStore.isUsernameCorrupted(tx: tx) {
            return .usernameAndLinkCorrupted
        } else if let username = usernameStore.username(tx: tx) {
            if
                !corruptionStore.isUsernameLinkCorrupted(tx: tx),
                let usernameLink = usernameStore.usernameLink(tx: tx)
            {
                return .available(username: username, usernameLink: usernameLink)
            }

            return .linkCorrupted(username: username)
        }

        return .unset
    }

    func setLocalUsername(
        username: String,
        usernameLink: Usernames.UsernameLink,
        tx: DBWriteTransaction
    ) {
        corruptionStore.setUsernameCorrupted(false, tx: tx)
        usernameStore.setUsername(username: username, tx: tx)

        corruptionStore.setUsernameLinkCorrupted(false, tx: tx)
        usernameStore.setUsernameLink(usernameLink: usernameLink, tx: tx)

        postLocalUsernameStateChangedNotification(tx: tx)
    }

    func setLocalUsernameWithCorruptedLink(
        username: String,
        tx: DBWriteTransaction
    ) {
        corruptionStore.setUsernameCorrupted(false, tx: tx)
        usernameStore.setUsername(username: username, tx: tx)

        corruptionStore.setUsernameLinkCorrupted(true, tx: tx)

        postLocalUsernameStateChangedNotification(tx: tx)
    }

    func setLocalUsernameCorrupted(tx: DBWriteTransaction) {
        markUsernameCorrupted(true, tx: tx)
    }

    func clearLocalUsername(tx: DBWriteTransaction) {
        corruptionStore.setUsernameCorrupted(false, tx: tx)
        corruptionStore.setUsernameLinkCorrupted(false, tx: tx)

        usernameStore.setUsername(username: nil, tx: tx)
        usernameStore.setUsernameLink(usernameLink: nil, tx: tx)

        postLocalUsernameStateChangedNotification(tx: tx)
    }

    func usernameLinkQRCodeColor(
        tx: DBReadTransaction
    ) -> Usernames.QRCodeColor {
        return usernameStore.usernameLinkColor(tx: tx)
    }

    func setUsernameLinkQRCodeColor(
        color: Usernames.QRCodeColor,
        tx: DBWriteTransaction
    ) {
        usernameStore.setUsernameLinkColor(color: color, tx: tx)
    }

    private func markUsernameCorrupted(_ value: Bool, tx: DBWriteTransaction) {
        corruptionStore.setUsernameCorrupted(value, tx: tx)
        corruptionStore.setUsernameLinkCorrupted(value, tx: tx)

        postLocalUsernameStateChangedNotification(tx: tx)
    }

    private func markUsernameLinkCorrupted(_ value: Bool, tx: DBWriteTransaction) {
        corruptionStore.setUsernameLinkCorrupted(value, tx: tx)

        postLocalUsernameStateChangedNotification(tx: tx)
    }

    private func postLocalUsernameStateChangedNotification(tx: DBWriteTransaction) {
        tx.addAsyncCompletion(on: schedulers.main) {
            NotificationCenter.default.postNotificationNameAsync(
                Usernames.localUsernameStateChangedNotification,
                object: nil
            )
        }
    }

    // MARK: Usernames and the service

    func reserveUsername(
        usernameCandidates: Usernames.HashedUsername.GeneratedCandidates
    ) -> Promise<Usernames.ReservationResult> {
        return usernameApiClient.reserveUsernameCandidates(
            usernameCandidates: usernameCandidates
        )
    }

    /// Confirm the given reserved username, setting it as our username.
    func confirmUsername(
        reservedUsername: Usernames.HashedUsername,
        tx syncTx: DBWriteTransaction
    ) -> Promise<Usernames.ConfirmationResult> {
        let linkEntropy: Data
        let linkEncryptedUsername: Data
        do {
            (
                linkEntropy,
                linkEncryptedUsername
            ) = try self.usernameLinkManager.generateEncryptedUsername(
                username: reservedUsername.usernameString
            )
        } catch let error {
            return Promise(error: error)
        }

        // Mark as corrupted in case we encounter an unexpected error while
        // confirming. If that happens we can't be sure if our new username was
        // set or not, so we conservatively leave it in the corrupted state.
        // If, however, we get a response we understand (affirmative or
        // negative), we remove the corrupted flag.
        markUsernameCorrupted(true, tx: syncTx)

        return firstly(on: schedulers.global()) { () throws -> Promise<(Usernames.ApiClientConfirmationResult)> in
            return self.usernameApiClient.confirmReservedUsername(
                reservedUsername: reservedUsername,
                encryptedUsernameForLink: linkEncryptedUsername
            )
        }.map(on: schedulers.global()) { apiClientConfirmationResult -> Usernames.ConfirmationResult in
            self.db.write { tx in
                switch apiClientConfirmationResult {
                case let .success(linkHandle):
                    guard let usernameLink = Usernames.UsernameLink(
                        handle: linkHandle,
                        entropy: linkEntropy
                    ) else {
                        owsFail("This link should always be valid - we just generated the entropy ourselves!")
                    }

                    let username = reservedUsername.usernameString

                    self.setLocalUsername(
                        username: username,
                        usernameLink: usernameLink,
                        tx: tx
                    )

                    // We back up the username and link in StorageService, so
                    // trigger a backup now.
                    self.storageServiceManager.recordPendingLocalAccountUpdates()

                    return .success(
                        username: username,
                        usernameLink: usernameLink
                    )
                case .rejected:
                    self.markUsernameCorrupted(false, tx: tx)
                    return .rejected
                case .rateLimited:
                    self.markUsernameCorrupted(false, tx: tx)
                    return .rateLimited
                }
            }
        }.recover(on: schedulers.global()) { error throws -> Promise<Usernames.ConfirmationResult> in
            UsernameLogger.shared.error(
                "Error while confirming username. Username now assumed corrupted! \(error)"
            )

            throw error
        }
    }

    func deleteUsername(tx syncTx: DBWriteTransaction) -> Promise<Void> {
        // Mark as corrupted in case we encounter an unexpected error while
        // deleting. If that happens we can't be sure if our new username was
        // deleted or not, so we conservatively leave it in the corrupted state.
        // If, however, we get a response, we remove the corrupted flag.
        markUsernameCorrupted(true, tx: syncTx)

        return firstly(on: schedulers.global()) { () -> Promise<Void> in
            return self.usernameApiClient.deleteCurrentUsername()
        }.done(on: schedulers.global()) {
            self.db.write { tx in
                self.clearLocalUsername(tx: tx)
            }

            // We back up the username and link in StorageService, so
            // trigger a backup now.
            self.storageServiceManager.recordPendingLocalAccountUpdates()
        }.recover(on: schedulers.global()) { error -> Promise<Void> in
            UsernameLogger.shared.error(
                "Error while deleting username. Username now assumed corrupted! \(error)"
            )

            throw error
        }
    }

    // MARK: Username links and the service

    func rotateUsernameLink(
        tx syncTx: DBWriteTransaction
    ) -> Promise<Usernames.UsernameLink> {
        guard let currentUsername = usernameState(tx: syncTx).username else {
            return Promise(error: OWSAssertionError(
                "Tried to rotate link, but missing current username!"
            ))
        }

        let newEntropy: Data
        let newEncryptedUsername: Data
        do {
            (
                newEntropy,
                newEncryptedUsername
            ) = try self.usernameLinkManager.generateEncryptedUsername(
                username: currentUsername
            )
        } catch let error {
            return Promise(error: error)
        }

        // Mark as corrupted in case we encounter an unexpected error while
        // rotating. If that happens we can't be sure if our username link was
        // rotated or not, so we conservatively leave it in the corrupted state.
        // If, however, we get a response, we remove the corrupted flag.
        markUsernameLinkCorrupted(true, tx: syncTx)

        return firstly(on: schedulers.global()) { () -> Promise<UUID> in
            return self.usernameApiClient.setUsernameLink(
                encryptedUsername: newEncryptedUsername
            )
        }.map(on: schedulers.global()) { newHandle -> Usernames.UsernameLink in
            guard let newUsernameLink = Usernames.UsernameLink(
                handle: newHandle,
                entropy: newEntropy
            ) else {
                owsFail("This link should always be valid - we just generated the entropy ourselves!")
            }

            self.db.write { tx in
                self.setLocalUsername(
                    username: currentUsername,
                    usernameLink: newUsernameLink,
                    tx: tx
                )
            }

            // We back up the username and link in StorageService, so
            // trigger a backup now.
            self.storageServiceManager.recordPendingLocalAccountUpdates()

            return newUsernameLink
        }.recover(on: schedulers.global()) { error -> Promise<Usernames.UsernameLink> in
            UsernameLogger.shared.error(
                "Error while rotating username link. Username link now assumed corrupted! \(error)"
            )

            throw error
        }
    }
}
