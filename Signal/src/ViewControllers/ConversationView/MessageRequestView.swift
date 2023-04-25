//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

protocol MessageRequestDelegate: AnyObject {
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

public struct MessageRequestType: Equatable {
    let isGroupV1Thread: Bool
    let isGroupV2Thread: Bool
    let isThreadBlocked: Bool
    let hasSentMessages: Bool
}

// MARK: -

@objc
class MessageRequestView: UIStackView {

    private let thread: TSThread
    private let mode: MessageRequestMode
    private let messageRequestType: MessageRequestType

    private var isGroupV1Thread: Bool {
        messageRequestType.isGroupV1Thread
    }
    private var isGroupV2Thread: Bool {
        messageRequestType.isGroupV2Thread
    }
    private var isThreadBlocked: Bool {
        messageRequestType.isThreadBlocked
    }
    private var hasSentMessages: Bool {
        messageRequestType.hasSentMessages
    }

    weak var delegate: MessageRequestDelegate?

    init(threadViewModel: ThreadViewModel) {
        let thread = threadViewModel.threadRecord
        self.thread = thread
        self.messageRequestType = Self.databaseStorage.read { transaction in
            Self.messageRequestType(forThread: thread, transaction: transaction)
        }

        if let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread {
            self.mode = (groupThread.isLocalUserInvitedMember
                ? .groupInviteRequest
                : .contactOrGroupRequest)
        } else {
            self.mode = .contactOrGroupRequest
        }

        super.init(frame: .zero)

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
            addArrangedSubview(prepareMessageRequestPrompt())
            addArrangedSubview(prepareMessageRequestButtons())
        case .groupInviteRequest:
            addArrangedSubview(prepareGroupV2InvitePrompt())
            addArrangedSubview(prepareGroupV2InviteButtons())
        }
    }

    public static func messageRequestType(forThread thread: TSThread,
                                          transaction: SDSAnyReadTransaction) -> MessageRequestType {
        let isGroupV1Thread = thread.isGroupV1Thread
        let isGroupV2Thread = thread.isGroupV2Thread
        let isThreadBlocked = blockingManager.isThreadBlocked(thread, transaction: transaction)
        let hasSentMessages = InteractionFinder(threadUniqueId: thread.uniqueId).existsOutgoingMessage(transaction: transaction)
        return MessageRequestType(isGroupV1Thread: isGroupV1Thread,
                                  isGroupV2Thread: isGroupV2Thread,
                                  isThreadBlocked: isThreadBlocked,
                                  hasSentMessages: hasSentMessages)
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
    func prepareMessageRequestPrompt() -> UITextView {
        if thread.isGroupThread {
            let string: String
            var appendLearnMoreLink = false
            if thread.isGroupV1Thread {
                if isThreadBlocked {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_BLOCKED_GROUP_PROMPT",
                        comment: "A prompt notifying that the user must unblock this group to continue."
                    )
                } else if hasSentMessages {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_EXISTING_GROUP_PROMPT",
                        comment: "A prompt notifying that the user must share their profile with this group."
                    )
                    appendLearnMoreLink = true
                } else {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT",
                        comment: "A prompt asking if the user wants to accept a group invite."
                    )
                }
            } else {
                owsAssertDebug(thread.isGroupV2Thread)

                if isThreadBlocked {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_BLOCKED_GROUP_PROMPT_V2",
                        comment: "A prompt notifying that the user must unblock this group to continue."
                    )
                } else {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT_V2",
                        comment: "A prompt asking if the user wants to accept a group invite."
                    )
                }
            }

            return prepareTextView(
                attributedString: NSAttributedString(string: string, attributes: [
                    .font: UIFont.dynamicTypeSubheadlineClamped,
                    .foregroundColor: Theme.secondaryTextAndIconColor
                ]),
                appendLearnMoreLink: appendLearnMoreLink
            )
        } else if let thread = thread as? TSContactThread {
            let formatString: String
            var appendLearnMoreLink = false

            if isThreadBlocked {
                formatString = OWSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_BLOCKED_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt notifying that the user must unblock this conversation to continue. Embeds {{contact name}}."
                )
            } else if hasSentMessages {
                formatString = OWSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_EXISTING_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt notifying that the user must share their profile with this conversation. Embeds {{contact name}}."
                )
                appendLearnMoreLink = true
            } else {
                formatString = OWSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_NEW_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt asking if the user wants to accept a conversation invite. Embeds {{contact name}}."
                )
            }

            let shortName = databaseStorage.read { transaction in
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
    func prepareMessageRequestButtons() -> UIStackView {
        let mode = self.mode
        var buttons = [UIView]()

        if isThreadBlocked {
            buttons = [
                prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
                                                       comment: "incoming message request button text which deletes a conversation"),
                              titleColor: .ows_accentRed) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapDelete()
                },
                prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_UNBLOCK_BUTTON",
                                                       comment: "A button used to unlock a blocked conversation."),
                              titleColor: Theme.accentBlueColor) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapUnblock(mode: mode)
                }]
        } else if hasSentMessages {
            buttons = [
                prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
                                                       comment: "A button used to block a user on an incoming message request."),
                              titleColor: .ows_accentRed) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
                },
                prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
                                                       comment: "incoming message request button text which deletes a conversation"),
                              titleColor: .ows_accentRed) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapDelete()
                },
                prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_CONTINUE_BUTTON",
                                                       comment: "A button used to continue a conversation and share your profile."),
                              titleColor: Theme.accentBlueColor) { [weak self] in
                    // This is the same action as accepting the message request, but displays
                    // with slightly different visuals if the user has already been messaging
                    // this user in the past but didn't share their profile.
                    self?.delegate?.messageRequestViewDidTapAccept(mode: mode)
                }]
        } else {
            buttons = [
                prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
                                                       comment: "A button used to block a user on an incoming message request."),
                              titleColor: .ows_accentRed) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
                },
                prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
                                                       comment: "incoming message request button text which deletes a conversation"),
                              titleColor: .ows_accentRed) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapDelete()
                },
                prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_ACCEPT_BUTTON",
                                                       comment: "A button used to accept a user on an incoming message request."),
                              titleColor: Theme.accentBlueColor) { [weak self] in
                                self?.delegate?.messageRequestViewDidTapAccept(mode: mode)
                }]
        }

        return prepareButtonStack(buttons)
    }

    // MARK: - Group V2 Invites

    func prepareGroupV2InvitePrompt() -> UITextView {
        let string = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT",
            comment: "A prompt asking if the user wants to accept a group invite."
        )

        return prepareTextView(
            attributedString: NSAttributedString(string: string, attributes: [
                .font: UIFont.dynamicTypeSubheadlineClamped,
                .foregroundColor: Theme.secondaryTextAndIconColor
            ]),
            appendLearnMoreLink: false
        )
    }

    func prepareGroupV2InviteButtons() -> UIStackView {
        let mode = self.mode
        let buttons = [
            prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
                                                   comment: "A button used to block a user on an incoming message request."),
                          titleColor: .ows_accentRed) { [weak self] in
                            self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
            },
            prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
                                                   comment: "incoming message request button text which deletes a conversation"),
                          titleColor: .ows_accentRed) { [weak self] in
                            self?.delegate?.messageRequestViewDidTapDelete()
            },
            prepareButton(title: OWSLocalizedString("MESSAGE_REQUEST_VIEW_ACCEPT_BUTTON",
                                                   comment: "A button used to accept a user on an incoming message request."),
                          titleColor: Theme.accentBlueColor) { [weak self] in
                            self?.delegate?.messageRequestViewDidTapAccept(mode: mode)
            }]
        return prepareButtonStack(buttons)
    }

    // MARK: -

    func prepareButton(title: String, titleColor: UIColor, touchHandler: @escaping () -> Void) -> OWSFlatButton {
        let flatButton = OWSFlatButton()
        flatButton.setTitle(title: title, font: UIFont.dynamicTypeBodyClamped.semibold(), titleColor: titleColor)
        flatButton.setBackgroundColors(upColor: Theme.isDarkThemeEnabled ? UIColor.ows_gray75 : UIColor.ows_gray05)
        flatButton.setPressedBlock(touchHandler)
        flatButton.useDefaultCornerRadius()
        flatButton.autoSetDimension(.height, toSize: 48)
        return flatButton
    }

    private func preparePromptTextView(formatString: String, embeddedString: String, appendLearnMoreLink: Bool) -> UITextView {
        let defaultAttributes: AttributedFormatArg.Attributes = [
            .font: UIFont.dynamicTypeSubheadlineClamped,
            .foregroundColor: Theme.secondaryTextAndIconColor
        ]

        let attributesForEmbedded: AttributedFormatArg.Attributes = [
            .font: UIFont.dynamicTypeSubheadlineClamped.semibold(),
            .foregroundColor: Theme.secondaryTextAndIconColor
        ]

        let attributedString = NSAttributedString.make(
            fromFormat: formatString,
            attributedFormatArgs: [.string(embeddedString, attributes: attributesForEmbedded)],
            defaultAttributes: defaultAttributes
        )

        return prepareTextView(attributedString: attributedString, appendLearnMoreLink: appendLearnMoreLink)
    }

    private func prepareTextView(attributedString: NSAttributedString, appendLearnMoreLink: Bool) -> UITextView {
        let textView = UITextView()
        textView.isOpaque = false
        textView.isEditable = false
        textView.contentInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.linkTextAttributes = [
            .foregroundColor: Theme.accentBlueColor
        ]

        if appendLearnMoreLink {
            textView.attributedText = .composed(of: [
                attributedString,
                " ",
                CommonStrings.learnMore.styled(
                    with: .link(URL(string: "https://support.signal.org/hc/articles/360007459591")!),
                    .font(.dynamicTypeSubheadlineClamped)
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
