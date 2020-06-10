//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
protocol MessageRequestDelegate: class {
    func messageRequestViewDidTapBlock(mode: MessageRequestMode)
    func messageRequestViewDidTapDelete()
    func messageRequestViewDidTapAccept(mode: MessageRequestMode)
    func messageRequestViewDidTapUnblock(mode: MessageRequestMode)
    func messageRequestViewDidTapLearnMore()
}

// MARK: -

@objc
public enum MessageRequestMode: UInt {
    case none
    case contactOrGroupV1
    case groupV2
}

// MARK: -

@objc
class MessageRequestView: UIStackView {

    // MARK: - Dependencies

    private var contactManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: -

    private let thread: TSThread
    private let mode: MessageRequestMode

    @objc
    weak var delegate: MessageRequestDelegate?

    @objc
    init(thread: TSThread) {
        self.thread = thread
        self.mode = thread.isGroupV2Thread ? .groupV2 : .contactOrGroupV1

        super.init(frame: .zero)

        // TODO: Does this apply to the group invite path?
        let isThreadBlocked = OWSBlockingManager.shared().isThreadBlocked(thread)

        // We want the background to extend to the bottom of the screen
        // behind the safe area, so we add that inset to our bottom inset
        // instead of pinning this view to the safe area
        let safeAreaInset = safeAreaInsets.bottom

        autoresizingMask = .flexibleHeight

        axis = .vertical
        spacing = 11
        layoutMargins = UIEdgeInsets(top: 16, leading: 16, bottom: 20 + safeAreaInset, trailing: 16)
        isLayoutMarginsRelativeArrangement = true

        let backgroundView = UIView()
        backgroundView.backgroundColor = Theme.backgroundColor
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()

        switch mode {
        case .none:
            owsFailDebug("Invalid mode.")
        case .contactOrGroupV1:
            var hasSentMessages = false
            databaseStorage.uiRead { transaction in
        hasSentMessages = InteractionFinder(threadUniqueId: thread.uniqueId).existsOutgoingMessage(transaction: transaction)
            }
        // If phone number privacy feature is not enabled, we expect this
        // flow to never be hit when hasSentMessages would be false unless
        // the thread has been blocked.
        assert(!hasSentMessages || isThreadBlocked || FeatureFlags.phoneNumberPrivacy)

            addArrangedSubview(prepareContactOrGroupV1Prompt(hasSentMessages: hasSentMessages,
        isThreadBlocked: isThreadBlocked))
            addArrangedSubview(prepareContactOrGroupV1Buttons(hasSentMessages: hasSentMessages,
        isThreadBlocked: isThreadBlocked))
        case .groupV2:
            addArrangedSubview(prepareGroupV2Prompt())
            addArrangedSubview(prepareGroupV2Buttons())
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return .zero
    }

    // MARK: - Contact or Group V1

    func prepareContactOrGroupV1Prompt(hasSentMessages: Bool, isThreadBlocked: Bool) -> UILabel {
        if thread.isGroupThread {
            let string: String
            if isThreadBlocked {
                string = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_BLOCKED_GROUP_PROMPT",
                    comment: "A prompt notifying that the user must unblock this group to continue."
                )
            } else if hasSentMessages {
                string = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_EXISTING_GROUP_PROMPT",
                    comment: "A prompt notifying that the user must share their profile with this group."
                )
            } else {
                string = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT",
                    comment: "A prompt asking if the user wants to accept a group invite."
                )
            }

            return prepareLabel(attributedString: NSAttributedString(string: string, attributes: [
                .font: UIFont.ows_dynamicTypeSubheadlineClamped,
                .foregroundColor: Theme.secondaryTextAndIconColor
            ]))
        } else if let thread = thread as? TSContactThread {
            let formatString: String

            if isThreadBlocked {
                formatString = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_BLOCKED_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt notifying that the user must unblock this conversation to continue. Embeds {{contact name}}."
                )
            } else if hasSentMessages {
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

            let shortName = databaseStorage.uiRead { transaction in
                return self.contactManager.shortDisplayName(for: thread.contactAddress, transaction: transaction)
            }

            return preparePromptLabel(formatString: formatString, embeddedString: shortName)
        } else {
            owsFailDebug("unexpected thread type")
            return UILabel()
        }
    }

    func prepareContactOrGroupV1Buttons(hasSentMessages: Bool, isThreadBlocked: Bool) -> UIStackView {
        let mode = self.mode
        var buttons = [UIView]()

        if isThreadBlocked {
            buttons = [
                prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
                                                       comment: "incoming message request button text which deletes a conversation"),
                              titleColor: .ows_accentRed) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapDelete()
                },
                prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_UNBLOCK_BUTTON",
                                                       comment: "A button used to unlock a blocked conversation."),
                              titleColor: Theme.accentBlueColor) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapUnblock(mode: mode)
                }]
        } else if hasSentMessages {
            buttons = [
                prepareButton(title: CommonStrings.learnMore,
                              titleColor: Theme.secondaryTextAndIconColor) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapLearnMore()
                },
                prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_SHARE_PROFILE_BUTTON",
                                                       comment: "A button used to share your profile with an existing thread."),
                              titleColor: Theme.accentBlueColor) { [weak self] in
                                // This is the same action as accepting the message request, but displays
                                // with slightly different visuals if the user has already been messaging
                                // this user in the past but didn't share their profile.
                                self?.delegate?.messageRequestViewDidTapAccept(mode: mode)
                }]
        } else {
            buttons = [
                prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
                                                       comment: "A button used to block a user on an incoming message request."),
                              titleColor: .ows_accentRed) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
                },
                prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
                                                       comment: "incoming message request button text which deletes a conversation"),
                              titleColor: .ows_accentRed) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapDelete()
                },
                prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_ACCEPT_BUTTON",
                                                       comment: "A button used to accept a user on an incoming message request."),
                              titleColor: Theme.accentBlueColor) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapAccept(mode: mode)
                }]
        }

        return prepareButtonStack(buttons)
    }

    // MARK: - Group V2

    func prepareGroupV2Prompt() -> UILabel {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return UILabel()
        }
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return UILabel()
        }
        let groupMembership = groupThread.groupModel.groupMembership
        guard let addedByUuid = groupMembership.addedByUuid(forPendingMember: localAddress) else {
            owsFailDebug("missing addedByUuid")
            return UILabel()
        }
        let addedByName = contactManager.displayName(for: SignalServiceAddress(uuid: addedByUuid))

        let formatString = NSLocalizedString(
            "MESSAGE_REQUEST_VIEW_GROUP_INVITE_PROMPT_FORMAT",
            comment: "A prompt for the user to accept or decline an invite to a group. Embeds {{name of user who invited you}}."
        )

        return preparePromptLabel(formatString: formatString, embeddedString: addedByName)
    }

    func prepareGroupV2Buttons() -> UIStackView {
        let mode = self.mode
        let buttons = [
            prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
                                                   comment: "A button used to block a user on an incoming message request."),
                          titleColor: .ows_accentRed) { [weak self] in
                            self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
            },
            prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
                                                   comment: "incoming message request button text which deletes a conversation"),
                          titleColor: .ows_accentRed) { [weak self] in
                            self?.delegate?.messageRequestViewDidTapDelete()
            },
            prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_ACCEPT_BUTTON",
                                                   comment: "A button used to accept a user on an incoming message request."),
                          titleColor: Theme.accentBlueColor) { [weak self] in
                            self?.delegate?.messageRequestViewDidTapAccept(mode: mode)
            }]
        return prepareButtonStack(buttons)
    }

    // MARK: -

    func prepareButton(title: String, titleColor: UIColor, touchHandler: @escaping () -> Void) -> OWSFlatButton {
        let flatButton = OWSFlatButton()
        flatButton.setTitle(title: title, font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold(), titleColor: titleColor)
        flatButton.setBackgroundColors(upColor: Theme.isDarkThemeEnabled ? UIColor.ows_gray75 : UIColor.ows_gray05)
        flatButton.setPressedBlock(touchHandler)
        flatButton.useDefaultCornerRadius()
        flatButton.autoSetDimension(.height, toSize: 48)
        return flatButton
    }

    private func preparePromptLabel(formatString: String, embeddedString: String) -> UILabel {
        // Get the range of the formatter marker to calculate the start of the bold area
        var boldRange = (formatString as NSString).range(of: "%@")

        // Update the length of the range to reflect the length of the string that will be inserted
        boldRange.length = (embeddedString as NSString).length

        let promptString = String(format: formatString, embeddedString)

        let attributedString = NSMutableAttributedString(
            string: promptString,
            attributes: [
                .font: UIFont.ows_dynamicTypeSubheadlineClamped,
                .foregroundColor: Theme.secondaryTextAndIconColor
            ]
        )
        attributedString.addAttributes([.font: UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold()], range: boldRange)
        return prepareLabel(attributedString: attributedString)
    }

    private func prepareLabel(attributedString: NSAttributedString) -> UILabel {
        let label = UILabel()
        label.attributedText = attributedString
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func prepareButtonStack(_ buttons: [UIView]) -> UIStackView {
        let buttonsStack = UIStackView(arrangedSubviews: buttons)
        buttonsStack.spacing = 8
        buttonsStack.distribution = .fillEqually
        return buttonsStack
    }
}
