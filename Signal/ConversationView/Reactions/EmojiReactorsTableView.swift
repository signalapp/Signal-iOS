//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class EmojiReactorsTableView: UITableView, UITableViewDataSource {
    struct ReactorItem {
        let address: SignalServiceAddress
        let displayName: String
        let emoji: String
    }

    private var reactorItems = [ReactorItem]() {
        didSet { reloadData() }
    }

    init() {
        super.init(frame: .zero, style: .plain)

        dataSource = self
        backgroundColor = .clear
        separatorStyle = .none

        register(EmojiReactorCell.self, forCellReuseIdentifier: EmojiReactorCell.reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(for reactions: [ReactionRecord], tx: DBReadTransaction) {
        let contactManager = SSKEnvironment.shared.contactManagerRef
        let recipientStore = DependenciesBridge.shared.recipientDatabaseTable
        reactorItems = reactions.map { reaction in
            let recipient = recipientStore.fetchRecipient(rowId: reaction.reactorId, tx: tx).owsFailUnwrap("must exist")
            let displayName = contactManager.displayName(for: recipient.address, tx: tx).resolvedValue()

            return ReactorItem(
                address: recipient.address,
                displayName: displayName,
                emoji: reaction.emoji,
            )
        }
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return reactorItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(EmojiReactorCell.self, for: indexPath)

        guard let item = reactorItems[safe: indexPath.row] else {
            owsFailDebug("unexpected indexPath")
            return cell
        }

        cell.backgroundColor = .clear
        cell.configure(item: item)

        return cell
    }
}

private class EmojiReactorCell: UITableViewCell, ReusableTableViewCell {
    static let reuseIdentifier = "EmojiReactorCell"

    let avatarView = ConversationAvatarView(sizeClass: .thirtySix, localUserDisplayMode: .asUser)
    let nameLabel = UILabel()
    let emojiLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        layoutMargins = UIEdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)

        contentView.addSubview(avatarView)
        avatarView.autoPinLeadingToSuperviewMargin()
        avatarView.autoVCenterInSuperview()

        contentView.addSubview(nameLabel)
        nameLabel.autoPinLeading(toTrailingEdgeOf: avatarView, offset: 8)
        nameLabel.autoPinHeightToSuperviewMargins()

        emojiLabel.font = .boldSystemFont(ofSize: 24)
        contentView.addSubview(emojiLabel)
        emojiLabel.autoPinLeading(toTrailingEdgeOf: nameLabel, offset: 8)
        emojiLabel.setContentHuggingHorizontalHigh()
        emojiLabel.autoPinHeightToSuperviewMargins()
        emojiLabel.autoPinTrailingToSuperviewMargin()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: EmojiReactorsTableView.ReactorItem) {
        nameLabel.textColor = UIColor.Signal.label

        emojiLabel.text = item.emoji

        if item.address.isLocalAddress {
            nameLabel.text = CommonStrings.you
        } else {
            nameLabel.text = item.displayName
        }

        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .address(item.address)
        }
    }
}
