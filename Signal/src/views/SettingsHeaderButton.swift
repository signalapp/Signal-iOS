//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import UIKit

class SettingsHeaderButton: UIView {

    private let button = UIButton(configuration: .gray())
    private let titleLabel = UILabel()
    private let stackView = UIStackView()

    init(title: String, icon: ThemeIcon, actionHandler: (() -> Void)? = nil) {
        super.init(frame: .zero)

        // Stack View
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .center
        addSubview(stackView)
        stackView.addArrangedSubviews([button, titleLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Button
        button.configuration?.image = UIImage(named: Theme.iconName(icon))
        button.configuration?.imageColorTransformer = UIConfigurationColorTransformer({ _ in
            return .Signal.label
        })
        button.configuration?.contentInsets = .init(top: 13, leading: 26, bottom: 13, trailing: 26)
        button.configuration?.cornerStyle = .capsule
        updateButtonBackgroundColorTransformer()

        if let buttonConfiguration = button.configuration, let imageSize = buttonConfiguration.image?.size {
            let buttonWidth = imageSize.width + buttonConfiguration.contentInsets.leading + buttonConfiguration.contentInsets.trailing
            let buttonHeight = imageSize.height + buttonConfiguration.contentInsets.top + buttonConfiguration.contentInsets.bottom
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: buttonWidth),
                button.heightAnchor.constraint(equalToConstant: buttonHeight),
            ])
        }

        titleLabel.attributedText = title.styled(
            with: .color(UIColor.Signal.label),
            .alignment(.center),
            .font(.dynamicTypeFootnoteClamped),
            // Since this usually one word and is space-constrained,
            // try to hyphenate when line wrapping.
            .hyphenationFactor(1),
        )
        titleLabel.numberOfLines = 0

        // Action
        if let actionHandler {
            addActionHandler(actionHandler)
        }

        // Accessibility
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func addActionHandler(_ handler: @escaping () -> Void) {
        button.addAction(UIAction { _ in handler() }, for: .primaryActionTriggered)
    }

    var minimumWidth: CGFloat {
        return intrinsicContentSize.width
    }

    // MARK: - Properties

    var menu: UIMenu? {
        get {
            return button.menu
        }
        set {
            button.menu = newValue
            button.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    var buttonBackgroundColor: UIColor = Theme.tableCell2BackgroundColor {
        didSet {
            updateButtonBackgroundColorTransformer()
        }
    }

    var selectedButtonBackgroundColor: UIColor = Theme.tableCell2SelectedBackgroundColor {
        didSet {
            updateButtonBackgroundColorTransformer()
        }
    }

    private func updateButtonBackgroundColorTransformer() {
        button.configuration?.background.backgroundColorTransformer = UIConfigurationColorTransformer { [weak self] _ in
            guard let self else { return .Signal.background }
            if self.button.isHighlighted {
                return self.selectedButtonBackgroundColor
            }
            return self.buttonBackgroundColor
        }
    }

    var isEnabled: Bool {
        get {
            button.isEnabled
        }
        set {
            button.isEnabled = newValue
        }
    }

    // MARK: Accessibility

    override func accessibilityActivate() -> Bool {
        if #available(iOS 17.4, *) {
            button.performPrimaryAction()
        } else {
            button.sendActions(for: .touchUpInside)
        }
        return true
    }

}
