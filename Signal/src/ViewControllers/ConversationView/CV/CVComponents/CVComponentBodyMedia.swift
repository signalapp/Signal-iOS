//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public class CVComponentBodyMedia: CVComponentBase, CVComponent {

    public var componentKey: CVComponentKey { .bodyMedia }

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
        albumView.configure(mediaCache: self.mediaCache,
                            items: self.items,
                            interaction: self.interaction,
                            isBorderless: self.isBorderless,
                            cellMeasurement: cellMeasurement,
                            conversationStyle: conversationStyle)

        let stackView = componentView.stackView

        stackView.reset()
        stackView.configure(config: stackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_stackView,
                            subviews: [ albumView ])

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
            let footerRootView = footerView.rootView
            stackView.addSubview(footerRootView)
            let footerSize = cellMeasurement.size(key: Self.measurementKey_footerSize) ?? .zero
            stackView.addLayoutBlock { view in
                var footerFrame = view.bounds
                // Apply h-insets.
                footerFrame.x += conversationStyle.textInsetHorizontal
                footerFrame.width -= conversationStyle.textInsetHorizontal * 2
                // Ensure footer height fits within text insets.
                let maxFooterHeight = (view.bounds.height -
                                        (conversationStyle.textInsetTop + conversationStyle.textInsetBottom))
                footerFrame.height = min(maxFooterHeight, footerSize.height)
                // Bottom align.
                footerFrame.y = (view.bounds.height -
                                    (footerFrame.height +
                                        conversationStyle.textInsetBottom))
                footerRootView.frame = footerFrame
            }

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
            stackView.layoutSubviewToFillSuperviewEdges(gradientView)
        }

        // Only apply "inner shadow" for single media, not albums.
        if !isBorderless,
           albumView.itemViews.count == 1,
           let firstMediaView = albumView.itemViews.first {
            let shadowColor: UIColor = isDarkThemeEnabled ? .white : .black
            let innerShadowView = OWSBubbleShapeView(mode: .innerShadow(color: shadowColor,
                                                                        radius: 0.5,
                                                                        opacity: 0.15))
            componentView.innerShadowView = innerShadowView
            firstMediaView.addSubview(innerShadowView)
            stackView.layoutSubviewToFillSuperviewEdges(innerShadowView)
        }

        if hasDownloadButton {
            let iconView = CVImageView()
            iconView.setTemplateImageName("arrow-down-24", tintColor: UIColor.ows_white)
            if albumView.itemViews.count > 1 {
                let downloadStackConfig = ManualStackView.Config(axis: .horizontal,
                                                                 alignment: .center,
                                                                 spacing: 8,
                                                                 layoutMargins: UIEdgeInsets(hMargin: 16, vMargin: 10))
                let downloadStack = ManualStackView(name: "downloadStack")
                downloadStack.apply(config: downloadStackConfig)
                var subviewInfos = [ManualStackSubviewInfo]()

                let pillView = ManualLayoutViewWithLayer.pillView(name: "pillView")
                pillView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.8)
                downloadStack.addSubviewToFillSuperviewEdges(pillView)

                downloadStack.addArrangedSubview(iconView)
                subviewInfos.append(CGSize.square(20).asManualSubviewInfo(hasFixedSize: true))

                let downloadLabel = CVLabel()
                let downloadFormat = (areAllItemsImages
                                        ? OWSLocalizedString("MEDIA_GALLERY_ITEM_IMAGE_COUNT_%d", tableName: "PluralAware",
                                        comment: "Format for an indicator of the number of image items in a media gallery. Embeds {{ the number of items in the media gallery }}.")
                                        : OWSLocalizedString("MEDIA_GALLERY_ITEM_MIXED_COUNT_%d", tableName: "PluralAware",
                                        comment: "Format for an indicator of the number of image or video items in a media gallery. Embeds {{ the number of items in the media gallery }}."))
                downloadStack.addArrangedSubview(downloadLabel)
                let downloadLabelConfig = CVLabelConfig(text: String.localizedStringWithFormat(downloadFormat, items.count),
                                                        font: .dynamicTypeSubheadline,
                                                        textColor: UIColor.ows_white)
                downloadLabelConfig.applyForRendering(label: downloadLabel)
                let downloadLabelSize = CVText.measureLabel(config: downloadLabelConfig,
                                                            maxWidth: CGFloat.greatestFiniteMagnitude)
                subviewInfos.append(downloadLabelSize.asManualSubviewInfo)

                let downloadStackMeasurement = ManualStackView.measure(config: downloadStackConfig,
                                                                       subviewInfos: subviewInfos)
                downloadStack.measurement = downloadStackMeasurement
                stackView.addSubviewToCenterOnSuperview(downloadStack,
                                                        size: downloadStackMeasurement.measuredSize)
            } else {
                let circleSize: CGFloat = 44
                let circleView = OWSLayerView.circleView(size: circleSize)
                circleView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.8)
                stackView.addSubviewToCenterOnSuperview(circleView, size: .square(circleSize))
                stackView.addSubviewToCenterOnSuperview(iconView, size: .square(24))
            }

            if mediaAlbumHasPendingAttachment {
                let attachmentPointers = items.compactMap { $0.attachment as? TSAttachmentPointer }
                let pendingManualDownloadAttachments = attachmentPointers.filter { $0.isPendingManualDownload }
                let totalSize = pendingManualDownloadAttachments.map { $0.byteCount}.reduce(0, +)

                if totalSize > 0 {
                    var downloadSizeText = [OWSFormat.localizedFileSizeString(from: Int64(totalSize))]
                    if pendingManualDownloadAttachments.count == 1,
                       let firstAttachmentPointer = pendingManualDownloadAttachments.first {
                        if firstAttachmentPointer.isAnimated || firstAttachmentPointer.isLoopingVideo {
                            // Do nothing.
                        } else if firstAttachmentPointer.isImage {
                            downloadSizeText.append(CommonStrings.attachmentTypePhoto)
                        } else if firstAttachmentPointer.isVideo {
                            downloadSizeText.append(CommonStrings.attachmentTypeVideo)
                        }
                    }

                    let downloadSizeView = ManualLayoutViewWithLayer.pillView(name: "downloadSizeView")
                    downloadSizeView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.8)
                    downloadSizeView.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 1)

                    let downloadSizeLabelConfig = CVLabelConfig(text: downloadSizeText.joined(separator: " • "),
                                                                font: .dynamicTypeCaption1,
                                                                textColor: .ows_white)
                    let downloadSizeLabel = CVLabel()
                    downloadSizeLabelConfig.applyForRendering(label: downloadSizeLabel)
                    let downloadSizeLabelSize = CVText.measureLabel(config: downloadSizeLabelConfig,
                                                                    maxWidth: .greatestFiniteMagnitude)
                    downloadSizeView.addSubviewToFillSuperviewMargins(downloadSizeLabel)

                    let downloadSizeViewSize = downloadSizeLabelSize + downloadSizeView.layoutMargins.asSize
                    stackView.addSubview(downloadSizeView)
                    stackView.addLayoutBlock { view in
                        let hInset: CGFloat = 16
                        let x = (CurrentAppContext().isRTL
                                    ? view.width - (downloadSizeViewSize.width - hInset)
                                    : hInset)
                        downloadSizeView.frame = CGRect(x: x,
                                                        y: 9,
                                                        width: downloadSizeViewSize.width,
                                                        height: downloadSizeViewSize.height)
                    }
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

    private static var senderNameFont: UIFont { UIFont.dynamicTypeCaption1.semibold() }

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    private var maxMediaMessageWidth: CGFloat {
        let maxMediaMessageWidth = conversationStyle.maxMediaMessageWidth
        if self.isBorderless {
            return min(175, maxMediaMessageWidth)
        }
        return maxMediaMessageWidth
    }

    private static let measurementKey_stackView = "CVComponentBodyMedia.measurementKey_stackView"
    private static let measurementKey_footerSize = "CVComponentBodyMedia.measurementKey_footerSize"

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
            measurementBuilder.setSize(key: Self.measurementKey_footerSize, size: footerSize)
        }

        let maxWidth = min(maxWidth, maxMediaMessageWidth)

        let albumSize = CVMediaAlbumView.measure(maxWidth: maxWidth,
                                                 minWidth: minWidth,
                                                 items: self.items,
                                                 measurementBuilder: measurementBuilder)
        let albumInfo = albumSize.asManualSubviewInfo
        let stackMeasurement = ManualStackView.measure(config: stackConfig,
                                                       measurementBuilder: measurementBuilder,
                                                       measurementKey: Self.measurementKey_stackView,
                                                       subviewInfos: [ albumInfo ],
                                                       maxWidth: maxWidth)
        return stackMeasurement.measuredSize
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
            componentDelegate.didTapFailedOrPendingDownloads(message)
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
            componentDelegate.didTapFailedOrPendingDownloads(message)
            return true
        }

        let attachment = mediaView.attachment
        if let attachmentPointer = attachment as? TSAttachmentPointer {
            switch attachmentPointer.state {
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                componentDelegate.didTapFailedOrPendingDownloads(message)
                return true
            case .enqueued, .downloading:
                Logger.warn("Media attachment not yet downloaded.")
                Self.attachmentDownloads.cancelDownload(attachmentId: attachmentPointer.uniqueId)
                return true
            }
        }

        guard let attachmentStream = attachment as? TSAttachmentStream else {
            owsFailDebug("unexpected attachment.")
            return false
        }

        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        if let item = items.first(where: { $0.attachment.uniqueId == attachment.uniqueId }), item.isBroken {
            componentDelegate.didTapBrokenVideo()
            return true
        }
        componentDelegate.didTapBodyMedia(itemViewModel: itemViewModel,
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
    class CVComponentViewBodyMediaRootView: ManualStackView {

        fileprivate var bodyMediaGradientView: UIView?

        fileprivate var footerOverlayView: CVComponentView?

        open override func reset() {
            bodyMediaGradientView = nil
            footerOverlayView = nil

            super.reset()
        }
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewBodyMedia: NSObject, CVComponentView {

        fileprivate let stackView = CVComponentViewBodyMediaRootView(name: "stackView")

        fileprivate let albumView = CVMediaAlbumView()

        fileprivate var bodyMediaGradientView: UIView? {
            get { stackView.bodyMediaGradientView }
            set { stackView.bodyMediaGradientView = newValue }
        }

        fileprivate var innerShadowView: OWSBubbleShapeView?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            stackView
        }

        // MARK: - Subcomponents

        fileprivate var footerOverlayView: CVComponentView? {
            get { stackView.footerOverlayView }
            set { stackView.footerOverlayView = newValue }
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
            stackView.reset()
            footerOverlayView?.reset()

            bodyMediaGradientView?.removeFromSuperview()
            bodyMediaGradientView = nil

            innerShadowView?.removeFromSuperview()
            innerShadowView = nil
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

// MARK: -

extension CVComponentBodyMedia: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        // TODO: We could describe how many media
        // and their type (video, image, animated image).
        OWSLocalizedString("ACCESSIBILITY_LABEL_MEDIA",
                          comment: "Accessibility label for media.")
    }
}
