//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import UIKit

class BlurredToolbarContainer: UIView {
    let toolbar = UIToolbar()
    private var blurEffectView: UIVisualEffectView?

    let forceDarkTheme: Bool

    init(forceDarkTheme: Bool = false) {
        self.forceDarkTheme = forceDarkTheme
        super.init(frame: .zero)

        if forceDarkTheme {
            toolbar.overrideUserInterfaceStyle = .dark
        }
        addSubview(toolbar)
        toolbar.autoPinEdge(toSuperviewSafeArea: .bottom)
        toolbar.autoPinWidthToSuperview()
        toolbar.autoPinEdge(toSuperviewSafeArea: .top)
        themeChanged()
    }

    func themeChanged() {
        toolbar.tintColor = self.forceDarkTheme ? Theme.darkThemeNavbarIconColor : Theme.primaryIconColor
        if UIAccessibility.isReduceTransparencyEnabled {
            blurEffectView?.isHidden = true
            let color = self.forceDarkTheme ? Theme.darkThemeNavbarBackgroundColor : Theme.navbarBackgroundColor
            let backgroundImage = UIImage.image(color: color)
            toolbar.setBackgroundImage(backgroundImage, forToolbarPosition: .any, barMetrics: .default)
        } else {
            // Make navbar more translucent than default. Navbars remove alpha from any assigned backgroundColor, so
            // to achieve transparency, we have to assign a transparent image.
            toolbar.setBackgroundImage(UIImage.image(color: .clear), forToolbarPosition: .any, barMetrics: .default)

            let blurEffect = self.forceDarkTheme ? Theme.darkThemeBarBlurEffect : Theme.barBlurEffect

            let blurEffectView: UIVisualEffectView = {
                if let existingBlurEffectView = self.blurEffectView {
                    existingBlurEffectView.isHidden = false
                    return existingBlurEffectView
                }

                let blurEffectView = UIVisualEffectView()
                blurEffectView.isUserInteractionEnabled = false

                self.blurEffectView = blurEffectView
                insertSubview(blurEffectView, at: 0)

                blurEffectView.autoPinEdgesToSuperviewEdges()

                return blurEffectView
            }()

            blurEffectView.effect = blurEffect

            // remove hairline below bar.
            toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

            // On iOS11, despite inserting the blur at 0, other views are later inserted into the navbar behind the blur,
            // so we have to set a zindex to avoid obscuring navbar title/buttons.
            blurEffectView.layer.zPosition = -1
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
