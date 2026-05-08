//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class CVComponentSticker: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .sticker }

    private let sticker: CVComponentState.Sticker
    private var stickerMetadata: (any StickerMetadata)? {
        sticker.stickerMetadata
    }

    private var attachmentStream: ReferencedAttachmentStream? {
        sticker.attachmentStream
    }

    private var attachmentPointer: ReferencedAttachmentPointer? {
        sticker.attachmentPointer
    }

    init(itemModel: CVItemModel, sticker: CVComponentState.Sticker) {
        self.sticker = sticker

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewSticker()
    }

    public static let stickerSize: CGFloat = 175
    private static let progressViewSize = CGSize.square(44)

    public func configureForRendering(
        componentView componentViewParam: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {
        guard let componentView = componentViewParam as? CVComponentViewSticker else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let stackView = componentView.stackView

        switch sticker {
        case .available(_, let attachmentStream, let isUploading, let imageMetadata):
            let cacheKey = CVMediaCache.CacheKey.attachment(attachmentStream.attachment.id)
            let isAnimated = imageMetadata.isAnimated
            let reusableMediaView: ReusableMediaView
            if let cachedView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
                reusableMediaView = cachedView
            } else {
                let mediaViewAdapter = MediaViewAdapterSticker(
                    attachmentStream: attachmentStream.attachmentStream,
                    isAnimated: isAnimated,
                )
                reusableMediaView = ReusableMediaView(mediaViewAdapter: mediaViewAdapter, mediaCache: mediaCache)
                mediaCache.setMediaView(reusableMediaView, forKey: cacheKey, isAnimated: isAnimated)
            }

            reusableMediaView.owner = componentView
            componentView.reusableMediaView = reusableMediaView
            let mediaView = reusableMediaView.mediaView

            stackView.reset()
            stackView.configure(
                config: stackViewConfig,
                cellMeasurement: cellMeasurement,
                measurementKey: Self.measurementKey_stackView,
                subviews: [mediaView],
            )

            switch CVAttachmentProgressView.progressType(cvAttachment: .stream(
                attachmentStream,
                isUploading: isUploading,
                imageMetadata: imageMetadata,
            )) {
            case .none:
                break
            case .uploading:
                let progressView = CVAttachmentProgressView(
                    direction: .upload(attachmentStream: attachmentStream.attachmentStream),
                    configuration: .forMediaOverlay(),
                )
                stackView.addSubview(progressView)
                stackView.centerSubviewOnSuperview(progressView, size: Self.progressViewSize)
            case .skipped:
                break
            case .downloading:
                break
            }
        case .invalidImage(attachmentId: _):
            configureForRenderingInvalidImage(
                stackView: stackView,
                cellMeasurement: cellMeasurement,
            )
        case .downloading(let attachmentPointer):
            configureForRenderingDownload(
                downloadState: .enqueuedOrDownloading,
                attachmentPointer: attachmentPointer,
                stackView: stackView,
                cellMeasurement: cellMeasurement,
            )
        case .skipped(let attachmentPointer, let downloadState):
            configureForRenderingDownload(
                downloadState: downloadState,
                attachmentPointer: attachmentPointer,
                stackView: stackView,
                cellMeasurement: cellMeasurement,
            )
        }
    }

    private func configureForRenderingInvalidImage(
        stackView: ManualStackView,
        cellMeasurement: CVCellMeasurement,
    ) {
        let placeholderView = UIView()
        placeholderView.backgroundColor = Theme.washColor
        placeholderView.layer.cornerRadius = 18

        stackView.reset()
        stackView.configure(
            config: stackViewConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_stackView,
            subviews: [placeholderView],
        )
    }

    private func configureForRenderingDownload(
        downloadState: AttachmentDownloadState,
        attachmentPointer: ReferencedAttachmentPointer,
        stackView: ManualStackView,
        cellMeasurement: CVCellMeasurement,
    ) {
        let placeholderView = UIView()
        placeholderView.backgroundColor = Theme.washColor
        placeholderView.layer.cornerRadius = 18

        stackView.reset()
        stackView.configure(
            config: stackViewConfig,
            cellMeasurement: cellMeasurement,
            measurementKey: Self.measurementKey_stackView,
            subviews: [placeholderView],
        )

        let progressView = CVAttachmentProgressView(
            direction: .download(
                attachmentPointer: attachmentPointer.attachmentPointer,
                downloadState: downloadState,
            ),
            configuration: .forMediaOverlay(),
        )
        stackView.addSubview(progressView)
        stackView.centerSubviewOnSuperview(progressView, size: Self.progressViewSize)
    }

    private var stackViewConfig: CVStackViewConfig {
        CVStackViewConfig(
            axis: .vertical,
            alignment: isOutgoing ? .trailing : .leading,
            spacing: 0,
            layoutMargins: .zero,
        )
    }

    private static let measurementKey_stackView = "CVComponentSticker.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let size: CGFloat = ceil(min(maxWidth, Self.stickerSize))
        let stickerSize = CGSize.square(size)
        let stickerInfo = stickerSize.asManualSubviewInfo(hasFixedSize: true)
        let stackMeasurement = ManualStackView.measure(
            config: stackViewConfig,
            measurementBuilder: measurementBuilder,
            measurementKey: Self.measurementKey_stackView,
            subviewInfos: [stickerInfo],
            maxWidth: maxWidth,
        )
        return stackMeasurement.measuredSize
    }

    // MARK: - Events

    override public func handleTap(
        sender: UIGestureRecognizer,
        componentDelegate: CVComponentDelegate,
        componentView: CVComponentView,
        renderItem: CVRenderItem,
    ) -> Bool {

        guard
            let stickerMetadata,
            attachmentStream != nil
        else {
            // Not yet downloaded.
            return false
        }
        componentDelegate.didTapStickerPack(stickerMetadata.packInfo)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewSticker: NSObject, CVComponentView {

        fileprivate let stackView = ManualStackView(name: "sticker.container")

        fileprivate var reusableMediaView: ReusableMediaView?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {
            if isCellVisible {
                if
                    let reusableMediaView,
                    reusableMediaView.owner == self
                {
                    reusableMediaView.load()
                }
            } else {
                if
                    let reusableMediaView,
                    reusableMediaView.owner == self
                {
                    reusableMediaView.unload()
                }
            }
        }

        public func reset() {
            stackView.reset()

            if
                let reusableMediaView,
                reusableMediaView.owner == self
            {
                reusableMediaView.unload()
            }
        }

    }
}

// MARK: -

extension CVComponentSticker: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        if let approximateEmoji = stickerMetadata?.firstEmoji {
            return String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "ACCESSIBILITY_LABEL_STICKER_FORMAT",
                    comment: "Accessibility label for stickers. Embeds {{ name of top emoji the sticker resembles }}",
                ),
                approximateEmoji,
            )
        } else {
            return OWSLocalizedString(
                "ACCESSIBILITY_LABEL_STICKER",
                comment: "Accessibility label for stickers.",
            )
        }
    }
}
