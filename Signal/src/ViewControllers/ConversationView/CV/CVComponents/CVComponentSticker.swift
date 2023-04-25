//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class CVComponentSticker: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .sticker }

    private let sticker: CVComponentState.Sticker
    private var stickerMetadata: StickerMetadata? {
        sticker.stickerMetadata
    }
    private var attachmentStream: TSAttachmentStream? {
        sticker.attachmentStream
    }
    private var attachmentPointer: TSAttachmentPointer? {
        sticker.attachmentPointer
    }
    private var stickerInfo: StickerInfo? {
        stickerMetadata?.stickerInfo
    }

    init(itemModel: CVItemModel, sticker: CVComponentState.Sticker) {
        self.sticker = sticker

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewSticker()
    }

    public static let stickerSize: CGFloat = 175

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewSticker else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let stackView = componentView.stackView

        if let attachmentStream = self.attachmentStream {
            let cacheKey = attachmentStream.uniqueId
            let isAnimated = attachmentStream.shouldBeRenderedByYY
            let reusableMediaView: ReusableMediaView
            if let cachedView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
                reusableMediaView = cachedView
            } else {
                let mediaViewAdapter = MediaViewAdapterSticker(attachmentStream: attachmentStream)
                reusableMediaView = ReusableMediaView(mediaViewAdapter: mediaViewAdapter, mediaCache: mediaCache)
                mediaCache.setMediaView(reusableMediaView, forKey: cacheKey, isAnimated: isAnimated)
            }

            reusableMediaView.owner = componentView
            componentView.reusableMediaView = reusableMediaView
            let mediaView = reusableMediaView.mediaView

            stackView.reset()
            stackView.configure(config: stackViewConfig,
                                cellMeasurement: cellMeasurement,
                                measurementKey: Self.measurementKey_stackView,
                                subviews: [ mediaView ])

            switch CVAttachmentProgressView.progressType(forAttachment: attachmentStream,
                                                         interaction: interaction) {
            case .none:
                break
            case .uploading:
                let progressView = CVAttachmentProgressView(direction: .upload(attachmentStream: attachmentStream),
                                                            isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
                                                            mediaCache: mediaCache)
                stackView.addSubview(progressView)
                stackView.centerSubviewOnSuperview(progressView, size: progressView.layoutSize)
            case .pendingDownload:
                break
            case .downloading:
                break
            case .restoring:
                // TODO: We could easily show progress for restores.
                owsFailDebug("Restoring progress type.")
            case .unknown:
                owsFailDebug("Unknown progress type.")
            }
        } else if let attachmentPointer = self.attachmentPointer {
            let placeholderView = UIView()
            placeholderView.backgroundColor = Theme.secondaryBackgroundColor
            placeholderView.layer.cornerRadius = 18

            stackView.reset()
            stackView.configure(config: stackViewConfig,
                                cellMeasurement: cellMeasurement,
                                measurementKey: Self.measurementKey_stackView,
                                subviews: [ placeholderView ])

            let progressView = CVAttachmentProgressView(direction: .download(attachmentPointer: attachmentPointer),
                                                        isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
                                                        mediaCache: mediaCache)
            stackView.addSubview(progressView)
            stackView.centerSubviewOnSuperview(progressView, size: progressView.layoutSize)
        } else {
            owsFailDebug("Invalid attachment.")
            return
        }
    }

    private var stackViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: isOutgoing ? .trailing : .leading,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private static let measurementKey_stackView = "CVComponentSticker.measurementKey_stackView"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let size: CGFloat = ceil(min(maxWidth, Self.stickerSize))
        let stickerSize = CGSize.square(size)
        let stickerInfo = stickerSize.asManualSubviewInfo(hasFixedSize: true)
        let stackMeasurement = ManualStackView.measure(config: stackViewConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_stackView,
                                                       subviewInfos: [ stickerInfo ],
                                                       maxWidth: maxWidth)
        return stackMeasurement.measuredSize
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let stickerMetadata = stickerMetadata,
              attachmentStream != nil else {
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
                if let reusableMediaView = reusableMediaView,
                   reusableMediaView.owner == self {
                    reusableMediaView.load()
                }
            } else {
                if let reusableMediaView = reusableMediaView,
                   reusableMediaView.owner == self {
                    reusableMediaView.unload()
                }
            }
        }

        public func reset() {
            stackView.reset()

            if let reusableMediaView = reusableMediaView,
               reusableMediaView.owner == self {
                reusableMediaView.unload()
                reusableMediaView.owner = nil
            }
        }

    }
}

// MARK: -

extension CVComponentSticker: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        // NOTE: We could include the strings used for sticker suggestion.
        OWSLocalizedString("ACCESSIBILITY_LABEL_STICKER",
                          comment: "Accessibility label for stickers.")
    }
}
