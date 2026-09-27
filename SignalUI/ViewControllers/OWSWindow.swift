//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

public class OWSWindow: UIWindow {
    override public init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        commonInit()
    }

    @available(*, unavailable, message: "Must use windowScene init!")
    override init(frame: CGRect) {
        owsFail("Not implemented!")
    }

    @available(*, unavailable, message: "Must use windowScene init!")
    required init?(coder: NSCoder) {
        owsFail("Not implemented!")
    }

    private func commonInit() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil,
        )

        applyTheme()
    }

    @objc
    private func themeDidChange() {
        applyTheme()
    }

    private func applyTheme() {
        // Ensure system UI elements use the appropriate styling for the selected theme.
        switch Theme.getOrFetchCurrentMode() {
        case .light:
            overrideUserInterfaceStyle = .light
        case .dark:
            overrideUserInterfaceStyle = .dark
        case .system:
            overrideUserInterfaceStyle = .unspecified
        }
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            Theme.systemThemeChanged()
        }
    }
}
