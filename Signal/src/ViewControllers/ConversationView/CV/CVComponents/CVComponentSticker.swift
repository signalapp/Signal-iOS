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

            let isAnimated = attachmentStream.shouldBeRenderedByYY
            componentView.isAnimated = isAnimated
            if isAnimated {
                containerView.addSubview(componentView.animatedImageView)
                componentView.animatedImageView.autoPinEdgesToSuperviewEdges()

                componentView.loadBlock = {
                    guard let filePath = attachmentStream.originalFilePath else {
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
                containerView.addSubview(componentView.stillmageView)
                componentView.stillmageView.autoPinEdgesToSuperviewEdges()

                componentView.loadBlock = {
                    guard let filePath = attachmentStream.originalFilePath else {
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
        } else if let attachmentPointer = self.attachmentPointer {
            componentView.loadBlock = {}
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
            containerView
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
            containerView.removeAllSubviews()
            animatedImageView.image = nil
            stillmageView.image = nil
            loadBlock = nil
        }
    }
}
