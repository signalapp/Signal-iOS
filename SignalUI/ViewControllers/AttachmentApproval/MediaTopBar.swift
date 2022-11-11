//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

open class MediaTopBar: UIView {

    // Custom layout guide is necessary to allow to adjust the top margin.
    // Usually one could just change layoutMargins.top but that approach
    // sometimes doesn't work for this view because top inset gets overridden by UIKit
    // since `preservesSuperviewLayoutMargins` is set to `true`.
    public let controlsLayoutGuide = UILayoutGuide()
    private lazy var controlsLayoutGuideTop: NSLayoutConstraint = {
        controlsLayoutGuide.topAnchor.constraint(equalTo: topAnchor)
    }()
    private lazy var controlsLayoutGuideLeading: NSLayoutConstraint = {
        controlsLayoutGuide.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor)
    }()
    private lazy var controlsLayoutGuideTrailing: NSLayoutConstraint = {
        controlsLayoutGuide.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
    }()

    override public init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .zero
        preservesSuperviewLayoutMargins = true

        installConstraints()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installConstraints() {
        addLayoutGuide(controlsLayoutGuide)
        controlsLayoutGuideTop.isActive = true
        controlsLayoutGuideLeading.isActive = true
        controlsLayoutGuideTrailing.isActive = true
        controlsLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    public override func updateConstraints() {
        super.updateConstraints()

        let isIPadUIInRegularMode = traitCollection.horizontalSizeClass == .regular && traitCollection.verticalSizeClass == .regular
        let horizontalMargin: CGFloat = isIPadUIInRegularMode ? 12 : 0
        let topMargin: CGFloat = {
            // Unnecessary, but looks better with some more padding on iPad screens.
            if isIPadUIInRegularMode {
                return 10
            }
            // iPhones in landscape mode.
            if traitCollection.verticalSizeClass == .compact {
                return 0
            }
            // iPhones with a screen notch, iPads in windowed mode.
            if UIDevice.current.hasIPhoneXNotch || UIDevice.current.isIPad {
                return 4
            }
            // iPhones with a home button have their status bar hidden (safeArea.top == 0)
            // so it's necessary to add some padding manually.
            return 16
        }()
        controlsLayoutGuideLeading.constant = horizontalMargin
        controlsLayoutGuideTrailing.constant = -horizontalMargin
        controlsLayoutGuideTop.constant = topMargin
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsUpdateConstraints()
    }

    public func install(in view: UIView) {
        view.addSubview(self)
        autoPinWidthToSuperview()
        autoPinEdge(toSuperviewSafeArea: .top)
    }
}
