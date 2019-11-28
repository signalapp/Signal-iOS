//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

class EmojiReactorsTableView: UITableView {
    private var reactorItems = [(thread: TSContactThread, displayName: String)]()

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    let finder: ReactionFinder
    init(finder: ReactionFinder) {
        self.finder = finder
        super.init(frame: .zero, style: .plain)

        dataSource = self
        backgroundColor = Theme.reactionBackgroundColor
        separatorStyle = .none

        register(EmojiReactorCell.self, forCellReuseIdentifier: EmojiReactorCell.reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(for emoji: String?, transaction: SDSAnyReadTransaction) {
        defer { reloadData() }
        guard let emoji = emoji else {
            reactorItems = []
            return
        }
        reactorItems = finder.reactors(for: emoji, transaction: transaction).compactMap { address in
            guard let thread = TSContactThread.getWithContactAddress(address, transaction: transaction) else {
                owsFailDebug("unexpectedly missing thread for address: \(address)")
                return nil
            }
            return (
                thread: thread,
                displayName: contactsManager.displayName(for: thread, transaction: transaction)
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

        guard let (thread, displayName) = reactorItems[safe: indexPath.row] else {
            owsFailDebug("unexpected indexPath")
            return cell
        }

        contactCell.backgroundColor = .clear
        contactCell.configure(thread: thread, displayName: displayName)

        return contactCell
    }
}

private class EmojiReactorCell: UITableViewCell {
    static let reuseIdentifier = "EmojiReactorCell"

    let avatarView = AvatarImageView()
    let avatarDiameter: CGFloat = 36
    let nameLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        contentView.addSubview(avatarView)
        avatarView.autoPinLeadingToSuperviewMargin()
        avatarView.autoPinHeightToSuperviewMargins()
        avatarView.autoSetDimensions(to: CGSize(square: avatarDiameter))

        nameLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold()
        nameLabel.textColor = Theme.primaryTextColor
        contentView.addSubview(nameLabel)
        nameLabel.autoPinTrailingToSuperviewMargin()
        nameLabel.autoPinLeading(toTrailingEdgeOf: avatarView, offset: 8)
        nameLabel.autoAlignAxis(.horizontal, toSameAxisOf: avatarView)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(thread: TSContactThread, displayName: String) {

        let avatarBuilder = OWSContactAvatarBuilder(
            address: thread.contactAddress,
            colorName: thread.conversationColorName,
            diameter: UInt(avatarDiameter)
        )

        if thread.contactAddress.isLocalAddress {
            nameLabel.text = String(format: NSLocalizedString(
                "LOCAL_REACTOR_INDICATOR_FORMAT",
                comment: "Prepends text indicating that the embedded name is associated with the local user. Embeds {{local name}}"
            ), displayName)
            avatarView.image = OWSProfileManager.shared().localProfileAvatarImage() ?? avatarBuilder.buildDefaultImage()
        } else {
            nameLabel.text = displayName
            avatarView.image = avatarBuilder.build()
        }
    }
}
