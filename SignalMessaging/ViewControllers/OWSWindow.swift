//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class OWSWindow: UIWindow {
    public override init(frame: CGRect) {
        super.init(frame: frame)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: NSNotification.Name.ThemeDidChange,
            object: nil
        )

        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func themeDidChange() {
        applyTheme()
    }

    private func applyTheme() {
        guard #available(iOS 13, *) else { return }

        // Ensure system UI elements use the appropriate styling for the selected theme.
        overrideUserInterfaceStyle = Theme.isDarkThemeEnabled ? .dark : .light
    }
}
