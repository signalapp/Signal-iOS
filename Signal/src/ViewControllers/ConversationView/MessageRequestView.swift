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
    case contactOrGroupRequest
    case groupInviteRequest
}

// MARK: -

@objc
class MessageRequestView: UIStackView {

    private let thread: TSThread
    private let mode: MessageRequestMode

    @objc
    weak var delegate: MessageRequestDelegate?

    @objc
    init(threadViewModel: ThreadViewModel) {
        let thread = threadViewModel.threadRecord
        self.thread = thread

        if let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread {
            self.mode = (groupThread.isLocalUserInvitedMember
                ? .groupInviteRequest
                : .contactOrGroupRequest)
        } else {
            self.mode = .contactOrGroupRequest
        }

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
        case .contactOrGroupRequest:
            var hasSentMessages = false
            databaseStorage.uiRead { transaction in
        hasSentMessages = InteractionFinder(threadUniqueId: thread.uniqueId).existsOutgoingMessage(transaction: transaction)
            }

            addArrangedSubview(prepareMessageRequestPrompt(hasSentMessages: hasSentMessages,
        isThreadBlocked: isThreadBlocked))
            addArrangedSubview(prepareMessageRequestButtons(hasSentMessages: hasSentMessages,
        isThreadBlocked: isThreadBlocked))
        case .groupInviteRequest:
            addArrangedSubview(prepareGroupV2InvitePrompt())
            addArrangedSubview(prepareGroupV2InviteButtons())
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return .zero
    }

    // MARK: - Message Request

    // This is used for:
    //
    // * Contact threads
    // * v1 groups
    // * v2 groups if user does not have a pending invite.
    func prepareMessageRequestPrompt(hasSentMessages: Bool, isThreadBlocked: Bool) -> UITextView {
        if thread.isGroupThread {
            let string: String
            var appendLearnMoreLink = false
            if thread.isGroupV1Thread {
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
                    appendLearnMoreLink = true
                } else {
                    string = NSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT",
                        comment: "A prompt asking if the user wants to accept a group invite."
                    )
                }
            } else {
                owsAssertDebug(thread.isGroupV2Thread)

                if isThreadBlocked {
                    string = NSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_BLOCKED_GROUP_PROMPT_V2",
                        comment: "A prompt notifying that the user must unblock this group to continue."
                    )
                } else {
                    string = NSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT_V2",
                        comment: "A prompt asking if the user wants to accept a group invite."
                    )
                }
            }

            return prepareTextView(
                attributedString: NSAttributedString(string: string, attributes: [
                    .font: UIFont.ows_dynamicTypeSubheadlineClamped,
                    .foregroundColor: Theme.secondaryTextAndIconColor
                ]),
                appendLearnMoreLink: appendLearnMoreLink
            )
        } else if let thread = thread as? TSContactThread {
            let formatString: String
            var appendLearnMoreLink = false

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
                appendLearnMoreLink = true
            } else {
                formatString = NSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_NEW_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt asking if the user wants to accept a conversation invite. Embeds {{contact name}}."
                )
            }

            let shortName = databaseStorage.uiRead { transaction in
                return self.contactsManager.shortDisplayName(for: thread.contactAddress, transaction: transaction)
            }

            return preparePromptTextView(
                formatString: formatString,
                embeddedString: shortName,
                appendLearnMoreLink: appendLearnMoreLink
            )
        } else {
            owsFailDebug("unexpected thread type")
            return UITextView()
        }
    }

    // This is used for:
    //
    // * Contact threads
    // * v1 groups
    // * v2 groups if user does not have a pending invite.
    func prepareMessageRequestButtons(hasSentMessages: Bool, isThreadBlocked: Bool) -> UIStackView {
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
                prepareButton(title: NSLocalizedString("MESSAGE_REQUEST_VIEW_CONTINUE_BUTTON",
                                                       comment: "A button used to continue a conversation and share your profile."),
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

    // MARK: - Group V2 Invites

    func prepareGroupV2InvitePrompt() -> UITextView {
        let string = NSLocalizedString(
            "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT",
            comment: "A prompt asking if the user wants to accept a group invite."
        )

        return prepareTextView(
            attributedString: NSAttributedString(string: string, attributes: [
                .font: UIFont.ows_dynamicTypeSubheadlineClamped,
                .foregroundColor: Theme.secondaryTextAndIconColor
            ]),
            appendLearnMoreLink: false
        )
    }

    func prepareGroupV2InviteButtons() -> UIStackView {
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
        flatButton.setTitle(title: title, font: UIFont.ows_dynamicTypeBodyClamped.ows_semibold, titleColor: titleColor)
        flatButton.setBackgroundColors(upColor: Theme.isDarkThemeEnabled ? UIColor.ows_gray75 : UIColor.ows_gray05)
        flatButton.setPressedBlock(touchHandler)
        flatButton.useDefaultCornerRadius()
        flatButton.autoSetDimension(.height, toSize: 48)
        return flatButton
    }

    private func preparePromptTextView(formatString: String, embeddedString: String, appendLearnMoreLink: Bool) -> UITextView {
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
        attributedString.addAttributes([.font: UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold], range: boldRange)
        return prepareTextView(attributedString: attributedString, appendLearnMoreLink: appendLearnMoreLink)
    }

    private func prepareTextView(attributedString: NSAttributedString, appendLearnMoreLink: Bool) -> UITextView {
        let textView = UITextView()
        textView.isOpaque = false
        textView.isEditable = false
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false

        if appendLearnMoreLink {
            textView.attributedText = .composed(of: [
                attributedString,
                " ",
                CommonStrings.learnMore.styled(
                    with: .link(URL(string: "https://support.signal.org/hc/articles/360007459591")!),
                    .font(.ows_dynamicTypeSubheadlineClamped),
                    .underline([], nil),
                    .color(Theme.accentBlueColor)
                )
            ])
        } else {
            textView.attributedText = attributedString
        }

        return textView
    }

    private func prepareButtonStack(_ buttons: [UIView]) -> UIStackView {
        let buttonsStack = UIStackView(arrangedSubviews: buttons)
        buttonsStack.spacing = 8
        buttonsStack.distribution = .fillEqually
        return buttonsStack
    }
}
