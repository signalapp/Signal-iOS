//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentSticker: CVComponentBase, CVComponent {

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

        let containerView = componentView.containerView
        containerView.apply(config: containerViewConfig)

        guard let stickerSize = cellMeasurement.value(key: stickerMeasurementKey) else {
            owsFailDebug("Missing stickerMeasurement.")
            return
        }

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
            containerView.addArrangedSubview(mediaView)
            componentView.layoutConstraints.append(contentsOf: mediaView.autoSetDimensions(to: .square(stickerSize)))

            switch CVAttachmentProgressView.progressType(forAttachment: attachmentStream,
                                                         interaction: interaction) {
            case .none:
                break
            case .uploading:
                let progressView = CVAttachmentProgressView(direction: .upload(attachmentStream: attachmentStream),
                                                            style: .withCircle,
                                                            conversationStyle: conversationStyle)
                containerView.addSubview(progressView)
                progressView.autoAlignAxis(.horizontal, toSameAxisOf: mediaView)
                progressView.autoAlignAxis(.vertical, toSameAxisOf: mediaView)
            case .pendingDownload:
                break
            case .downloading:
                break
            case .restoring:
                // TODO: We could easily show progress for restores.
                owsFailDebug("Restoring progress type.")
                break
            case .unknown:
                owsFailDebug("Unknown progress type.")
                break
            }
        } else if let attachmentPointer = self.attachmentPointer {
            let placeholderView = UIView()
            placeholderView.backgroundColor = Theme.secondaryBackgroundColor
            placeholderView.layer.cornerRadius = 18
            containerView.addArrangedSubview(placeholderView)
            componentView.layoutConstraints.append(contentsOf: placeholderView.autoSetDimensions(to: .square(stickerSize)))

            let progressView = CVAttachmentProgressView(direction: .download(attachmentPointer: attachmentPointer),
                                                        style: .withCircle,
                                                        conversationStyle: conversationStyle)
            placeholderView.addSubview(progressView)
            progressView.autoCenterInSuperview()
        } else {
            owsFailDebug("Invalid attachment.")
            return
        }
    }

    private var containerViewConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: isOutgoing ? .trailing : .leading,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private let stickerMeasurementKey = "stickerMeasurementKey"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let size: CGFloat = ceil(min(maxWidth, Self.stickerSize))
        measurementBuilder.setValue(key: stickerMeasurementKey, value: size)
        return CGSize(width: size, height: size).ceil
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
        componentDelegate.cvc_didTapStickerPack(stickerMetadata.packInfo)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewSticker: NSObject, CVComponentView {

        fileprivate let containerView = OWSStackView(name: "sticker.container")

        fileprivate var reusableMediaView: ReusableMediaView?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            containerView
        }

        fileprivate var layoutConstraints = [NSLayoutConstraint]()

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
            containerView.reset()

            NSLayoutConstraint.deactivate(layoutConstraints)
            layoutConstraints = []

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
        NSLocalizedString("ACCESSIBILITY_LABEL_STICKER",
                          comment: "Accessibility label for stickers.")
    }
}
