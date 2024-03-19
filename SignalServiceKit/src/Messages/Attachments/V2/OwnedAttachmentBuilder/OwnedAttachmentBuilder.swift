//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wraps the two "modes" of creating attachments: legacy and v2.
///
/// Legacy attachments must be created before their owning messages; their IDs
/// get added to the owning message and therefore must be created first.
/// V2 attachments must be created after their owning messages; we establish
/// a separate relationship between owner id and attachment on AttachmentReference.
/// This class abstracts this away; you create an instance before creating the owner,
/// then "finalize" the instance after, and when the actual database writes happen
/// depends on the underlying v1/v2 implementation.
///
/// Once v1 is migrated and removed from the codebase entirely, we can also remove
/// this abstraction, though we don't strictly need to do so immediately. In a v2-only
/// world, callsites just invoke directly the things that would have been handled
/// by "finalize".
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
