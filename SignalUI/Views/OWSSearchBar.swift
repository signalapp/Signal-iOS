//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public class OWSSearchBar: UISearchBar {

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // MARK: -

    public var searchFieldBackgroundColorOverride: UIColor? {
        didSet {
            applyTheme()
        }
    }

    private func configure() {
        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .themeDidChange, object: nil)
    }

    // MARK: Theme

    public static func applyTheme(to searchBar: UISearchBar) {
        AssertIsOnMainThread()

        searchBar.tintColor = Theme.secondaryTextAndIconColor
        searchBar.barStyle = Theme.barStyle
        searchBar.barTintColor = Theme.backgroundColor

        // Hide searchBar border.
        // Alternatively we could hide the border by using `UISearchBarStyleMinimal`, but that causes an issue when toggling
        // from light -> dark -> light theme wherein the textField background color appears darker than it should
        // (regardless of our re-setting textfield.backgroundColor below).
        searchBar.backgroundImage = UIImage()

        if Theme.isDarkThemeEnabled {
            let foregroundColor = Theme.secondaryTextAndIconColor

            let clearImage = UIImage(imageLiteralResourceName: "x-circle-fill")
            searchBar.setImage(
                clearImage.asTintedImage(color: foregroundColor),
                for: .clear,
                state: .normal
            )

            let searchImage = UIImage(imageLiteralResourceName: "search")
            searchBar.setImage(
                searchImage.asTintedImage(color: foregroundColor),
                for: .search,
                state: .normal
            )
        } else {
            searchBar.setImage(nil, for: .clear, state: .normal)
            searchBar.setImage(nil, for: .search, state: .normal)
        }

        let searchFieldBackgroundColor: UIColor
        if let owsSearchBar = searchBar as? OWSSearchBar, let colorOverride = owsSearchBar.searchFieldBackgroundColorOverride {
            searchFieldBackgroundColor = colorOverride
        } else {
            searchFieldBackgroundColor = Theme.searchFieldBackgroundColor
        }

        searchBar.traverseHierarchyDownward { view in
            guard let textField = view as? UITextField else { return }
            textField.backgroundColor = searchFieldBackgroundColor
            textField.textColor = Theme.primaryTextColor
            textField.keyboardAppearance = Theme.keyboardAppearance
        }
    }

    private func applyTheme() {
        Self.applyTheme(to: self)
    }

    @objc
    private func themeDidChange(_ notification: Notification) {
        AssertIsOnMainThread()
        applyTheme()
    }
}
