//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// These extensions allow callers to use RecipientHidingManager
/// via SignalServiceAddress, temporarily, while we still have
/// callsites using SignalServiceAddress.
/// The actual root identifier used by RecipientHidingManager is
/// SignalRecipient (well, its row id), and all these methods just do
/// a lookup of SignalRecipient by address.
/// Eventually, all callsites should be explicit about the recipient
/// identifier they have (whether a SignalRecipient or some as
/// yet undefined combo of {ACI} or {e164 + PNI}.
/// At that point, this extension should be deleted.
extension RecipientHidingManager {

    // MARK: Read
    /// Returns set of ``SignalServiceAddress``es corresponding with
    /// all hidden recipients.
    ///
    /// - Parameter tx: The transaction to use for database operations.
    public func hiddenAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress> {
        return Set(hiddenRecipients(tx: tx).compactMap { (recipient: SignalRecipient) -> SignalServiceAddress? in
            let address = recipient.address
            guard address.isValid else { return nil }
            return address
        })
    }

    /// Whether a service address corresponds with a hidden recipient.
    ///
    /// - Parameter address: The service address corresponding with
    ///   the ``SignalRecipient``.
    /// - Parameter tx: The transaction to use for database operations.
    ///
    /// - Returns: True if the address is hidden.
    public func isHiddenAddress(_ address: SignalServiceAddress, tx: DBReadTransaction) -> Bool {
        guard
            let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress,
            !localAddress.isEqualToAddress(address) else
        {
            return false
        }
        guard let recipient = recipient(from: address, tx: tx) else {
            return false
        }
        return isHiddenRecipient(recipient, tx: tx)
    }

    // MARK: Write
    /// Adds a recipient to the hidden recipient table.
    ///
    /// - Parameter address: The service address corresponding with
    ///   the ``SignalRecipient``.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    public func addHiddenRecipient(_ address: SignalServiceAddress, wasLocallyInitiated: Bool, tx: DBWriteTransaction) throws {
        guard address.isValid else {
            throw RecipientHidingError.invalidRecipientAddress(address)
        }
        guard
            let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress,
            !localAddress.isEqualToAddress(address)
        else {
            throw RecipientHidingError.cannotHideLocalAddress
        }
        let recipient = OWSAccountIdFinder.ensureRecipient(
            forAddress: address,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        try addHiddenRecipient(recipient, wasLocallyInitiated: wasLocallyInitiated, tx: tx)
    }

    /// Removes a recipient from the hidden recipient table.
    ///
    /// - Parameter address: The service address corresponding with
    ///   the ``SignalRecipient``.
    /// - Parameter wasLocallyInitiated: Whether the user initiated
    ///   the hide on this device (true) or a linked device (false).
    /// - Parameter tx: The transaction to use for database operations.
    public func removeHiddenRecipient(_ address: SignalServiceAddress, wasLocallyInitiated: Bool, tx: DBWriteTransaction) {
        guard
            let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)?.aciAddress,
            !localAddress.isEqualToAddress(address)
        else {
            owsFailDebug("Cannot unhide the local address")
            return
        }
        if let recipient = recipient(from: address, tx: tx) {
            removeHiddenRecipient(recipient, wasLocallyInitiated: wasLocallyInitiated, tx: tx)
        }
    }

    /// Returns the id for a recipient, if the recipient exists.
    ///
    /// - Parameter address: The service address corresponding with
    ///   the ``SignalRecipient``.
    /// - Parameter tx: The transaction to use for database operations.
    ///
    /// - Returns: The ``SignalRecipient``.
    private func recipient(from address: SignalServiceAddress, tx: DBReadTransaction) -> SignalRecipient? {
        return SignalRecipient.fetchRecipient(for: address, onlyIfRegistered: false, tx: SDSDB.shimOnlyBridge(tx))
    }
}
