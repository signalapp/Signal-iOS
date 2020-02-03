//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class EmojiReactorsTableView: UITableView {
    private var reactorItems = [(thread: TSContactThread, displayName: String, profileName: String?, emoji: String?)]() {
        didSet { reloadData() }
    }

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

    func configureForAll(transaction: SDSAnyReadTransaction) {
        reactorItems = finder.allReactions(transaction: transaction).compactMap { reaction in
            guard let thread = TSContactThread.getWithContactAddress(reaction.reactor, transaction: transaction) else {
                owsFailDebug("unexpectedly missing thread for address: \(reaction.reactor)")
                return nil
            }

            let displayName = contactsManager.displayName(for: thread, transaction: transaction)

            let profileName: String?
            if FeatureFlags.profileDisplayChanges || contactsManager.hasNameInSystemContacts(for: reaction.reactor) {
                profileName = nil
            } else {
                profileName = contactsManager.formattedProfileName(for: reaction.reactor, transaction: transaction)
            }

            return (thread: thread, displayName: displayName, profileName: profileName, emoji: reaction.emoji)
        }
    }

    func configure(for emoji: String?, transaction: SDSAnyReadTransaction) {
        guard let emoji = emoji else { return configureForAll(transaction: transaction) }
        reactorItems = finder.reactors(for: emoji, transaction: transaction).compactMap { address in
            guard let thread = TSContactThread.getWithContactAddress(address, transaction: transaction) else {
                owsFailDebug("unexpectedly missing thread for address: \(address)")
                return nil
            }

            let displayName = contactsManager.displayName(for: thread, transaction: transaction)

            let profileName: String?
            if FeatureFlags.profileDisplayChanges || contactsManager.hasNameInSystemContacts(for: address) {
                profileName = nil
            } else {
                profileName = contactsManager.formattedProfileName(for: address, transaction: transaction)
            }

            return (thread: thread, displayName: displayName, profileName: profileName, emoji: emoji)
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

        guard let (thread, displayName, profileName, emoji) = reactorItems[safe: indexPath.row] else {
            owsFailDebug("unexpected indexPath")
            return cell
        }

        contactCell.backgroundColor = .clear
        contactCell.configure(thread: thread, displayName: displayName, profileName: profileName, emoji: emoji)

        return contactCell
    }
}

private class EmojiReactorCell: UITableViewCell {
    static let reuseIdentifier = "EmojiReactorCell"

    let avatarView = AvatarImageView()
    let avatarDiameter: CGFloat = 36
    let nameLabel = UILabel()
    let profileLabel = UILabel()
    let emojiLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .none

        layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        contentView.addSubview(avatarView)
        avatarView.autoPinLeadingToSuperviewMargin()
        avatarView.autoPinHeightToSuperviewMargins()
        avatarView.autoSetDimensions(to: CGSize(square: avatarDiameter))

        let labelStackView = UIStackView()
        labelStackView.axis = .vertical
        contentView.addSubview(labelStackView)
        labelStackView.autoPinLeading(toTrailingEdgeOf: avatarView, offset: 8)
        labelStackView.autoPinHeightToSuperviewMargins()

        nameLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold()
        nameLabel.textColor = Theme.primaryTextColor
        labelStackView.addArrangedSubview(nameLabel)

        profileLabel.font = .ows_dynamicTypeCaption1Clamped
        profileLabel.textColor = Theme.secondaryTextAndIconColor
        labelStackView.addArrangedSubview(profileLabel)

        emojiLabel.font = .boldSystemFont(ofSize: 28)
        contentView.addSubview(emojiLabel)
        emojiLabel.autoPinLeading(toTrailingEdgeOf: labelStackView, offset: 8)
        emojiLabel.setContentHuggingHorizontalHigh()
        emojiLabel.autoPinHeightToSuperviewMargins()
        emojiLabel.autoPinTrailingToSuperviewMargin()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(thread: TSContactThread, displayName: String, profileName: String?, emoji: String?) {

        let avatarBuilder = OWSContactAvatarBuilder(
            address: thread.contactAddress,
            colorName: thread.conversationColorName,
            diameter: UInt(avatarDiameter)
        )

        emojiLabel.text = emoji

        if thread.contactAddress.isLocalAddress {
            nameLabel.text = String(format: NSLocalizedString(
                "LOCAL_REACTOR_INDICATOR_FORMAT",
                comment: "Prepends text indicating that the embedded name is associated with the local user. Embeds {{local name}}"
            ), displayName)
            avatarView.image = OWSProfileManager.shared().localProfileAvatarImage() ?? avatarBuilder.buildDefaultImage()
            profileLabel.isHidden = true
        } else {
            nameLabel.text = displayName
            avatarView.image = avatarBuilder.build()
            profileLabel.text = profileName
            profileLabel.isHidden = profileName == nil
        }
    }
}
