//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension UsernameSelectionViewController {
    class HeaderView: UIView {

        // MARK: Init

        private let iconSize: CGFloat

        init(withIconSize iconSize: CGFloat) {
            self.iconSize = iconSize

            super.init(frame: .zero)

            addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            updateFontsForCurrentPreferredContentSize()
            setColorsForCurrentTheme()
        }

        @available(*, unavailable, message: "Use other initializer!")
        required init?(coder: NSCoder) {
            fatalError("Use other initializer!")
        }

        private let iconImage: UIImage = Theme.iconImage(.settingsMention)

        // MARK: Views

        private lazy var iconImageView: UIImageView = {
            UIImageView(image: iconImage)
        }()

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

            return label
        }()

        private lazy var stackView: OWSStackView = {
            let stack = OWSStackView(
                name: "Username Selection Header Stack",
                arrangedSubviews: [
                    iconView,
                    usernameDisplayLabel
                ]
            )

            stack.axis = .vertical
            stack.alignment = .center
            stack.distribution = .equalSpacing
            stack.spacing = 16

            return stack
        }()

        // MARK: - Configure views

        func updateFontsForCurrentPreferredContentSize() {
            usernameDisplayLabel.font = .ows_dynamicTypeSubheadlineClamped
        }

        func setColorsForCurrentTheme() {
            iconImageView.image = iconImage
                .tintedImage(color: Theme.isDarkThemeEnabled ? .ows_gray02 : .ows_gray90)

            iconView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white

            usernameDisplayLabel.textColor = Theme.secondaryTextAndIconColor
        }

        func setUsernameText(to text: String) {
            usernameDisplayLabel.text = text
        }
    }
}
