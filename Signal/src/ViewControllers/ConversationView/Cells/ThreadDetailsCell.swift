//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSThreadDetailsCell)
public class ThreadDetailsCell: ConversationViewCell {

    // MARK: -

    @objc
    public static let cellReuseIdentifier = "ThreadDetailsCell"

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: Dependencies

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    // MARK: 

    private let avatarContainer = UIView()
    private var avatarView: ConversationAvatarImageView?
    private let avatarDiameter: CGFloat = 112

    private let titleLabel = UILabel()
    private let detailsLabel = UILabel()

    private let mutualGroupsContainer = UIView()
    private let mutualGroupsLabel = UILabel()

    let stackViewMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 28, trailing: 16)
    let stackViewSpacing: CGFloat = 3
    let avatarBottomInset: CGFloat = 7
    let mutualGroupsLabelTopInset: CGFloat = 11

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.layoutMargins = .zero
        self.contentView.layoutMargins = .zero

        avatarContainer.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: avatarBottomInset, trailing: 0)

        titleLabel.font = UIFont.ows_dynamicTypeTitle1.ows_semibold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.setContentHuggingHigh()
        titleLabel.setCompressionResistanceHigh()

        detailsLabel.font = .ows_dynamicTypeSubheadline
        detailsLabel.numberOfLines = 0
        detailsLabel.lineBreakMode = .byWordWrapping
        detailsLabel.textAlignment = .center
        detailsLabel.setContentHuggingHigh()
        detailsLabel.setCompressionResistanceHigh()

        mutualGroupsContainer.addSubview(mutualGroupsLabel)
        mutualGroupsContainer.layoutMargins = UIEdgeInsets(top: mutualGroupsLabelTopInset, leading: 0, bottom: 0, trailing: 0)
        mutualGroupsLabel.autoPinEdgesToSuperviewMargins()

        mutualGroupsLabel.font = .ows_dynamicTypeSubheadline
        mutualGroupsLabel.numberOfLines = 0
        mutualGroupsLabel.lineBreakMode = .byWordWrapping
        mutualGroupsLabel.textAlignment = .center
        mutualGroupsLabel.setContentHuggingHigh()
        mutualGroupsLabel.setCompressionResistanceHigh()

        let detailsStack = UIStackView(arrangedSubviews: [
            avatarContainer,
            titleLabel,
            detailsLabel,
            mutualGroupsContainer
        ])
        detailsStack.spacing = stackViewSpacing
        detailsStack.axis = .vertical
        detailsStack.isLayoutMarginsRelativeArrangement = true
        detailsStack.layoutMargins = stackViewMargins

        contentView.addSubview(detailsStack)
        detailsStack.autoPinEdgesToSuperviewMargins()
    }

    @objc
    public override func loadForDisplay() {
        configureAvatarView()
        configureTitleLabel()
        configureDetailsLabel()
        configureMutualGroupsLabel()

        titleLabel.textColor = Theme.primaryTextColor
        detailsLabel.textColor = Theme.secondaryTextAndIconColor
        mutualGroupsLabel.textColor = Theme.secondaryTextAndIconColor
    }

    private func configureAvatarView() {

        defer {
            avatarContainer.isHidden = avatarView?.image == nil
        }

        guard let viewItem = self.viewItem else {
            return owsFailDebug("Missing viewItem")
        }

        guard avatarView == nil else {
            self.avatarView?.updateImage()
            return
        }

        self.avatarView = ConversationAvatarImageView(
            thread: viewItem.thread,
            diameter: UInt(avatarDiameter),
            contactsManager: Environment.shared.contactsManager
        )

        avatarContainer.addSubview(avatarView!)
        avatarView?.autoSetDimension(.height, toSize: avatarDiameter)
        avatarView?.autoHCenterInSuperview()
        avatarView?.autoPinHeightToSuperviewMargins()
    }

    private func configureTitleLabel() {
        var title: String?

        defer {
            titleLabel.text = title
            titleLabel.isHidden = title == nil
        }

        guard let viewItem = self.viewItem else {
            return owsFailDebug("Missing viewItem")
        }

        switch viewItem.thread {
        case let groupThread as TSGroupThread:
            title = groupThread.groupNameOrDefault
        case let contactThread as TSContactThread:
            if contactThread.isNoteToSelf {
                title = MessageStrings.noteToSelf
            } else {
                title = Environment.shared.contactsManager.displayName(for: contactThread.contactAddress)
            }
        default:
            return owsFailDebug("interaction incorrect thread type")
        }
    }

    private func configureDetailsLabel() {
        var details: String?

        defer {
            detailsLabel.text = details
            detailsLabel.isHidden = details == nil
        }

        guard let viewItem = self.viewItem else {
            return owsFailDebug("Missing viewItem")
        }

        switch viewItem.thread {
        case let groupThread as TSGroupThread:
            let memberCount = groupThread.groupModel.groupMembers.count
            details = GroupViewUtils.formatGroupMembersLabel(memberCount: memberCount)
        case let contactThread as TSContactThread where contactThread.isNoteToSelf:
            details = NSLocalizedString("THREAD_DETAILS_NOTE_TO_SELF_EXPLANATION",
                                        comment: "Subtitle appearing at the top of the users 'note to self' conversation")
        case let contactThread as TSContactThread:
            let threadName = self.contactsManager.displayName(for: contactThread.contactAddress)
            if let phoneNumber = contactThread.contactAddress.phoneNumber, phoneNumber != threadName {
                let formattedNumber = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
                if threadName != formattedNumber {
                    details = formattedNumber
                }
            }
            if let username = viewItem.senderUsername {
                if let formattedUsername = CommonFormats.formatUsername(username), threadName != formattedUsername {
                    if let existingDetails = details {
                        details = existingDetails + "\n" + formattedUsername
                    } else {
                        details = formattedUsername
                    }
                }
            }
        default:
            return owsFailDebug("interaction incorrect thread type")
        }
    }

    private func configureMutualGroupsLabel() {
        var attributedString: NSAttributedString?

        defer {
            mutualGroupsLabel.attributedText = attributedString
            mutualGroupsContainer.isHidden = attributedString == nil
        }

        guard let viewItem = self.viewItem else {
            return owsFailDebug("Missing viewItem")
        }

        if let contactThread = viewItem.thread as? TSContactThread, contactThread.isNoteToSelf {
            return
        }

        let mutualGroupNames = viewItem.mutualGroupNames ?? []

        let formatString: String
        var groupsToInsert = mutualGroupNames
        switch mutualGroupNames.count {
        case 0:
            return
        case 1:
            formatString = NSLocalizedString(
                "THREAD_DETAILS_ONE_MUTUAL_GROUP",
                comment: "A string indicating a mutual group the user shares with this contact. Embeds {{mutual group name}}"
            )
        case 2:
            formatString = NSLocalizedString(
                "THREAD_DETAILS_TWO_MUTUAL_GROUP",
                comment: "A string indicating two mutual groups the user shares with this contact. Embeds {{mutual group name}}"
            )
        case 3:
            formatString = NSLocalizedString(
                "THREAD_DETAILS_THREE_MUTUAL_GROUP",
                comment: "A string indicating three mutual groups the user shares with this contact. Embeds {{mutual group name}}"
            )
        default:
            formatString = NSLocalizedString(
                "THREAD_DETAILS_MORE_MUTUAL_GROUP",
                comment: "A string indicating two mutual groups the user shares with this contact and that there are more unlisted. Embeds {{mutual group name}}"
            )
            groupsToInsert = Array(groupsToInsert[0...1])
        }

        var formatStringCount = formatString.components(separatedBy: "%@").count
        if formatString.count > 1 { formatStringCount -= 1 }

        guard formatStringCount == groupsToInsert.count else {
            return owsFailDebug("Incorrect number of format characters in string")
        }

        let mutableAttributedString = NSMutableAttributedString(string: formatString)

        // We don't use `String(format:)` so that we can make sure each group name is bold.
        for groupName in groupsToInsert {
            let nextInsertionPoint = (mutableAttributedString.string as NSString).range(of: "%@")
            guard nextInsertionPoint.location != NSNotFound else {
                return owsFailDebug("Unexpectedly tried to insert too many group names")
            }

            let boldGroupName = NSAttributedString(string: groupName, attributes: [.font: UIFont.ows_dynamicTypeSubheadline.ows_semibold()])
            mutableAttributedString.replaceCharacters(in: nextInsertionPoint, with: boldGroupName)
        }

        // We also need to insert the count if we're more than 3
        if mutualGroupNames.count > 3 {
            let nextInsertionPoint = (mutableAttributedString.string as NSString).range(of: "%lu")
            guard nextInsertionPoint.location != NSNotFound else {
                return owsFailDebug("Unexpectedly failed to insert more count")
            }

            mutableAttributedString.replaceCharacters(in: nextInsertionPoint, with: "\(mutualGroupNames.count - 2)")
        } else if mutableAttributedString.string.range(of: "%lu") != nil {
            return owsFailDebug("unexpected format string remaining in string")
        }

        attributedString = mutableAttributedString
    }

    @objc
    public override func cellSize() -> CGSize {
        guard let conversationStyle = self.conversationStyle else {
            owsFailDebug("Missing conversationStyle")
            return .zero
        }

        loadForDisplay()

        let viewWidth = conversationStyle.viewWidth
        var height: CGFloat = stackViewMargins.top + stackViewMargins.bottom

        func measureHeight(label: UILabel) -> CGFloat {
            return label.sizeThatFits(CGSize(
                width: viewWidth - stackViewMargins.left - stackViewMargins.right,
                height: .greatestFiniteMagnitude
            )).height
        }

        if !avatarContainer.isHidden {
            height += avatarDiameter + avatarBottomInset + stackViewSpacing
        }

        if !titleLabel.isHidden {
            height += measureHeight(label: titleLabel) + stackViewSpacing
        }

        if !detailsLabel.isHidden {
            height += measureHeight(label: detailsLabel) + stackViewSpacing
        }

        if !mutualGroupsContainer.isHidden {
            height += measureHeight(label: mutualGroupsLabel) + mutualGroupsLabelTopInset + stackViewSpacing
        }

        return CGSizeCeil(CGSize(width: viewWidth, height: height))
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        avatarView?.removeFromSuperview()
        avatarView = nil
    }
}
