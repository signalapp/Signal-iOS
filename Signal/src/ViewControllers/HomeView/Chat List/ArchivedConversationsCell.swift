//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class ArchivedConversationsCell: UITableViewCell {

    public static let reuseIdentifier = "ArchivedConversationsCell"

    private let label = UILabel()
    private let disclosureImageView = UIImageView(image: UIImage(imageLiteralResourceName: "chevron-right-20"))

    var enabled = true {
        didSet {
            if enabled {
                label.textColor = Theme.primaryTextColor
            } else {
                label.textColor = Theme.secondaryTextAndIconColor
            }
            disclosureImageView.tintColor = label.textColor
        }
    }

    // MARK: -

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func commonInit() {
        self.selectionStyle = .none

        disclosureImageView.tintColor = Theme.primaryTextColor
        disclosureImageView.setContentHuggingHigh()
        disclosureImageView.setCompressionResistanceHigh()

        label.text = OWSLocalizedString("HOME_VIEW_ARCHIVED_CONVERSATIONS",
                                       comment: "Label for 'archived conversations' button.")
        label.textAlignment = .center

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 5
        // If alignment isn't set, UIStackView uses the height of
        // disclosureImageView, even if label has a higher desired height.
        stackView.alignment = .center
        stackView.addArrangedSubview(label)
        stackView.addArrangedSubview(disclosureImageView)
        contentView.addSubview(stackView)
        stackView.autoCenterInSuperview()
        // Constrain to cell margins.
        stackView.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)
        stackView.autoPinEdge(toSuperviewMargin: .top)
        stackView.autoPinEdge(toSuperviewMargin: .bottom)

        accessibilityIdentifier = "archived_conversations"
        enabled = true
    }

    func configure(enabled: Bool) {
        OWSTableItem.configureCell(self)
        label.font = .dynamicTypeBody
        self.enabled = enabled
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(multiSelectionModeDidChange),
                                               name: MultiSelectState.multiSelectionModeDidChange,
                                               object: nil)
    }

    public override func prepareForReuse() {
        NotificationCenter.default.removeObserver(self)
        super.prepareForReuse()
    }

    @objc
    private func multiSelectionModeDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let multiSelectActive = notification.object as? Bool else {
            return
        }
        self.enabled = !multiSelectActive
    }
}
