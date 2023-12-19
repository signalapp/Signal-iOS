//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public enum MessageBackup {}

extension MessageBackup {
    public enum Shims {
        public typealias BlockingManager = _MessageBackup_BlockingManagerShim
        public typealias ProfileManager = _MessageBackup_ProfileManagerShim
    }

    public enum Wrappers {
        public typealias BlockingManager = _MessageBackup_BlockingManagerWrapper
        public typealias ProfileManager = _MessageBackup_ProfileManagerWrapper
    }
}

// MARK: - BlockingManager

public protocol _MessageBackup_BlockingManagerShim {

    func blockedAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress>

    func addBlockedAddress(_ address: SignalServiceAddress, tx: DBWriteTransaction)
}

public class _MessageBackup_BlockingManagerWrapper: _MessageBackup_BlockingManagerShim {

    private let blockingManager: BlockingManager

    public init(_ blockingManager: BlockingManager) {
        self.blockingManager = blockingManager
    }

    public func blockedAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress> {
        return blockingManager.blockedAddresses(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func addBlockedAddress(_ address: SignalServiceAddress, tx: DBWriteTransaction) {
        blockingManager.addBlockedAddress(address, blockMode: .localShouldNotLeaveGroups, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - ProfileManager

public protocol _MessageBackup_ProfileManagerShim {

    func getUserProfile(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile?

    func allWhitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress]

    func isThread(inProfileWhitelist thread: TSThread, tx: DBReadTransaction) -> Bool

    func addToWhitelist(_ address: SignalServiceAddress, tx: DBWriteTransaction)

    func addToWhitelist(_ thread: TSGroupThread, tx: DBWriteTransaction)

    func setProfileGivenName(
        givenName: String?,
        familyName: String?,
        profileKey: Data?,
        address: SignalServiceAddress,
        tx: DBWriteTransaction
    )
}

public class _MessageBackup_ProfileManagerWrapper: _MessageBackup_ProfileManagerShim {

    private let profileManager: ProfileManagerProtocol

    public init(_ profileManager: ProfileManagerProtocol) {
        self.profileManager = profileManager
    }

    public func getUserProfile(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile? {
        profileManager.getUserProfile(for: address, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func allWhitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        profileManager.allWhitelistedRegisteredAddresses(tx: SDSDB.shimOnlyBridge(tx))
    }

    public func isThread(inProfileWhitelist thread: TSThread, tx: DBReadTransaction) -> Bool {
        profileManager.isThread(inProfileWhitelist: thread, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func addToWhitelist(_ address: SignalServiceAddress, tx: DBWriteTransaction) {
        profileManager.addUser(
            toProfileWhitelist: address,
            userProfileWriter: .storageService, /* TODO */
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func addToWhitelist(_ thread: TSGroupThread, tx: DBWriteTransaction) {
        profileManager.addThread(toProfileWhitelist: thread, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func setProfileGivenName(
        givenName: String?,
        familyName: String?,
        profileKey: Data?,
        address: SignalServiceAddress,
        tx: DBWriteTransaction
    ) {
        profileManager.setProfileGivenName(
            givenName,
            familyName: familyName,
            for: address,
            userProfileWriter: .storageService /* TODO */,
            authedAccount: .implicit(),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        if let profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: address,
                userProfileWriter: .storageService, /* TODO */
                authedAccount: .implicit(),
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        }
    }
}
