//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

@available(iOS, deprecated: 26)
class BlurredToolbarContainer: UIView {

    let toolbar = UIToolbar()
    private var blurEffectView: UIVisualEffectView?

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)

        addSubview(toolbar)
        toolbar.autoPinEdge(toSuperviewSafeArea: .bottom)
        toolbar.autoPinWidthToSuperview()
        toolbar.autoPinEdge(toSuperviewSafeArea: .top)

        guard UIAccessibility.isReduceTransparencyEnabled == false else { return }

        // Make navbar more translucent than default. Navbars remove alpha from any assigned backgroundColor, so
        // to achieve transparency, we have to assign a transparent image.
        toolbar.setBackgroundImage(UIImage.image(color: .clear), forToolbarPosition: .any, barMetrics: .default)
        // Remove hairline below bar.
        toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

        let blurEffectView = UIVisualEffectView()
        blurEffectView.isUserInteractionEnabled = false
        insertSubview(blurEffectView, at: 0)
        // On iOS11, despite inserting the blur at 0, other views are later inserted into the navbar behind the blur,
        // so we have to set a zindex to avoid obscuring navbar title/buttons.
        blurEffectView.layer.zPosition = -1
        blurEffectView.autoPinEdgesToSuperviewEdges()
        self.blurEffectView = blurEffectView

        updateColors()
    }

    func updateColors() {
        toolbar.tintColor = Theme.primaryIconColor

        guard UIAccessibility.isReduceTransparencyEnabled == false else {
            let backgroundImage = UIImage.image(color: Theme.navbarBackgroundColor)
            toolbar.setBackgroundImage(backgroundImage, forToolbarPosition: .any, barMetrics: .default)
            return
        }

        blurEffectView?.effect = Theme.barBlurEffect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
