//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

extension UsernameSelectionViewController {
    class HeaderView: UIView {

        // MARK: Init

        private let iconSize: CGFloat

        init(withIconSize iconSize: CGFloat) {
            self.iconSize = iconSize

            super.init(frame: .zero)

            layoutMargins = UIEdgeInsets(top: 34, leading: 32, bottom: 24, trailing: 32)

            addSubview(iconView)
            addSubview(usernameDisplayLabel)

            iconView.autoPinTopToSuperviewMargin()
            iconView.autoHCenterInSuperview()

            iconView.autoPinEdge(.bottom, to: .top, of: usernameDisplayLabel, withOffset: -16)

            usernameDisplayLabel.autoPinLeadingToSuperviewMargin()
            usernameDisplayLabel.autoPinTrailingToSuperviewMargin()
            usernameDisplayLabel.autoPinBottomToSuperviewMargin()

            updateFontsForCurrentPreferredContentSize()
            setColorsForCurrentTheme()
        }

        @available(*, unavailable, message: "Use other initializer!")
        required init?(coder: NSCoder) {
            fatalError("Use other initializer!")
        }

        // MARK: Views

        private lazy var iconImageView = UIImageView(image: UIImage(imageLiteralResourceName: "at-display-bold"))

        /// Displays an icon over a circular, square-aspect-ratio, colored
        /// background.
        private lazy var iconView: UIView = {
            let backgroundView = UIView()
            backgroundView.layer.masksToBounds = true
            backgroundView.layer.cornerRadius = iconSize / 2

            backgroundView.autoPinToSquareAspectRatio()
            backgroundView.autoSetDimension(.height, toSize: iconSize)

            backgroundView.addSubview(iconImageView)
            iconImageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(margin: iconSize / 4))

            return backgroundView
        }()

        /// Displays the user-entered username along with the discriminator.
        private lazy var usernameDisplayLabel: UILabel = {
            let label = UILabel()

            label.numberOfLines = 0
            label.textAlignment = .center

            return label
        }()

        // MARK: - Configure views

        func updateFontsForCurrentPreferredContentSize() {
            usernameDisplayLabel.font = .dynamicTypeSubheadlineClamped
        }

        func setColorsForCurrentTheme() {
            iconImageView.tintColor = Theme.isDarkThemeEnabled ? .ows_gray02 : .ows_gray90

            iconView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white

            usernameDisplayLabel.textColor = Theme.secondaryTextAndIconColor
        }

        func setUsernameText(to text: String) {
            usernameDisplayLabel.text = text
        }
    }
}
