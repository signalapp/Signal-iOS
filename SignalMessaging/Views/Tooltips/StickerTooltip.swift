//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage

@objc
public class StickerTooltip: UIView {

    private let stickerPack: StickerPack
    private let block: (() -> Void)?

    // MARK: Initializers

    @objc
    required public init(fromView: UIView,
                         widthReferenceView: UIView,
                         tailReferenceView: UIView,
                         stickerPack: StickerPack,
                         block: (() -> Void)?) {
        self.stickerPack = stickerPack
        self.block = block

        super.init(frame: .zero)

        createContents(fromView: fromView,
                       widthReferenceView: widthReferenceView,
                       tailReferenceView: tailReferenceView)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    public class func presentTooltip(fromView: UIView,
                                     widthReferenceView: UIView,
                                     tailReferenceView: UIView,
                                     stickerPack: StickerPack,
                                     block: (() -> Void)?) -> UIView {
        let tooltip = StickerTooltip(fromView: fromView,
                                     widthReferenceView: widthReferenceView,
                                     tailReferenceView: tailReferenceView,
                                     stickerPack: stickerPack,
                                     block: block)
        return tooltip
    }

    private let tailHeight: CGFloat = 8
    private let tailWidth: CGFloat = 16
    private let bubbleRounding: CGFloat = 8

    private let iconView = YYAnimatedImageView()

    private func createContents(fromView: UIView,
                                widthReferenceView: UIView,
                                tailReferenceView: UIView) {
        backgroundColor = .clear
        isOpaque = false

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                    action: #selector(handleTap)))

        // Bubble View

        let bubbleView = OWSLayerView()
        let shapeLayer = CAShapeLayer()
        shapeLayer.shadowColor = UIColor.black.cgColor
        shapeLayer.shadowOffset = CGSize(width: 0, height: 40)
        shapeLayer.shadowRadius = 40
        shapeLayer.shadowOpacity = 0.33
        shapeLayer.fillColor = Theme.backgroundColor.cgColor
        bubbleView.layer.addSublayer(shapeLayer)
        addSubview(bubbleView)
        bubbleView.autoPinEdgesToSuperviewEdges()
        bubbleView.layoutCallback = { [weak self] view in
            guard let self = self else {
                return
            }
            let bezierPath = UIBezierPath()

            // Bubble
            var bubbleBounds = view.bounds
            bubbleBounds.size.height -= self.tailHeight
            bezierPath.append(UIBezierPath(roundedRect: bubbleBounds, cornerRadius: self.bubbleRounding))

            // Tail
            //
            // The tail should _try_ to point to the "tail reference view".
            let tailReferenceFrame = self.convert(tailReferenceView.bounds, from: tailReferenceView)
            let tailHalfWidth = self.tailWidth * 0.5
            let tailHCenterMin = self.bubbleRounding + tailHalfWidth
            let tailHCenterMax = bubbleBounds.width - tailHCenterMin
            let tailHCenter = tailReferenceFrame.center.x.clamp(tailHCenterMin, tailHCenterMax)
            let tailBottom = CGPoint(x: tailHCenter, y: view.bounds.height)
            let tailLeft = CGPoint(x: tailHCenter - tailHalfWidth, y: bubbleBounds.height)
            let tailRight = CGPoint(x: tailHCenter + tailHalfWidth, y: bubbleBounds.height)
            bezierPath.move(to: tailBottom)
            bezierPath.addLine(to: tailLeft)
            bezierPath.addLine(to: tailRight)
            bezierPath.addLine(to: tailBottom)

            shapeLayer.path = bezierPath.cgPath
            shapeLayer.frame = view.bounds
        }

        // Bubble Contents

        iconView.autoSetDimensions(to: CGSize(width: 24, height: 24))
        updateIconView()

        let label = UILabel()
        label.text = NSLocalizedString("STICKER_PACK_INSTALLED_TOOLTIP",
                                       comment: "Tooltip indicating that a sticker pack was installed.")
        label.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        label.textColor = Theme.primaryColor

        let stackView = UIStackView(arrangedSubviews: [
            iconView,
            label
            ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 6
        stackView.layoutMargins = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        stackView.isLayoutMarginsRelativeArrangement = true

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
        layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: tailHeight, right: 0)

        fromView.addSubview(self)
        autoPinEdge(.bottom, to: .top, of: tailReferenceView, withOffset: -0)
        // Insist on the tooltip fitting within the margins of the widthReferenceView.
        autoPinEdge(.left, to: .left, of: widthReferenceView, withOffset: 20, relation: .greaterThanOrEqual)
        autoPinEdge(.right, to: .right, of: widthReferenceView, withOffset: -20, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultLow) {
            // Prefer that the tooltip's tail is as far as possible.
            // It should point at the center of the "tail reference view".
            let edgeOffset = bubbleRounding + tailWidth * 0.5 - tailReferenceView.width() * 0.5
            autoPinEdge(.right, to: .right, of: tailReferenceView, withOffset: edgeOffset)
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)
    }

    private func updateIconView() {
        guard iconView.image == nil else {
            iconView.isHidden = true
            return
        }
        let stickerInfo = stickerPack.coverInfo
        guard let filePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerInfo) else {
            // This sticker is not downloaded; try to download now.
            StickerManager.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
                .done { [weak self] (stickerData: Data) in
                    guard let self = self else {
                        return
                    }
                    self.updateIconView(imageData: stickerData)
                }.catch {(error) in
                    owsFailDebug("error: \(error)")
                }.retainUntilComplete()
            return
        }

        guard let image = YYImage(contentsOfFile: filePath) else {
            owsFailDebug("could not load asset.")
            return
        }
        iconView.image = image
        iconView.isHidden = false
    }

    private func updateIconView(imageData: Data) {
        guard iconView.image == nil else {
            iconView.isHidden = true
            return
        }
        guard let image = YYImage(data: imageData) else {
            owsFailDebug("could not load asset.")
            return
        }
        iconView.image = image
        iconView.isHidden = false
    }

    // MARK: Events

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        updateIconView()
    }

    @objc
    func handleTap(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        Logger.verbose("")
        removeFromSuperview()
        block?()
    }
}
