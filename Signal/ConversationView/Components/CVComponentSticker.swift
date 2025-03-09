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

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewSticker else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let stackView = componentView.stackView

        switch sticker {
        case .available(_, let attachmentStream):
            let cacheKey = CVMediaCache.CacheKey.attachment(attachmentStream.attachment.id)
            let isAnimated = attachmentStream.attachmentStream.contentType.isAnimatedImage
            let reusableMediaView: ReusableMediaView
            if let cachedView = mediaCache.getMediaView(cacheKey, isAnimated: isAnimated) {
                reusableMediaView = cachedView
            } else {
                let mediaViewAdapter = MediaViewAdapterSticker(attachmentStream: attachmentStream.attachmentStream)
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

            switch CVAttachmentProgressView.progressType(
                forAttachment: .stream(attachmentStream),
                interaction: interaction
            ) {
            case .none:
                break
            case .uploading:
                let progressView = CVAttachmentProgressView(
                    direction: .upload(attachmentStream: attachmentStream.attachmentStream),
                    isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
                    mediaCache: mediaCache
                )
                stackView.addSubview(progressView)
                stackView.centerSubviewOnSuperview(progressView, size: progressView.layoutSize)
            case .pendingDownload:
                break
            case .downloading:
                break
            case .unknown:
                owsFailDebug("Unknown progress type.")
            }
        case .downloading(let attachmentPointer):
            configureForRendering(
                attachmentPointer: attachmentPointer,
                downloadState: .enqueuedOrDownloading,
                stackView: stackView,
                cellMeasurement: cellMeasurement
            )
        case .failedOrPending(let attachmentPointer, let downloadState):
            configureForRendering(
                attachmentPointer: attachmentPointer,
                downloadState: downloadState,
                stackView: stackView,
                cellMeasurement: cellMeasurement
            )
        }
    }

    private func configureForRendering(
        attachmentPointer: ReferencedAttachmentPointer,
        downloadState: AttachmentDownloadState,
        stackView: ManualStackView,
        cellMeasurement: CVCellMeasurement
    ) {
        let placeholderView = UIView()
        placeholderView.backgroundColor = Theme.secondaryBackgroundColor
        placeholderView.layer.cornerRadius = 18

        stackView.reset()
        stackView.configure(config: stackViewConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_stackView,
                            subviews: [ placeholderView ])

        let progressView = CVAttachmentProgressView(
            direction: .download(
                attachmentPointer: attachmentPointer.attachmentPointer,
                downloadState: downloadState
            ),
            isDarkThemeEnabled: conversationStyle.isDarkThemeEnabled,
            mediaCache: mediaCache
        )
        stackView.addSubview(progressView)
        stackView.centerSubviewOnSuperview(progressView, size: progressView.layoutSize)
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

    private func toggleStickerAnimation(_ view: CVComponentView) {
        if let stickerView = view as? CVComponentViewSticker, let rmv = stickerView.reusableMediaView, let yyView = rmv.mediaView as? CVAnimatedImageView {
            if yyView.isAnimating {
                yyView.stopAnimating()
                stickerView.togglePlayButton()
            } else {
                stickerView.togglePlayButton()
                yyView.startAnimating()
            }
        }
    }

    public override func handleTap(sender: UIGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let stickerMetadata = stickerMetadata,
              attachmentStream != nil else {
            // Not yet downloaded.
            return false
        }
        var isAnimated = false
        if let stickerComponent = componentView as? CVComponentViewSticker {
            isAnimated = stickerComponent.isAnimated
        }
        if UIAccessibility.isReduceMotionEnabled && isAnimated {
            toggleStickerAnimation(componentView)
        } else {
            componentDelegate.didTapStickerPack(stickerMetadata.packInfo)
        }
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewSticker: NSObject, CVComponentView {

        fileprivate let stackView = ManualStackView(name: "sticker.container")
        fileprivate var playButtonView: UIView? = nil

        fileprivate var reusableMediaView: ReusableMediaView?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        public var isAnimated: Bool {
            get {
                reusableMediaView?.needsPlayButton != nil && (reusableMediaView?.needsPlayButton)! || false
            }
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {
            if isCellVisible {
                if let reusableMediaView = reusableMediaView {
                    if reusableMediaView.owner == self {
                        reusableMediaView.load()
                    }
                    if reusableMediaView.needsPlayButton {
                        addPlayButton()
                    }
                }
            } else {
                if let reusableMediaView = reusableMediaView,
                   reusableMediaView.owner == self {
                    reusableMediaView.unload()
                }
            }
        }

        private func addPlayButton() {
            if playButtonView != nil {
                return
            }
            let playButtonWidth: CGFloat = 44
            let playIconWidth: CGFloat = 20

            let playButton = UIView.transparentContainer()
            playButtonView = playButton
            stackView.addSubviewToCenterOnSuperview(playButton, size: CGSize(square: playButtonWidth))

            let playCircleView = OWSLayerView.circleView()
            playCircleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.7)
            playCircleView.isUserInteractionEnabled = false
            playButton.addSubview(playCircleView)
            stackView.layoutSubviewToFillSuperviewEdges(playCircleView)

            let playIconView = CVImageView()
            playIconView.setTemplateImageName("play-fill-32", tintColor: UIColor.ows_white)
            playIconView.isUserInteractionEnabled = false
            stackView.addSubviewToCenterOnSuperview(playIconView,
                                                    size: CGSize(square: playIconWidth))
        }

        fileprivate func togglePlayButton() {
            if let playButton = playButtonView {
                playButton.isHidden = !playButton.isHidden
            }
        }

        public func reset() {
            stackView.reset()

            if let reusableMediaView = reusableMediaView,
               reusableMediaView.owner == self {
                reusableMediaView.unload()
            }
        }

    }
}

// MARK: -

extension CVComponentSticker: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        if let approximateEmoji = stickerMetadata?.firstEmoji {
            return String(
                format: OWSLocalizedString(
                    "ACCESSIBILITY_LABEL_STICKER_FORMAT",
                    comment: "Accessibility label for stickers. Embeds {{ name of top emoji the sticker resembles }}"),
                approximateEmoji
            )
        } else {
            return OWSLocalizedString(
                "ACCESSIBILITY_LABEL_STICKER",
                comment: "Accessibility label for stickers."
            )
        }
    }
}
