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
    private var mediaAlbumHasPendingMessageRequestAttachment: Bool {
        bodyMedia.mediaAlbumHasPendingMessageRequestAttachment
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

        let albumView = componentView.albumView
        let location = sender.location(in: albumView)
        guard let mediaView = albumView.mediaView(forLocation: location) else {
            Logger.warn("Missing mediaView.")
            return false
        }
        let isMoreItemsWithMediaView = albumView.isMoreItemsView(mediaView: mediaView)

        if isMoreItemsWithMediaView {
            if mediaAlbumHasFailedAttachment {
                componentDelegate.cvc_didTapFailedDownloads(message)
                return true
            } else if mediaAlbumHasPendingMessageRequestAttachment {
                componentDelegate.cvc_didTapPendingMessageRequestIncomingAttachment(message)
                return true
            }
        }

        let attachment = mediaView.attachment
        if let attachmentPointer = attachment as? TSAttachmentPointer {
            switch attachmentPointer.state {
            case .failed:
                componentDelegate.cvc_didTapFailedDownloads(message)
                return true
            case .pendingMessageRequest:
                componentDelegate.cvc_didTapPendingMessageRequestIncomingAttachment(message)
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
