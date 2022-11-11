//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class OWSWindow: UIWindow {
    public override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .ThemeDidChange,
            object: nil
        )

        applyTheme()
    }

    // This useless override is defined so that you can call `-init` from Swift.
    @available(iOS 13, *)
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
        guard #available(iOS 13, *) else { return }

        // Ensure system UI elements use the appropriate styling for the selected theme.
        switch Theme.getOrFetchCurrentTheme() {
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

        guard #available(iOS 13, *) else { return }

        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            Theme.systemThemeChanged()
        }
    }
}
