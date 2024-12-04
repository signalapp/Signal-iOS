//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockLinkPreviewManager: LinkPreviewManager {

    public init() {}

    public func validateAndBuildLinkPreview(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return .withoutFinalizer(.init())
    }

    public func validateAndBuildLinkPreview<Builder: LinkPreviewBuilder>(
        from proto: SSKProtoPreview,
        dataMessage: SSKProtoDataMessage,
        builder: Builder,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return .withoutFinalizer(.init())
    }

    public func validateAndBuildStoryLinkPreview(
        from proto: SSKProtoPreview,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return .withoutFinalizer(.init())
    }

    public func buildDataSource(
        from draft: OWSLinkPreviewDraft
    ) throws -> LinkPreviewDataSource {
        return .init(
            metadata: .init(
                urlString: draft.urlString,
                title: draft.title,
                previewDescription: draft.previewDescription,
                date: draft.date
            ),
            imageDataSource: nil
        )
    }

    public func buildDataSource<Builder: LinkPreviewBuilder>(
        from draft: OWSLinkPreviewDraft,
        builder: Builder
    ) throws -> Builder.DataSource {
        return try builder.buildDataSource(draft)
    }

    public func buildLinkPreview(
        from dataSource: LinkPreviewDataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return .withoutFinalizer(.init())
    }

    public func buildLinkPreview<Builder: LinkPreviewBuilder>(
        from dataSource: Builder.DataSource,
        builder: Builder,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<OWSLinkPreview> {
        return .withoutFinalizer(.init())
    }

    public func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoPreview {
        return SSKProtoPreview.builder(url: linkPreview.urlString!).buildIgnoringErrors()!
    }

    public func buildProtoForSending(
        _ linkPreview: OWSLinkPreview,
        parentStoryMessage: StoryMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoPreview {
        return SSKProtoPreview.builder(url: linkPreview.urlString!).buildIgnoringErrors()!
    }
}

#endif
