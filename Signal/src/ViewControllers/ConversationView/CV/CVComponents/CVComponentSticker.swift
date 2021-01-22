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

        if let attachmentStream = self.attachmentStream {
            containerView.backgroundColor = nil
            containerView.layer.cornerRadius = 0

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
            reusableMediaView.mediaView.accessibilityLabel = NSLocalizedString("ACCESSIBILITY_LABEL_STICKER",
                                                                               comment: "Accessibility label for stickers.")
            containerView.addSubview(reusableMediaView.mediaView)
            reusableMediaView.mediaView.autoPinEdgesToSuperviewEdges()
        } else if let attachmentPointer = self.attachmentPointer {
            containerView.backgroundColor = Theme.secondaryBackgroundColor
            containerView.layer.cornerRadius = 18

            switch attachmentPointer.state {
            case .enqueued, .downloading:
                break
            case .failed, .pendingManualDownload, .pendingMessageRequest:
                let downloadStack = UIStackView()
                downloadStack.axis = .horizontal
                downloadStack.alignment = .center
                downloadStack.spacing = 8
                downloadStack.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 10)
                downloadStack.isLayoutMarginsRelativeArrangement = true

                let pillView = OWSLayerView.pillView()
                pillView.backgroundColor = Theme.washColor.withAlphaComponent(0.8)
                downloadStack.addSubview(pillView)
                pillView.autoPinEdgesToSuperviewEdges()

                let iconView = UIImageView.withTemplateImageName("arrow-down-24",
                                                                 tintColor: Theme.accentBlueColor)
                iconView.autoSetDimensions(to: CGSize.square(20))
                downloadStack.addArrangedSubview(iconView)

                let downloadLabel = UILabel()
                downloadLabel.text = NSLocalizedString("ACCESSIBILITY_LABEL_STICKER",
                                                       comment: "Accessibility label for stickers.")
                downloadLabel.textColor = Theme.accentBlueColor
                downloadLabel.font = .ows_dynamicTypeCaption1
                downloadStack.addArrangedSubview(downloadLabel)

                containerView.addSubview(downloadStack)
                downloadStack.autoCenterInSuperview()
            @unknown default:
                break
            }
        } else {
            owsFailDebug("Invalid attachment.")
            return
        }

        let accessibilityDescription = NSLocalizedString("ACCESSIBILITY_LABEL_STICKER",
                                                         comment: "Accessibility label for stickers.")
        componentView.rootView.accessibilityLabel = accessibilityLabel(description: accessibilityDescription)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let size = min(maxWidth, Self.stickerSize)
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

        fileprivate let containerView = UIView()

        fileprivate var reusableMediaView: ReusableMediaView?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            containerView
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
            containerView.removeAllSubviews()

            if let reusableMediaView = reusableMediaView,
               reusableMediaView.owner == self {
                reusableMediaView.unload()
                reusableMediaView.owner = nil
            }
        }
    }
}
