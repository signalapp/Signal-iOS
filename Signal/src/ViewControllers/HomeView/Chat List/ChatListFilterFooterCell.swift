//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

class ChatListFilterFooterCell: UITableViewCell, ReusableTableViewCell {
    static let reuseIdentifier = "ChatListFilterFooterCell"

    private let button: ChatListFilterButton

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
        button.translatesAutoresizingMaskIntoConstraints = false
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = .clear()
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
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
}
