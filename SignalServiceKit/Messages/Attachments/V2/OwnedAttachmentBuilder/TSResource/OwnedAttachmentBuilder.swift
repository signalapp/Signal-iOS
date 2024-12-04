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
public final class OwnedAttachmentBuilder<InfoType> {

    // MARK: - API

    /// Immediately available before inserting the owner (and in fact is often needed for owner creation).
    public let info: InfoType

    /// Finalize the ownership, actually creating any attachments.
    /// Must be called after the owner has been inserted into the database,
    /// within the same write transaction.
    public func finalize(
        owner: AttachmentReference.OwnerBuilder,
        tx: DBWriteTransaction
    ) throws {
        if self.hasBeenFinalized {
            owsFailDebug("Should only finalize once!")
            return
        }
        try finalizeFn(owner, tx)
        hasBeenFinalized = true
    }

    // MARK: - Init

    public init(
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
        _ owner: AttachmentReference.OwnerBuilder,
        _ tx: DBWriteTransaction
    ) throws -> Void

    // MARK: - Private

    fileprivate let finalizeFn: FinalizeFn
    fileprivate var hasBeenFinalized: Bool = false
    fileprivate weak var wrappee: AnyOwnedAttachmentBuilder?

    deinit {
        if !hasBeenFinalized {
            owsFailDebug("Did not finalize attachments!")
        }
    }
}

extension OwnedAttachmentBuilder {

    public func wrap<T>(_ mapFn: (InfoType) -> T) -> OwnedAttachmentBuilder<T> {
        let wrapped = OwnedAttachmentBuilder<T>(
            info: mapFn(self.info),
            finalize: { [self] owner, tx in
                try self.finalize(owner: owner, tx: tx)
            }
        )
        wrapped.wrappee = self
        return wrapped
    }

    /// Normally, OwnedAttachmentBuilders must be finalized exactly once.
    /// However, in multisend we want to send to multiple destinations which are all identical
    /// in their InfoType, use the same source Attachment, and only differ in the owner passed to the finalize method.
    /// In those cases they are allowed to "finalize" the same object multiple times, but we enforce that
    /// it must be finalized exactly once per destination, no more no less.
    public func forMultisendReuse(numDestinations: Int) -> [OwnedAttachmentBuilder<InfoType>] {
        var finalizedCount = 0
        var duplicates = [OwnedAttachmentBuilder<InfoType>]()
        for _ in 0..<numDestinations {
            duplicates.append(OwnedAttachmentBuilder<InfoType>(
                info: self.info,
                finalize: { [self] owner, tx in
                    try self.finalize(owner: owner, tx: tx)
                    finalizedCount += 1
                    if finalizedCount < numDestinations {
                        // Reset the "finalized" state until we hit all destinations.
                        var builder: AnyOwnedAttachmentBuilder? = self
                        while builder != nil {
                            builder?.hasBeenFinalized = false
                            builder = builder?.wrappee
                        }
                        self.hasBeenFinalized = false
                    }
                }
            ))
        }
        return duplicates
    }
}

extension OwnedAttachmentBuilder where InfoType == Void {

    public convenience init(
        finalize: @escaping FinalizeFn
    ) {
        self.init(info: (), finalize: finalize)
    }

    public static func withoutFinalizer() -> Self {
        return Self.init(info: (), finalize: { _, _ in })
    }
}

private protocol AnyOwnedAttachmentBuilder: AnyObject {
    var hasBeenFinalized: Bool { get set }
    var wrappee: AnyOwnedAttachmentBuilder? { get }
}
extension OwnedAttachmentBuilder: AnyOwnedAttachmentBuilder {}
