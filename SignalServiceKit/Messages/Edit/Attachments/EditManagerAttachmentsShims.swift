//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension EditManagerAttachmentsImpl {
    public enum Shims {
        public typealias TSMessageStore = _EditManagerAttachmentsImpl_TSMessageStoreShim
    }

    public enum Wrappers {
        public typealias TSMessageStore = _EditManagerAttachmentsImpl_TSMessageStoreWrapper
    }
}

// MARK: - EditManager.TSMessageStore

public protocol _EditManagerAttachmentsImpl_TSMessageStoreShim {

    func update(
        _ message: TSMessage,
        with quotedReply: TSQuotedMessage,
        tx: DBWriteTransaction
    )

    func update(
        _ message: TSMessage,
        with linkPreview: OWSLinkPreview,
        tx: DBWriteTransaction
    )
}

public class _EditManagerAttachmentsImpl_TSMessageStoreWrapper: EditManagerAttachmentsImpl.Shims.TSMessageStore {

    public init() {}

    public func update(
        _ message: TSMessage,
        with quotedReply: TSQuotedMessage,
        tx: DBWriteTransaction
    ) {
        message.update(with: quotedReply, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func update(
        _ message: TSMessage,
        with linkPreview: OWSLinkPreview,
        tx: DBWriteTransaction
    ) {
        message.update(with: linkPreview, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
