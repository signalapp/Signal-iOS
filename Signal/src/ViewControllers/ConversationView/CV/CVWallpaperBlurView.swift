//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

public class CVWallpaperBlurView: ManualLayoutViewWithLayer {

    private var isPreview = false

    private weak var provider: WallpaperBlurProvider?

    private let imageView = CVImageView()
    private let maskLayer = CAShapeLayer()

    private var state: WallpaperBlurState?
    private var maskCornerRadius: CGFloat = 0

    required init() {
        super.init(name: "CVWallpaperBlurView")

        self.clipsToBounds = true
        self.layer.zPosition = -1

        imageView.contentMode = .scaleAspectFill
        imageView.layer.mask = maskLayer
        imageView.layer.masksToBounds = true
        addSubview(imageView)

        owsAssertDebug(self.layer.delegate === self)
        maskLayer.disableAnimationsWithDelegate()

        addLayoutBlock { [weak self] _ in
            self?.applyLayout()
        }
    }

    public func applyLayout() {
        imageView.frame = imageViewFrame
        maskLayer.frame = imageView.bounds
        let maskPath = UIBezierPath(roundedRect: maskFrame, cornerRadius: maskCornerRadius)
        maskLayer.path = maskPath.cgPath
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    public func configureForPreview(maskCornerRadius: CGFloat) {
        resetContentAndConfiguration()

        self.isPreview = true
        self.maskCornerRadius = maskCornerRadius

        updateIfNecessary()
    }

    public func configure(provider: WallpaperBlurProvider,
                          maskCornerRadius: CGFloat) {
        resetContentAndConfiguration()

        self.isPreview = false
        // TODO: Observe provider changes.
        self.provider = provider
        self.maskCornerRadius = maskCornerRadius

        updateIfNecessary()
    }

    public func updateIfNecessary() {
        guard !isPreview else {
            self.backgroundColor = Theme.backgroundColor
            imageView.isHidden = true
            return
        }
        guard let provider = provider else {
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
        guard let state = self.state else {
            resetContent()
            return
        }
        let referenceView = state.referenceView
        let referenceLayer = referenceView.layer.presentation() ?? referenceView.layer
        let selfLayer = self.layer.presentation() ?? self.layer
        self.imageViewFrame = selfLayer.convert(referenceLayer.bounds, from: referenceLayer)
        self.maskFrame = referenceLayer.convert(selfLayer.bounds, from: selfLayer)

        applyLayout()
    }

    private func resetContent() {
        backgroundColor = nil
        imageView.image = nil
        imageView.isHidden = false
        imageViewFrame = .zero
        maskFrame = .zero
        state = nil
    }

    public func resetContentAndConfiguration() {
        isPreview = false
        provider = nil
        maskCornerRadius = 0

        resetContent()
    }

    // MARK: - CALayerDelegate

    public override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        // Disable all implicit CALayer animations.
        NSNull()
    }
}
