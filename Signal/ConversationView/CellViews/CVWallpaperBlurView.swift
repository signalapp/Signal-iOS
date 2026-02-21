//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class CVWallpaperBlurView: ManualLayoutViewWithLayer, CVDimmableView {

    private weak var provider: WallpaperBlurProvider?
    private var isPreview = false
    private var state: WallpaperBlurState?

    private let imageView = CVImageView()
    private let imageViewMaskLayer = CAShapeLayer()

    private let maskLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()

    private var bubbleConfig: BubbleConfiguration?

    init() {
        super.init(name: "CVWallpaperBlurView")

        clipsToBounds = true
        layer.zPosition = -1
        strokeLayer.fillColor = nil

        imageView.contentMode = .scaleAspectFill
        imageView.layer.mask = imageViewMaskLayer
        imageView.layer.masksToBounds = true
        imageView.layer.addSublayer(strokeLayer)
        addSubview(imageView)

        owsAssertDebug(layer.delegate === self)
        imageViewMaskLayer.disableAnimationsWithDelegate()
        maskLayer.disableAnimationsWithDelegate()
        strokeLayer.disableAnimationsWithDelegate()

        addLayoutBlock { [weak self] _ in
            self?.applyLayout()
        }
    }

    public func applyLayout() {
        guard bounds.size.isNonEmpty else { return }

        UIView.performWithoutAnimation {
            imageView.frame = imageViewFrame
            imageViewMaskLayer.frame = imageView.layer.bounds
            strokeLayer.frame = imageView.layer.bounds

            if let bubbleConfig {
                // Corners.
                imageViewMaskLayer.path = bubbleConfig.bubblePath(for: maskFrame).cgPath
                maskLayer.path = bubbleConfig.bubblePath(for: bounds).cgPath
                layer.mask = maskLayer

                // Stroke.
                if
                    let stroke = bubbleConfig.stroke,
                    let strokePath = bubbleConfig.strokePath(for: maskFrame)
                {
                    strokeLayer.lineWidth = stroke.width
                    strokeLayer.strokeColor = stroke.color.cgColor
                    strokeLayer.path = strokePath.cgPath
                    strokeLayer.isHidden = false
                } else {
                    strokeLayer.isHidden = true
                }
            } else {
                imageViewMaskLayer.path = UIBezierPath(rect: maskFrame).cgPath
                layer.mask = nil

                strokeLayer.isHidden = true
            }
        }
    }

    public func configure(
        provider: WallpaperBlurProvider?,
        bubbleConfig: BubbleConfiguration?,
    ) {
        resetContentAndConfiguration()

        self.isPreview = (provider == nil)
        // TODO: Observe provider changes.
        self.provider = provider
        self.bubbleConfig = bubbleConfig

        updateIfNecessary()
    }

    public func updateIfNecessary() {
        guard !isPreview else {
            backgroundColor = Theme.backgroundColor
            imageView.isHidden = true
            return
        }
        guard let provider else {
            owsFailDebug("Missing provider.")
            resetContentAndConfiguration()
            return
        }
        guard let state = provider.wallpaperBlurState else {
            resetContent()
            return
        }
        guard state.id != self.state?.id else {
            ensurePositioning()
            return
        }
        self.state = state
        imageView.image = state.image
        imageView.isHidden = false

        ensurePositioning()
    }

    private var imageViewFrame: CGRect = .zero
    private var maskFrame: CGRect = .zero

    private func ensurePositioning() {
        guard !isPreview else {
            return
        }
        guard let state else {
            resetContent()
            return
        }
        let referenceView = state.referenceView
        imageViewFrame = convert(referenceView.bounds, from: referenceView)
        maskFrame = referenceView.convert(bounds, from: self)

        applyLayout()
    }

    private func resetContent() {
        backgroundColor = nil
        imageView.image = nil
        imageView.isHidden = false
        imageViewFrame = .zero
        maskFrame = .zero
        strokeLayer.isHidden = true
        state = nil
    }

    public func resetContentAndConfiguration() {
        isPreview = false
        provider = nil
        bubbleConfig = nil

        resetContent()
    }

    @available(iOS, unavailable)
    override public func reset() {
        fatalError("Not supported.")
    }

    // MARK: - CALayerDelegate

    override public func action(for layer: CALayer, forKey event: String) -> CAAction? {
        // Disable all implicit CALayer animations.
        NSNull()
    }

    // MARK: - CVDimmableView

    var dimmerColor: UIColor = .clear

    var dimsContent = false

    var backgroundLayer: CALayer? { imageView.layer }
}

// MARK: -

extension CVWallpaperBlurView: OWSBubbleViewHost {

    public var maskPath: UIBezierPath {
        guard let bubbleConfig else {
            return UIBezierPath(rect: bounds)
        }
        return bubbleConfig.bubblePath(for: bounds)
    }

    public var bubbleReferenceView: UIView { self }
}
