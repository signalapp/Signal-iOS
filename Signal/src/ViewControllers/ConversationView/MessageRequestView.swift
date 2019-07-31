//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
protocol MessageRequestDelegate: class {
    func messageRequestViewDidTapBlock()
    func messageRequestViewDidTapDelete()
    func messageRequestViewDidTapAccept()
    func messageRequestViewDidTapLearnMore()
}

@objc
class MessageRequestView: UIStackView {
    var contactManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    let thread: TSThread

    @objc
    weak var delegate: MessageRequestDelegate?

    @objc
    init(thread: TSThread) {
        self.thread = thread

        super.init(frame: .zero)

        var hasSentMessages = false
        databaseStorage.uiRead { transaction in
            guard let threadUniqueId = thread.uniqueId else {
                return owsFailDebug("unexpectedly missing thread id")
            }
            hasSentMessages = InteractionFinder(threadUniqueId: threadUniqueId).existsOutgoingMessage(transaction: transaction)
        }

        // We want the background to extend to the bottom of the screen
        // behind the safe area, so we add that inset to our bottom inset
        // instead of pinning this view to the safe area
        let safeAreaInset: CGFloat
        if #available(iOS 11, *) {
            safeAreaInset = safeAreaInsets.bottom
        } else {
            safeAreaInset = 0
        }

        autoresizingMask = .flexibleHeight

        axis = .vertical
        spacing = 11
        layoutMargins = UIEdgeInsets(top: 0, leading: 16, bottom: 20 + safeAreaInset, trailing: 16)
        isLayoutMarginsRelativeArrangement = true

        let backgroundView = UIView()
        backgroundView.backgroundColor = Theme.backgroundColor
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        addArrangedSubview(preparePrompt(hasSentMessages: hasSentMessages))
        addArrangedSubview(prepareButtons(hasSentMessages: hasSentMessages))
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return .zero
    }

    func preparePrompt(hasSentMessages: Bool) -> UILabel {
        let promptString: String
        var boldRange: NSRange

        if let thread = thread as? TSGroupThread {
            let formatString: String
            if hasSentMessages {
                formatString = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_EXISTING_GROUP_PROMPT_FORMAT",
                    comment: "A prompt notifying that the user must share their profile with this group. Embeds {{group name}}."
                )
            } else {
                formatString = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT_FORMAT",
                    comment: "A prompt asking if the user wants to accept a group invite. Embeds {{group name}}."
                )
            }

            // Get the range of the formatter marker to calculate the start of the bold area
            boldRange = (formatString as NSString).range(of: "%@")
            let groupName = thread.groupNameOrDefault

            // Update the length of the range to reflect the length of the string that will be inserted
            boldRange.length = groupName.count

            promptString = String(format: formatString, groupName)
        } else if let thread = thread as? TSContactThread {
            let formatString: String
            if hasSentMessages {
                formatString = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_EXISTING_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt notifying that the user must share their profile with this conversation. Embeds {{contact name}}."
                )
            } else {
                formatString = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_NEW_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt asking if the user wants to accept a conversation invite. Embeds {{contact name}}."
                )
            }

            // Get the range of the formatter marker to calculate the start of the bold area
            boldRange = (formatString as NSString).range(of: "%@")
            let displayName = contactManager.displayName(for: thread.contactAddress)

            // Update the length of the range to reflect the length of the string that will be inserted
            boldRange.length = displayName.count

            promptString = String(format: formatString, displayName)
        } else {
            owsFailDebug("unexpected thread type")
            return UILabel()
        }

        let attributedString = NSMutableAttributedString(
            string: promptString,
            attributes: [
                .font: UIFont.ows_dynamicTypeSubheadlineClamped,
                .foregroundColor: Theme.secondaryColor
            ]
        )
        attributedString.addAttributes([.font: UIFont.ows_dynamicTypeSubheadlineClamped.ows_semiBold()], range: boldRange)

        let label = UILabel()
        label.attributedText = attributedString
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    func prepareButtons(hasSentMessages: Bool) -> UIStackView {
        let buttonsStack = UIStackView()
        buttonsStack.spacing = 8
        buttonsStack.distribution = .fillEqually

        if hasSentMessages {
            let learnMoreButton = prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_LEARN_MORE_BUTTON",
                                                                            comment: "A button used to learn more about why you must share your profile."),
                                                   titleColor: Theme.secondaryColor) { [weak self] in
                                                    self?.delegate?.messageRequestViewDidTapLearnMore()
            }
            buttonsStack.addArrangedSubview(learnMoreButton)

            let shareProfileButton = prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_SHARE_PROFILE_BUTTON",
                                                                     comment: "A button used to share your profile with an existing thread."),
                                            titleColor: .ows_signalBlue) { [weak self] in
                                                // This is the same action as accepting the message request, but displays
                                                // with slightly different visuals if the user has already been messaging
                                                // this user in the past but didn't share their profile.
                                                self?.delegate?.messageRequestViewDidTapAccept()
            }
            buttonsStack.addArrangedSubview(shareProfileButton)
        } else {
            let blockButton = prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
                                                                     comment: "A button used to block a user on an incoming message request."),
                                            titleColor: .ows_red) { [weak self] in
                                                self?.delegate?.messageRequestViewDidTapBlock()
            }
            buttonsStack.addArrangedSubview(blockButton)

            let deleteButton = prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
                                                                      comment: "A button used to block a user on an incoming message request."),
                                             titleColor: .ows_red) { [weak self] in
                                                self?.delegate?.messageRequestViewDidTapDelete()
            }
            buttonsStack.addArrangedSubview(deleteButton)

            let acceptButton = prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_ACCEPT_BUTTON",
                                                                      comment: "A button used to block a user on an incoming message request."),
                                             titleColor: .ows_signalBlue) { [weak self] in
                                                self?.delegate?.messageRequestViewDidTapAccept()
            }
            buttonsStack.addArrangedSubview(acceptButton)
        }

        return buttonsStack
    }

    func prepareButton(title: String, titleColor: UIColor, touchHandler: @escaping () -> Void) -> OWSFlatButton {
        let flatButton = OWSFlatButton()
        flatButton.setTitle(title: title, font: UIFont.ows_dynamicTypeBodyClamped.ows_semiBold(), titleColor: titleColor)
        flatButton.setBackgroundColors(upColor: Theme.isDarkThemeEnabled ? UIColor.ows_gray75 : UIColor.ows_gray05)
        flatButton.setPressedBlock(touchHandler)
        flatButton.useDefaultCornerRadius()
        flatButton.autoSetDimension(.height, toSize: 48)
        return flatButton
    }
}
