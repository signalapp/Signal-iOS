//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentBodyMedia: CVComponentBase, CVComponent {

    private let bodyMedia: CVComponentState.BodyMedia
    private var items: [CVMediaAlbumItem] {
        bodyMedia.items
    }
    private var mediaAlbumHasFailedAttachment: Bool {
        bodyMedia.mediaAlbumHasFailedAttachment
    }
    private var mediaAlbumHasPendingAttachment: Bool {
        bodyMedia.mediaAlbumHasPendingAttachment
    }
    private var mediaAlbumHasPendingManualDownloadAttachment: Bool {
        bodyMedia.mediaAlbumHasPendingManualDownloadAttachment
    }

    private var areAllItemsImages: Bool {
        for item in items {
            if item.attachment.isAnimated {
                return false
            }
            if !item.attachment.isImage {
                return false
            }
        }
        return true
    }

    var hasDownloadButton: Bool {
        mediaAlbumHasPendingAttachment
    }

    private let footerOverlay: CVComponent?

    init(itemModel: CVItemModel, bodyMedia: CVComponentState.BodyMedia, footerOverlay: CVComponent?) {
        self.bodyMedia = bodyMedia
        self.footerOverlay = footerOverlay

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewBodyMedia()
    }

    private var bodyTextColor: UIColor {
        guard let message = interaction as? TSMessage else {
            return .black
        }
        return conversationStyle.bubbleTextColor(message: message)
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewBodyMedia else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let conversationStyle = self.conversationStyle

        let albumView = componentView.albumView
        albumView.configure(mediaCache: self.cellMediaCache,
                            items: self.items,
                            isOutgoing: self.isOutgoing,
                            isBorderless: self.isBorderless,
                            cellMeasurement: cellMeasurement)

        let blockLayoutView = componentView.blockLayoutView
        blockLayoutView.addSubview(albumView)
        albumView.autoPinEdgesToSuperviewEdges()

        if let footerOverlay = self.footerOverlay {
            let footerView: CVComponentView
            if let footerOverlayView = componentView.footerOverlayView {
                footerView = footerOverlayView
            } else {
                let footerOverlayView = CVComponentFooter.CVComponentViewFooter()
                componentView.footerOverlayView = footerOverlayView
                footerView = footerOverlayView
            }
            footerOverlay.configureForRendering(componentView: footerView,
                                                cellMeasurement: cellMeasurement,
                                                componentDelegate: componentDelegate)
            blockLayoutView.addSubview(footerView.rootView)
            footerView.rootView.autoPinEdge(toSuperviewEdge: .leading,
                                            withInset: conversationStyle.textInsetHorizontal)
            footerView.rootView.autoPinEdge(toSuperviewEdge: .trailing,
                                            withInset: conversationStyle.textInsetHorizontal)
            footerView.rootView.autoPinEdge(toSuperviewEdge: .bottom,
                                            withInset: conversationStyle.textInsetBottom)
            footerView.rootView.autoPinEdge(toSuperviewEdge: .top,
                                            withInset: conversationStyle.textInsetTop,
                                            relation: .greaterThanOrEqual)

            let maxGradientHeight: CGFloat = 40
            let gradientLayer = CAGradientLayer()
            gradientLayer.colors = [
                UIColor(white: 0, alpha: 0.0).cgColor,
                UIColor(white: 0, alpha: 0.4).cgColor
                ]
            let gradientView = OWSLayerView(frame: .zero) { layerView in
                var layerFrame = layerView.bounds
                layerFrame.height = min(maxGradientHeight, layerView.height)
                layerFrame.y = layerView.height - layerFrame.height
                gradientLayer.frame = layerFrame
            }
            componentView.bodyMediaGradientView = gradientView
            gradientView.layer.addSublayer(gradientLayer)
            albumView.addSubview(gradientView)
            componentView.layoutConstraints.append(contentsOf: gradientView.autoPinEdgesToSuperviewEdges())
        }

        // Only apply "inner shadow" for single media, not albums.
        if !isBorderless,
           albumView.itemViews.count == 1,
           let firstMediaView = albumView.itemViews.first {
            let shadowColor: UIColor = isDarkThemeEnabled ? .white : .black
            let innerShadowView = OWSBubbleShapeView(innerShadowWith: shadowColor, radius: 0.5, opacity: 0.15)
            componentView.innerShadowView = innerShadowView
            firstMediaView.addSubview(innerShadowView)
            componentView.layoutConstraints.append(contentsOf: innerShadowView.autoPinEdgesToSuperviewEdges())
        }

        let accessibilityDescription = NSLocalizedString("ACCESSIBILITY_LABEL_MEDIA",
                                                         comment: "Accessibility label for media.")
        albumView.accessibilityLabel = accessibilityLabel(description: accessibilityDescription)

        if hasDownloadButton {
            let iconView = UIImageView.withTemplateImageName("arrow-down-24",
                                                             tintColor: UIColor.ows_white)
            let downloadButton: UIView
            if albumView.itemViews.count > 1 {
                let downloadStack = UIStackView()
                downloadStack.axis = .horizontal
                downloadStack.alignment = .center
                downloadStack.spacing = 8
                downloadStack.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 10)
                downloadStack.isLayoutMarginsRelativeArrangement = true

                let pillView = OWSLayerView.pillView()
                pillView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.8)
                downloadStack.addSubview(pillView)
                pillView.autoPinEdgesToSuperviewEdges()

                iconView.autoSetDimensions(to: CGSize.square(20))
                downloadStack.addArrangedSubview(iconView)

                let downloadLabel = UILabel()
                let downloadFormat = (areAllItemsImages
                                        ? NSLocalizedString("MEDIA_GALLERY_ITEM_IMAGE_COUNT_FORMAT",
                                        comment: "Format for an indicator of the number of image items in a media gallery. Embeds {{ the number of items in the media gallery }}.")
                                        : NSLocalizedString("MEDIA_GALLERY_ITEM_MIXED_COUNT_FORMAT",
                                        comment: "Format for an indicator of the number of image or video items in a media gallery. Embeds {{ the number of items in the media gallery }}."))
                downloadLabel.text = String(format: downloadFormat, OWSFormat.formatInt(albumView.itemViews.count))
                downloadLabel.textColor = UIColor.ows_white
                downloadLabel.font = .ows_dynamicTypeSubheadline
                downloadStack.addArrangedSubview(downloadLabel)

                downloadButton = downloadStack
            } else {
                let circleView = OWSLayerView.circleView(size: 44)
                circleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.8)
                iconView.autoSetDimensions(to: CGSize.square(24))
                circleView.addSubview(iconView)
                iconView.autoCenterInSuperview()
                downloadButton = circleView
            }

            componentView.rootView.addSubview(downloadButton)
            downloadButton.autoCenterInSuperview()

            if mediaAlbumHasPendingManualDownloadAttachment {
                let attachmentPointers = items.compactMap { $0.attachment as? TSAttachmentPointer }
                let pendingManualDownloadAttachments = attachmentPointers.filter { $0.isPendingManualDownload }
                let totalSize = pendingManualDownloadAttachments.map { $0.byteCount}.reduce(0, +)

                if totalSize > 0 {
                    let downloadSizeView = OWSLayerView.pillView()
                    downloadSizeView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.8)
                    downloadSizeView.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 1)

                    var downloadSizeText = [OWSFormat.formatFileSize(UInt(totalSize))]

                    if pendingManualDownloadAttachments.count == 1,
                       let firstAttachmentPointer = pendingManualDownloadAttachments.first {
                        if firstAttachmentPointer.isAnimated {
                            // Do nothing.
                        } else if firstAttachmentPointer.isImage {
                            downloadSizeText.append(CommonStrings.attachmentTypePhoto)
                        } else if firstAttachmentPointer.isVideo {
                            downloadSizeText.append(CommonStrings.attachmentTypeVideo)
                        }
                    }

                    let downloadSizeLabel = UILabel()
                    downloadSizeLabel.text = downloadSizeText.joined(separator: " • ")
                    downloadSizeLabel.textColor = UIColor.ows_white
                    downloadSizeLabel.font = .ows_dynamicTypeCaption1
                    downloadSizeView.addSubview(downloadSizeLabel)
                    downloadSizeLabel.autoPinEdgesToSuperviewMargins()

                    componentView.rootView.addSubview(downloadSizeView)
                    downloadSizeView.autoPinEdge(toSuperviewEdge: .top, withInset: 9)
                    downloadSizeView.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
                }
            }
        }
    }

    public func bubbleViewPartner(componentView: CVComponentView) -> OWSBubbleViewPartner? {
        guard let componentView = componentView as? CVComponentViewBodyMedia else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.innerShadowView
    }

    private static var senderNameFont: UIFont {
        UIFont.ows_dynamicTypeCaption1.ows_semibold
    }

    private var maxMediaMessageWidth: CGFloat {
        let maxMediaMessageWidth = conversationStyle.maxMediaMessageWidth
        if self.isBorderless {
            return min(175, maxMediaMessageWidth)
        }
        return maxMediaMessageWidth
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)
        owsAssertDebug(items.count > 0)

        // We may need to reserve space for a footer overlay.
        var minWidth: CGFloat = 0
        if let footerOverlay = self.footerOverlay {
            let maxFooterWidth = max(0, maxWidth - conversationStyle.textInsets.totalWidth)
            let footerSize = footerOverlay.measure(maxWidth: maxFooterWidth,
                                                   measurementBuilder: measurementBuilder)
            minWidth = min(maxWidth, footerSize.width + conversationStyle.textInsets.totalWidth)
        }

        let maxWidth = min(maxWidth, maxMediaMessageWidth)

        return CVMediaAlbumView.layoutSize(maxWidth: maxWidth,
                                           minWidth: minWidth,
                                           items: self.items,
                                           measurementBuilder: measurementBuilder).ceil
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewBodyMedia else {
            owsFailDebug("Unexpected componentView.")
            return false
        }
        guard let message = interaction as? TSMessage else {
            owsFailDebug("Invalid interaction.")
            return false
        }
        if hasDownloadButton {
            componentDelegate.cvc_didTapFailedOrPendingDownloads(message)
            return true
        }

        let albumView = componentView.albumView
        let location = sender.location(in: albumView)
        guard let mediaView = albumView.mediaView(forLocation: location) else {
            Logger.warn("Missing mediaView.")
            return false
        }
        let isMoreItemsWithMediaView = albumView.isMoreItemsView(mediaView: mediaView)

        if isMoreItemsWithMediaView,
           mediaAlbumHasFailedAttachment {
            componentDelegate.cvc_didTapFailedOrPendingDownloads(message)
            return true
        }

        let attachment = mediaView.attachment
        if let attachmentPointer = attachment as? TSAttachmentPointer {
            switch attachmentPointer.state {
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                componentDelegate.cvc_didTapFailedOrPendingDownloads(message)
                return true
            case .enqueued, .downloading:
                Logger.warn("Media attachment not yet downloaded.")
                return false
            @unknown default:
                owsFailDebug("Invalid attachment pointer state.")
                return false
            }
        }

        guard let attachmentStream = attachment as? TSAttachmentStream else {
            owsFailDebug("unexpected attachment.")
            return false
        }

        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        componentDelegate.cvc_didTapBodyMedia(itemViewModel: itemViewModel,
                                              attachmentStream: attachmentStream,
                                              imageView: mediaView)
        return true
    }

    public func albumItemView(forAttachment attachment: TSAttachmentStream,
                              componentView: CVComponentView) -> UIView? {
        guard let componentView = componentView as? CVComponentViewBodyMedia else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        let albumView = componentView.albumView
        guard let albumItemView = (albumView.itemViews.first { $0.attachment == attachment }) else {
            assert(albumView.moreItemsView != nil)
            return albumView.moreItemsView
        }
        return albumItemView
    }

    // MARK: -

    // We use this view to implement BodyMediaPresentationContext below.
    class CVComponentViewBodyMediaRootView: OWSStackView {

        fileprivate var bodyMediaGradientView: UIView?

        fileprivate var footerOverlayView: CVComponentView?

        public override func reset() {
            bodyMediaGradientView = nil
            footerOverlayView = nil

            super.reset()
        }
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewBodyMedia: NSObject, CVComponentView {

        fileprivate let blockLayoutView = CVComponentViewBodyMediaRootView(name: "blockLayoutView")

        fileprivate let albumView = CVMediaAlbumView()

        fileprivate var bodyMediaGradientView: UIView? {
            get { blockLayoutView.bodyMediaGradientView }
            set { blockLayoutView.bodyMediaGradientView = newValue }
        }

        fileprivate var innerShadowView: OWSBubbleShapeView?

        fileprivate var layoutConstraints = [NSLayoutConstraint]()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            blockLayoutView
        }

        // MARK: - Subcomponents

        fileprivate var footerOverlayView: CVComponentView? {
            get { blockLayoutView.footerOverlayView }
            set { blockLayoutView.footerOverlayView = newValue }
        }

        // MARK: -

        public func setIsCellVisible(_ isCellVisible: Bool) {
            if isCellVisible {
                albumView.loadMedia()
            } else {
                albumView.unloadMedia()
            }
        }

        public func reset() {
            albumView.reset()
            blockLayoutView.reset()
            footerOverlayView?.reset()

            bodyMediaGradientView?.removeFromSuperview()
            bodyMediaGradientView = nil

            innerShadowView?.removeFromSuperview()
            innerShadowView = nil

            NSLayoutConstraint.deactivate(layoutConstraints)
            layoutConstraints = []
        }
    }
}

// MARK: -

protocol BodyMediaPresentationContext {
    var mediaOverlayViews: [UIView] { get }
}

// MARK: -

extension CVComponentBodyMedia.CVComponentViewBodyMediaRootView: BodyMediaPresentationContext {
    var mediaOverlayViews: [UIView] {
        var result = [UIView]()
        if let footerOverlayView = footerOverlayView {
            result.append(footerOverlayView.rootView)
        }
        if let bodyMediaGradientView = bodyMediaGradientView {
            result.append(bodyMediaGradientView)
        }
        return result
    }
}
