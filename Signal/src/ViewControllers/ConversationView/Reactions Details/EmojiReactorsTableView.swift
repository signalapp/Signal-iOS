//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

class EmojiReactorsTableView: UITableView {
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
        backgroundColor = Theme.actionSheetBackgroundColor
        separatorStyle = .none

        register(EmojiReactorCell.self, forCellReuseIdentifier: EmojiReactorCell.reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(for reactions: [OWSReaction], transaction: SDSAnyReadTransaction) {
        reactorItems = reactions.compactMap { reaction in
            let displayName = contactsManager.displayName(for: reaction.reactor, transaction: transaction)

            return ReactorItem(
                address: reaction.reactor,
                displayName: displayName,
                emoji: reaction.emoji
            )
        }
    }
}

extension EmojiReactorsTableView: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return reactorItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: EmojiReactorCell.reuseIdentifier, for: indexPath)
        guard let contactCell = cell as? EmojiReactorCell else {
            owsFailDebug("unexpected cell type")
            return cell
        }

        guard let item = reactorItems[safe: indexPath.row] else {
            owsFailDebug("unexpected indexPath")
            return cell
        }

        contactCell.backgroundColor = .clear
        contactCell.configure(item: item)

        return contactCell
    }
}

private class EmojiReactorCell: UITableViewCell {
    static let reuseIdentifier = "EmojiReactorCell"

    let avatarView = ConversationAvatarView(sizeClass: .thirtySix, localUserDisplayMode: .asUser)
    let nameLabel = UILabel()
    let emojiLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

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

        nameLabel.textColor = Theme.primaryTextColor

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
