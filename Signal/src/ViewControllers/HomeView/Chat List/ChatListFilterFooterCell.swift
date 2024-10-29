//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

class ChatListFilterFooterCell: UITableViewCell, ReusableTableViewCell {
    static let reuseIdentifier = "ChatListFilterFooterCell"

    private let button: ChatListFilterButton
    private let container: UIView
    private let expandedHeight: NSLayoutConstraint
    private let messageLabel: UILabel
    private let stack: UIStackView

    var isExpanded: Bool = false {
        didSet {
            setNeedsUpdateConstraints()
        }
    }

    var message: String? {
        didSet {
            if let message = message?.nilIfEmpty {
                messageLabel.isHidden = false
                messageLabel.text = message
            } else {
                messageLabel.isHidden = true
            }
        }
    }

    var primaryAction: UIAction? {
        didSet {
            if let oldValue {
                button.removeAction(oldValue, for: .primaryActionTriggered)
            }
            setNeedsUpdateConfiguration()
        }
    }

    var showsClearIcon: Bool = false {
        didSet {
            if showsClearIcon != oldValue {
                setNeedsUpdateConfiguration()
            }
        }
    }

    var title: String? {
        didSet {
            setNeedsUpdateConfiguration()
        }
    }

    override init(style: CellStyle, reuseIdentifier: String?) {
        button = ChatListFilterButton()
        container = UIView()
        container.preservesSuperviewLayoutMargins = true
        container.translatesAutoresizingMaskIntoConstraints = false
        messageLabel = UILabel()
        messageLabel.font = .preferredFont(forTextStyle: .callout)
        messageLabel.isHidden = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        stack = UIStackView(arrangedSubviews: [messageLabel, button])
        stack.alignment = .center
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.preservesSuperviewLayoutMargins = true
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        stack.autoPinHorizontalEdges(toEdgesOf: container)
        stack.autoVCenterInSuperview()
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 40),
            container.bottomAnchor.constraint(greaterThanOrEqualTo: stack.bottomAnchor, constant: 40),
        ])
        expandedHeight = container.heightAnchor.constraint(equalToConstant: 0)
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        maximumContentSizeCategory = .extraExtraExtraLarge

        // Disable background highlighting.
        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .systemBackground
        self.backgroundConfiguration = backgroundConfiguration

        contentView.addSubview(container)
        container.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)

        if let primaryAction {
            button.addAction(primaryAction, for: .primaryActionTriggered)
        }

        button.configuration?.title = title ?? primaryAction?.title
        button.showsClearIcon = showsClearIcon
    }

    override func updateConstraints() {
        super.updateConstraints()

        expandedHeight.constant = traitCollection.verticalSizeClass == .compact ? 240 : 600
        expandedHeight.isActive = isExpanded
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass {
            setNeedsUpdateConstraints()
        }
    }
}
