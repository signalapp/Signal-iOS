//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

@objc
public class OWSWindow: UIWindow {
    public override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )

        applyTheme()
    }

    // This useless override is defined so that you can call `-init` from Swift.
    public override init(windowScene: UIWindowScene) {
        fatalError("init(windowScene:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            Theme.systemThemeChanged()
        }
    }
}
