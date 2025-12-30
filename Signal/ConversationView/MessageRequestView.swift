//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol MessageRequestDelegate: AnyObject {
    func messageRequestViewDidTapBlock(mode: MessageRequestMode)
    func messageRequestViewDidTapDelete()
    func messageRequestViewDidTapAccept(mode: MessageRequestMode, unblockThread: Bool, unhideRecipient: Bool)
    func messageRequestViewDidTapUnblock(mode: MessageRequestMode)
    func messageRequestViewDidTapReport()
    func messageRequestViewDidTapLearnMore()
}

// MARK: -

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
    let isThreadFromHiddenRecipient: Bool
    let hasReportedSpam: Bool
    let isLocalUserInvitedMember: Bool
}

// MARK: -

class MessageRequestView: ConversationBottomPanelView {

    enum LocalizedStrings {
        static let block = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
            comment: "A button used to block a user on an incoming message request.",
        )
        static let unblock = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_UNBLOCK_BUTTON",
            comment: "A button used to unlock a blocked conversation.",
        )
        static let delete = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_DELETE_BUTTON",
            comment: "incoming message request button text which deletes a conversation",
        )
        static let report = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_REPORT_BUTTON",
            comment: "incoming message request button text which reports a conversation as spam",
        )
        static let accept = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_ACCEPT_BUTTON",
            comment: "A button used to accept a user on an incoming message request.",
        )
        static let `continue` = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_CONTINUE_BUTTON",
            comment: "A button used to continue a conversation and share your profile.",
        )
    }

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

    private var isThreadFromHiddenRecipient: Bool {
        messageRequestType.isThreadFromHiddenRecipient
    }

    private var hasReportedSpam: Bool {
        messageRequestType.hasReportedSpam
    }

    weak var delegate: MessageRequestDelegate?

    init(threadViewModel: ThreadViewModel) {
        let thread = threadViewModel.threadRecord
        self.thread = thread
        self.messageRequestType = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            Self.messageRequestType(forThread: thread, transaction: transaction)
        }

        if let groupThread = thread as? TSGroupThread, groupThread.isGroupV2Thread {
            self.mode = (groupThread.groupModel.groupMembership.isLocalUserInvitedMember
                ? .groupInviteRequest
                : .contactOrGroupRequest)
        } else {
            self.mode = .contactOrGroupRequest
        }

        super.init(frame: .zero)

        let arrangedSubviews: [UIView] = {
            switch mode {
            case .none:
                owsFailDebug("Invalid mode.")
                return []
            case .contactOrGroupRequest:
                return [
                    prepareMessageRequestPrompt(),
                    prepareMessageRequestButtons(),
                ]
            case .groupInviteRequest:
                return [
                    prepareGroupV2InvitePrompt(),
                    prepareGroupV2InviteButtons(),
                ]
            }
        }()

        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        addConstraints([
            stackView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
        ])
    }

    static func messageRequestType(
        forThread thread: TSThread,
        transaction: DBReadTransaction,
    ) -> MessageRequestType {
        let isGroupV1Thread = thread.isGroupV1Thread
        let isGroupV2Thread = thread.isGroupV2Thread
        let isThreadBlocked = SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: transaction)
        var isThreadFromHiddenRecipient = false
        if let thread = thread as? TSContactThread {
            isThreadFromHiddenRecipient = DependenciesBridge.shared.recipientHidingManager.isHiddenAddress(
                thread.contactAddress,
                tx: transaction,
            )
        }
        let finder = InteractionFinder(threadUniqueId: thread.uniqueId)
        let hasSentMessages = finder.existsOutgoingMessage(transaction: transaction)
        let hasReportedSpam = finder.hasUserReportedSpam(transaction: transaction)

        var isLocalUserInvitedMember = false
        if let groupThread = thread as? TSGroupThread, groupThread.groupModel.groupMembership.isLocalUserInvitedMember {
            isLocalUserInvitedMember = true
        }

        return MessageRequestType(
            isGroupV1Thread: isGroupV1Thread,
            isGroupV2Thread: isGroupV2Thread,
            isThreadBlocked: isThreadBlocked,
            hasSentMessages: hasSentMessages,
            isThreadFromHiddenRecipient: isThreadFromHiddenRecipient,
            hasReportedSpam: hasReportedSpam,
            isLocalUserInvitedMember: isLocalUserInvitedMember,
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
                        comment: "A prompt notifying that the user must unblock this group to continue.",
                    )
                } else if hasSentMessages {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_EXISTING_GROUP_PROMPT",
                        comment: "A prompt notifying that the user must share their profile with this group.",
                    )
                    appendLearnMoreLink = true
                } else {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT",
                        comment: "A prompt asking if the user wants to accept a group invite.",
                    )
                }
            } else {
                owsAssertDebug(thread.isGroupV2Thread)

                if isThreadBlocked {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_BLOCKED_GROUP_PROMPT_V2",
                        comment: "A prompt notifying that the user must unblock this group to continue.",
                    )
                } else {
                    string = OWSLocalizedString(
                        "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT_V2",
                        comment: "A prompt asking if the user wants to accept a group invite.",
                    )
                }
            }

            return prepareTextView(
                attributedString: NSAttributedString(string: string, attributes: [
                    .font: UIFont.dynamicTypeSubheadlineClamped,
                    .foregroundColor: Theme.secondaryTextAndIconColor,
                ]),
                appendLearnMoreLink: appendLearnMoreLink,
            )
        } else if let thread = thread as? TSContactThread {
            let formatString: String
            var appendLearnMoreLink = false

            if isThreadBlocked {
                formatString = OWSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_BLOCKED_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt notifying that the user must unblock this conversation to continue. Embeds {{contact name}}.",
                )
            } else if isThreadFromHiddenRecipient {
                formatString = OWSLocalizedString("MESSAGE_REQUEST_VIEW_REMOVED_CONTACT_PROMPT_FORMAT", comment: "A prompt asking if the user wants to accept a conversation invite from a person whom they previously removed. Embeds {{contact name}}.")

            } else if hasSentMessages {
                formatString = OWSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_EXISTING_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt notifying that the user must share their profile with this conversation. Embeds {{contact name}}.",
                )
                appendLearnMoreLink = true
            } else {
                formatString = OWSLocalizedString(
                    "MESSAGE_REQUEST_VIEW_NEW_CONTACT_PROMPT_FORMAT",
                    comment: "A prompt asking if the user wants to accept a conversation invite. Embeds {{contact name}}.",
                )
            }

            let shortName = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                return SSKEnvironment.shared.contactManagerRef.displayName(for: thread.contactAddress, tx: transaction).resolvedValue(useShortNameIfAvailable: true)
            }

            return preparePromptTextView(
                formatString: formatString,
                embeddedString: shortName,
                appendLearnMoreLink: appendLearnMoreLink,
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
            buttons.append(
                prepareButton(title: LocalizedStrings.delete, destructive: true) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapDelete()
                },
            )
            if !hasReportedSpam {
                buttons.append(
                    prepareButton(title: LocalizedStrings.report, destructive: true) { [weak self] in
                        self?.delegate?.messageRequestViewDidTapReport()
                    },
                )
            }
            buttons.append(
                prepareButton(title: LocalizedStrings.unblock) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapUnblock(mode: mode)
                },
            )
        } else if isThreadFromHiddenRecipient {
            buttons.append(
                prepareButton(title: LocalizedStrings.block, destructive: true) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
                },
            )
            if !hasReportedSpam {
                buttons.append(
                    prepareButton(title: LocalizedStrings.report, destructive: true) { [weak self] in
                        self?.delegate?.messageRequestViewDidTapReport()
                    },
                )
            } else {
                buttons.append(
                    prepareButton(title: LocalizedStrings.delete, destructive: true) { [weak self] in
                        self?.delegate?.messageRequestViewDidTapDelete()
                    },
                )
            }
            buttons.append(
                prepareButton(title: LocalizedStrings.accept) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapAccept(mode: mode, unblockThread: false, unhideRecipient: true)
                },
            )
        } else if hasSentMessages {
            buttons.append(
                prepareButton(title: LocalizedStrings.block, destructive: true) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
                },
            )
            if !hasReportedSpam {
                buttons.append(
                    prepareButton(title: LocalizedStrings.report, destructive: true) { [weak self] in
                        self?.delegate?.messageRequestViewDidTapReport()
                    },
                )
            } else {
                buttons.append(
                    prepareButton(title: LocalizedStrings.delete, destructive: true) { [weak self] in
                        self?.delegate?.messageRequestViewDidTapDelete()
                    },
                )
            }
            buttons.append(
                prepareButton(title: LocalizedStrings.continue) { [weak self] in
                    // This is the same action as accepting the message request, but displays
                    // with slightly different visuals if the user has already been messaging
                    // this user in the past but didn't share their profile.
                    self?.delegate?.messageRequestViewDidTapAccept(mode: mode, unblockThread: false, unhideRecipient: false)
                },
            )
        } else {
            buttons.append(
                prepareButton(title: LocalizedStrings.block, destructive: true) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
                },
            )
            if !hasReportedSpam {
                buttons.append(
                    prepareButton(title: LocalizedStrings.report, destructive: true) { [weak self] in
                        self?.delegate?.messageRequestViewDidTapReport()
                    },
                )
            } else {
                buttons.append(
                    prepareButton(title: LocalizedStrings.delete, destructive: true) { [weak self] in
                        self?.delegate?.messageRequestViewDidTapDelete()
                    },
                )
            }
            buttons.append(
                prepareButton(title: LocalizedStrings.accept) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapAccept(mode: mode, unblockThread: false, unhideRecipient: false)
                },
            )
        }

        return prepareButtonStack(buttons)
    }

    // MARK: - Group V2 Invites

    func prepareGroupV2InvitePrompt() -> UITextView {
        let string = OWSLocalizedString(
            "MESSAGE_REQUEST_VIEW_NEW_GROUP_PROMPT",
            comment: "A prompt asking if the user wants to accept a group invite.",
        )

        return prepareTextView(
            attributedString: NSAttributedString(string: string, attributes: [
                .font: UIFont.dynamicTypeSubheadlineClamped,
                .foregroundColor: Theme.secondaryTextAndIconColor,
            ]),
            appendLearnMoreLink: false,
        )
    }

    func prepareGroupV2InviteButtons() -> UIStackView {
        let mode = self.mode
        var buttons = [UIView]()

        buttons.append(
            prepareButton(title: LocalizedStrings.block, destructive: true) { [weak self] in
                self?.delegate?.messageRequestViewDidTapBlock(mode: mode)
            },
        )

        if !hasReportedSpam {
            buttons.append(
                prepareButton(title: LocalizedStrings.report, destructive: true) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapReport()
                },
            )
        } else {
            buttons.append(
                prepareButton(title: LocalizedStrings.delete, destructive: true) { [weak self] in
                    self?.delegate?.messageRequestViewDidTapDelete()
                },
            )
        }

        buttons.append(
            prepareButton(title: LocalizedStrings.accept) { [weak self] in
                self?.delegate?.messageRequestViewDidTapAccept(mode: mode, unblockThread: false, unhideRecipient: false)
            },
        )
        return prepareButtonStack(buttons)
    }

    // MARK: -

    private func prepareButton(
        title: String,
        destructive: Bool = false,
        actionBlock: @escaping () -> Void,
    ) -> UIButton {
        let button = UIButton(
            configuration: .mediumSecondary(title: title),
            primaryAction: UIAction { _ in
                actionBlock()
            },
        )
        if destructive {
            button.configuration?.baseForegroundColor = .Signal.red
        }
        return button
    }

    private func preparePromptTextView(formatString: String, embeddedString: String, appendLearnMoreLink: Bool) -> UITextView {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let defaultAttributes: AttributedFormatArg.Attributes = [
            .font: UIFont.dynamicTypeSubheadlineClamped,
            .foregroundColor: Theme.secondaryTextAndIconColor,
            .paragraphStyle: centered,
        ]

        let attributesForEmbedded: AttributedFormatArg.Attributes = [
            .font: UIFont.dynamicTypeSubheadlineClamped.semibold(),
            .foregroundColor: Theme.secondaryTextAndIconColor,
        ]

        let attributedString = NSAttributedString.make(
            fromFormat: formatString,
            attributedFormatArgs: [.string(embeddedString, attributes: attributesForEmbedded)],
            defaultAttributes: defaultAttributes,
        )

        return prepareTextView(attributedString: attributedString, appendLearnMoreLink: appendLearnMoreLink)
    }

    private func prepareTextView(attributedString: NSAttributedString, appendLearnMoreLink: Bool) -> UITextView {
        let textView = LinkingTextView()
        if appendLearnMoreLink {
            textView.attributedText = .composed(of: [
                attributedString,
                " ",
                CommonStrings.learnMore.styled(
                    with: .link(URL.Support.profilesAndMessageRequests),
                    .font(.dynamicTypeSubheadlineClamped),
                ),
            ])
            .styled(with: .alignment(.center))
        } else {
            textView.attributedText = attributedString.styled(with: .alignment(.center))
        }
        return textView
    }

    private func prepareButtonStack(_ buttons: [UIView]) -> UIStackView {
        let buttonsStack = UIStackView(arrangedSubviews: buttons)
        buttonsStack.spacing = 11.5
        buttonsStack.distribution = .fillEqually
        return buttonsStack
    }
}
