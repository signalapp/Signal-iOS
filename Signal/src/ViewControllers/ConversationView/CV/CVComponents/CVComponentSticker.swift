//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentSticker: CVComponentBase, CVComponent {

    private let sticker: CVComponentState.Sticker
    private var stickerMetadata: StickerMetadata? {
        sticker.stickerMetadata
    }
    private var stickerAttachment: TSAttachmentStream? {
        sticker.attachmentStream
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

        // TODO: Handle viewItem.isFailedSticker.

        guard let stickerAttachment = self.stickerAttachment else {
            owsFailDebug("Missing stickerAttachment.")
            return
        }
        let isAnimated = stickerAttachment.shouldBeRenderedByYY
        componentView.isAnimated = isAnimated
        if isAnimated {
            componentView.loadBlock = {
                guard let filePath = stickerAttachment.originalFilePath else {
                    owsFailDebug("Missing filePath.")
                    return
                }
                guard let image = YYImage(contentsOfFile: filePath) else {
                    owsFailDebug("Could not load image.")
                    return
                }
                componentView.animatedImageView.image = image
            }
        } else {
            componentView.loadBlock = {
                guard let filePath = stickerAttachment.originalFilePath else {
                    owsFailDebug("Missing filePath.")
                    return
                }
                guard let image = UIImage(contentsOfFile: filePath) else {
                    owsFailDebug("Could not load image.")
                    return
                }
                componentView.stillmageView.image = image
            }
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

        guard let stickerMetadata = stickerMetadata else {
            // Not yet downloaded.
            return true
        }
        componentDelegate.cvc_didTapStickerPack(stickerMetadata.packInfo)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewSticker: NSObject, CVComponentView {

        // TODO: We might want to:
        //
        // * Lazy-create these views.
        // * Recycle these views (e.g. for animation continuity, for perf).
        // * Ensure a given instance is only ever user for animated or still.
        fileprivate lazy var animatedImageView = { () -> UIImageView in
            let view = YYAnimatedImageView()
            view.contentMode = .scaleAspectFit
            view.accessibilityLabel = NSLocalizedString("ACCESSIBILITY_LABEL_STICKER",
                                                        comment: "Accessibility label for stickers.")
            return view
        }()
        fileprivate lazy var stillmageView = { () -> UIImageView in
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            view.accessibilityLabel = NSLocalizedString("ACCESSIBILITY_LABEL_STICKER",
                                                        comment: "Accessibility label for stickers.")
            return view
        }()

        fileprivate var isAnimated = false

        typealias LoadBlock = () -> Void
        fileprivate var loadBlock: LoadBlock?

        public var isDedicatedCellView = false

        public var rootView: UIView {
            // TODO: If we want to have a stable view hierarchy, we could wrap
            // the image view in a stack view.
            isAnimated ? animatedImageView : stillmageView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {
            if isCellVisible {
                guard let loadBlock = loadBlock else {
                    owsFailDebug("Missing loadBlock.")
                    return
                }
                loadBlock()
            } else {
                animatedImageView.image = nil
                stillmageView.image = nil
            }
        }

        public func reset() {
            animatedImageView.image = nil
            stillmageView.image = nil
            loadBlock = nil
        }
    }
}
