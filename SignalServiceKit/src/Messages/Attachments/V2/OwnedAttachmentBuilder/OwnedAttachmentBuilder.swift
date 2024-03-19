//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OwnedAttachmentBuilder<InfoType> {

    // MARK: - API

    /// Immediately available before inserting the owner (and in fact is often needed for owner creation).
    public let info: InfoType

    /// Finalize the ownership, actually creating any attachments.
    /// Must be called after the owner has been inserted into the database,
    /// within the same write transaction.
    public func finalize(
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) {
        if self.hasBeenFinalized {
            owsFailDebug("Should only finalize once!")
            return
        }
        finalizeFn(owner, tx)
        hasBeenFinalized = true
    }

    // MARK: - Init

    public required init(
        info: InfoType,
        finalize: @escaping FinalizeFn
    ) {
        self.info = info
        self.finalizeFn = finalize
    }

    public static func withoutFinalizer(_ info: InfoType) -> Self {
        return Self.init(info: info, finalize: { _, _ in })
    }

    public typealias FinalizeFn = (
        _ owner: AttachmentReference.OwnerId,
        _ tx: DBWriteTransaction
    ) -> Void

    // MARK: - Private

    fileprivate let finalizeFn: FinalizeFn
    private var hasBeenFinalized: Bool = false

    deinit {
        if !hasBeenFinalized {
            owsFailDebug("Did not finalize attachments!")
        }
    }
}

extension OwnedAttachmentBuilder {

    func wrap<T>(_ mapFn: (InfoType) -> T) -> OwnedAttachmentBuilder<T> {
        return OwnedAttachmentBuilder<T>(
            info: mapFn(self.info),
            finalize: { [self] owner, tx in
                self.finalize(owner: owner, tx: tx)
            }
        )
    }
}
