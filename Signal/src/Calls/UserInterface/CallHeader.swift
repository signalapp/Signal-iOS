//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalMessaging
import SignalRingRTC
import SignalUI
import UIKit

@objc
protocol CallHeaderDelegate: AnyObject {
    func didTapBackButton()
    func didTapMembersButton()
}

class CallHeader: UIView {
    // MARK: - Views

    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")!
        dateFormatter.locale = Locale(identifier: "en_US")
        return dateFormatter
    }()

    private var callDurationTimer: Timer?

    private lazy var gradientView: UIView = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.ows_blackAlpha60.cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        let view = OWSLayerView(frame: .zero) { view in
            gradientLayer.frame = view.bounds
        }
        view.layer.addSublayer(gradientLayer)
        return view
    }()

    private let avatarView = ConversationAvatarView(sizeClass: .customDiameter(96),
                                                    localUserDisplayMode: .asLocalUser,
                                                    badged: false)
    private let callTitleLabel = MarqueeLabel()
    private let callStatusLabel = UILabel()
    private let groupMembersButton = GroupMembersButton()

    private let call: SignalCall
    private weak var delegate: CallHeaderDelegate!

    init(call: SignalCall, delegate: CallHeaderDelegate) {
        self.call = call
        self.delegate = delegate
        super.init(frame: .zero)

        addSubview(gradientView)
        gradientView.autoPinEdgesToSuperviewEdges()

        // Back button

        let backButton = UIButton()
        backButton.setTemplateImage(UIImage(imageLiteralResourceName: "NavBarBack"), tintColor: .ows_white)
        backButton.autoSetDimensions(to: CGSize(square: 40))
        backButton.imageEdgeInsets = UIEdgeInsets(top: -12, leading: -18, bottom: 0, trailing: 0)
        backButton.addTarget(delegate, action: #selector(CallHeaderDelegate.didTapBackButton), for: .touchUpInside)
        addShadow(to: backButton)

        addSubview(backButton)
        backButton.autoPinLeadingToSuperviewMargin(withInset: 8)
        backButton.autoPinTopToSuperviewMargin()

        // Group members button

        groupMembersButton.addTarget(
            delegate,
            action: #selector(CallHeaderDelegate.didTapMembersButton),
            for: .touchUpInside
        )
        addShadow(to: groupMembersButton)

        addSubview(groupMembersButton)
        groupMembersButton.autoPinTrailingToSuperviewMargin(withInset: 8)
        groupMembersButton.autoPinTopToSuperviewMargin()

        // vStack

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .center
        vStack.spacing = 8
        vStack.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 0)

        // This view doesn't contain any interactable content, put it as low as possible.
        insertSubview(vStack, aboveSubview: gradientView)
        vStack.autoPinEdgesToSuperviewMargins()

        // Avatar
        let avatarPaddingView = UIView()
        avatarView.updateWithSneakyTransactionIfNecessary {
            $0.dataSource = .thread(call.thread)
        }
        avatarPaddingView.addSubview(avatarView)
        avatarView.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)

        vStack.addArrangedSubview(avatarPaddingView)
        vStack.setCustomSpacing(16, after: avatarPaddingView)

        // Name Label

        callTitleLabel.type = .continuous
        // This feels pretty slow when you're initially waiting for it, but when you're overlaying video calls, anything faster is distracting.
        callTitleLabel.speed = .duration(30.0)
        callTitleLabel.animationCurve = .linear
        callTitleLabel.fadeLength = 10.0
        callTitleLabel.animationDelay = 5
        // Add trailing space after the name scrolls before it wraps around and scrolls back in.
        callTitleLabel.trailingBuffer = .scaleFromIPhone5(80)

        callTitleLabel.font = UIFont.dynamicTypeHeadline.semibold()
        callTitleLabel.textAlignment = .center
        callTitleLabel.textColor = UIColor.white
        addShadow(to: callTitleLabel)

#if TESTABLE_BUILD
        // For debugging purposes, make it easy to force the call to disconnect.
        callTitleLabel.addGestureRecognizer(UILongPressGestureRecognizer(target: self,
                                                                         action: #selector(injectDisconnect)))
        callTitleLabel.isUserInteractionEnabled = true
#endif

        vStack.addArrangedSubview(callTitleLabel)

        // Make the title view as wide as possible, but don't overlap either button.
        // This gets combined with the vStack's centered alignment, so we won't ever get an unbalanced title label.
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            callTitleLabel.autoPinWidthToSuperview()
        }
        callTitleLabel.autoPinEdge(.leading, to: .trailing, of: backButton, withOffset: 13, relation: .greaterThanOrEqual)
        callTitleLabel.autoPinEdge(.trailing, to: .leading, of: groupMembersButton, withOffset: -13, relation: .lessThanOrEqual)

        // Status label

        callStatusLabel.font = UIFont.dynamicTypeFootnote.monospaced()
        callStatusLabel.textAlignment = .center
        callStatusLabel.textColor = UIColor.white
        callStatusLabel.numberOfLines = 0
        // Cut off the status lines before cutting off anything else.
        callStatusLabel.setContentCompressionResistancePriority(.defaultLow + 1, for: .vertical)
        // But always fit at least one line, with moderate descenders.
        callStatusLabel.autoSetDimension(.height, toSize: callStatusLabel.font.lineHeight * 1.2, relation: .greaterThanOrEqual)
        addShadow(to: callStatusLabel)

        vStack.addArrangedSubview(callStatusLabel)

        call.addObserverAndSyncState(observer: self)
    }

    deinit { call.removeObserver(self) }

    override func didMoveToSuperview() {
        guard let superview = self.superview else {
            return
        }
        // The bottom of the avatar must be no more than 25% down the screen.
        // This constraint is on the avatar view container rather than the full view
        // because the label may change its number of lines,
        // and we don't want that to affect the vertical position.
        avatarView.superview!.autoMatch(.height, to: .height, of: superview, withMultiplier: 0.25)
    }

    private func addShadow(to view: UIView) {
        view.layer.shadowOffset = .zero
        view.layer.shadowOpacity = 0.25
        view.layer.shadowRadius = 4
    }

    private func describeMembers(count: Int,
                                 names: [String],
                                 zeroMemberString: @autoclosure () -> String,
                                 oneMemberFormat: @autoclosure () -> String,
                                 twoMemberFormat: @autoclosure () -> String,
                                 manyMemberFormat: @autoclosure () -> String) -> String {
        switch count {
        case 0:
            return zeroMemberString()
        case 1:
            return String(format: oneMemberFormat(), names[0])
        case 2:
            return String(format: twoMemberFormat(), names[0], names[1])
        default:
            return String.localizedStringWithFormat(manyMemberFormat(), count - 2, names[0], names[1])
        }
    }

    private func fetchGroupSizeAndMemberNamesWithSneakyTransaction() -> (Int, [String]) {
        guard let groupThread = call.thread as? TSGroupThread else {
            return (0, [])
        }
        return databaseStorage.read { transaction in
            // FIXME: Register for notifications so we can update if someone leaves the group while the screen is up?
            let firstTwoNames = groupThread.sortedMemberNames(
                includingBlocked: false,
                limit: 2,
                useShortNameIfAvailable: true,
                transaction: transaction
            )
            if firstTwoNames.count < 2 {
                return (firstTwoNames.count, firstTwoNames)
            }

            let count = groupThread.groupMembership.fullMembers.lazy.filter {
                !$0.isLocalAddress && !self.blockingManager.isAddressBlocked($0, transaction: transaction)
            }.count
            return (count, firstTwoNames)
        }
    }

    private func updateCallStatusLabel() {
        let callStatusText: String
        switch call.groupCall.localDeviceState.joinState {
        case .notJoined, .joining, .pending:
            if case .incomingRing(let caller, _) = call.groupCallRingState {
                let callerName = databaseStorage.read { transaction in
                    contactsManager.shortDisplayName(for: caller, transaction: transaction)
                }
                let formatString = OWSLocalizedString(
                    "GROUP_CALL_INCOMING_RING_FORMAT",
                    comment: "Text explaining that someone has sent a ring to the group. Embeds {ring sender name}")
                callStatusText = String(format: formatString, callerName)

            } else if let joinedMembers = call.groupCall.peekInfo?.joinedMembers, !joinedMembers.isEmpty {
                let memberNames: [String] = databaseStorage.read { tx in
                    joinedMembers.prefix(2).map {
                        contactsManager.shortDisplayName(for: SignalServiceAddress(Aci(fromUUID: $0)), transaction: tx)
                    }
                }
                callStatusText = describeMembers(
                    count: joinedMembers.count,
                    names: memberNames,
                    zeroMemberString: "",
                    oneMemberFormat: OWSLocalizedString(
                        "GROUP_CALL_ONE_PERSON_HERE_FORMAT",
                        comment: "Text explaining that there is one person in the group call. Embeds {member name}"),
                    twoMemberFormat: OWSLocalizedString(
                        "GROUP_CALL_TWO_PEOPLE_HERE_FORMAT",
                        comment: "Text explaining that there are two people in the group call. Embeds {{ %1$@ participant1, %2$@ participant2 }}"),
                    manyMemberFormat: OWSLocalizedString(
                        "GROUP_CALL_MANY_PEOPLE_HERE_%d",
                        tableName: "PluralAware",
                        comment: "Text explaining that there are three or more people in the group call. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"))

            } else if call.groupCall.peekInfo == nil && call.ringRestrictions.contains(.callInProgress) {
                // If we think there might already be a call, don't show anything until we have proper peek info.
                callStatusText = ""
            } else {
                let (memberCount, firstTwoNames) = fetchGroupSizeAndMemberNamesWithSneakyTransaction()
                if call.ringRestrictions.isEmpty, case .shouldRing = call.groupCallRingState {
                    callStatusText = describeMembers(
                        count: memberCount,
                        names: firstTwoNames,
                        zeroMemberString: "",
                        oneMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_WILL_RING_ONE_PERSON_FORMAT",
                            comment: "Text shown before the user starts a group call if the user has enabled ringing and there is one other person in the group. Embeds {member name}"),
                        twoMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_WILL_RING_TWO_PEOPLE_FORMAT",
                            comment: "Text shown before the user starts a group call if the user has enabled ringing and there are two other people in the group. Embeds {{ %1$@ participant1, %2$@ participant2 }}"),
                        manyMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_WILL_RING_MANY_PEOPLE_%d",
                            tableName: "PluralAware",
                            comment: "Text shown before the user starts a group call if the user has enabled ringing and there are three or more other people in the group. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"))
                } else {
                    callStatusText = describeMembers(
                        count: memberCount,
                        names: firstTwoNames,
                        zeroMemberString: "",
                        oneMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_WILL_NOTIFY_ONE_PERSON_FORMAT",
                            comment: "Text shown before the user starts a group call if the user has not enabled ringing and there is one other person in the group. Embeds {member name}"),
                        twoMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_WILL_NOTIFY_TWO_PEOPLE_FORMAT",
                            comment: "Text shown before the user starts a group call if the user has not enabled ringing and there are two other people in the group. Embeds {{ %1$@ participant1, %2$@ participant2 }}"),
                        manyMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_WILL_NOTIFY_MANY_PEOPLE_%d",
                            tableName: "PluralAware",
                            comment: "Text shown before the user starts a group call if the user has not enabled ringing and there are three or more other people in the group. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"))
                }
            }
        case .joined:
            if call.groupCall.localDeviceState.connectionState == .reconnecting {
                callStatusText = OWSLocalizedString(
                    "GROUP_CALL_RECONNECTING",
                    comment: "Text indicating that the user has lost their connection to the call and we are reconnecting.")

            } else if call.groupCall.remoteDeviceStates.isEmpty {
                if case .ringing = call.groupCallRingState {
                    let (memberCount, firstTwoNames) = fetchGroupSizeAndMemberNamesWithSneakyTransaction()
                    callStatusText = describeMembers(
                        count: memberCount,
                        names: firstTwoNames,
                        zeroMemberString: "",
                        oneMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_IS_RINGING_ONE_PERSON_FORMAT",
                            comment: "Text shown before the user starts a group call if the user has enabled ringing and there is one other person in the group. Embeds {member name}"),
                        twoMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_IS_RINGING_TWO_PEOPLE_FORMAT",
                            comment: "Text shown before the user starts a group call if the user has enabled ringing and there are two other people in the group. Embeds {{ %1$@ participant1, %2$@ participant2 }}"),
                        manyMemberFormat: OWSLocalizedString(
                            "GROUP_CALL_IS_RINGING_MANY_PEOPLE_%d",
                            tableName: "PluralAware",
                            comment: "Text shown before the user starts a group call if the user has enabled ringing and there are three or more other people in the group. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"))

                } else {
                    callStatusText = OWSLocalizedString(
                        "GROUP_CALL_NO_ONE_HERE",
                        comment: "Text explaining that you are the only person currently in the group call")
                }

            } else {
                let callDuration = call.connectionDuration()
                let callDurationDate = Date(timeIntervalSinceReferenceDate: callDuration)
                var formattedDate = dateFormatter.string(from: callDurationDate)
                if formattedDate.hasPrefix("00:") {
                    // Don't show the "hours" portion of the date format unless the
                    // call duration is at least 1 hour.
                    formattedDate = String(formattedDate[formattedDate.index(formattedDate.startIndex, offsetBy: 3)...])
                } else {
                    // If showing the "hours" portion of the date format, strip any leading
                    // zeroes.
                    if formattedDate.hasPrefix("0") {
                        formattedDate = String(formattedDate[formattedDate.index(formattedDate.startIndex, offsetBy: 1)...])
                    }
                }
                callStatusText = String(format: CallStrings.callStatusFormat, formattedDate)
            }
        }

        callStatusLabel.text = callStatusText
    }

    private func updateCallTitleLabel() {
        let callTitleText: String
        if
            call.groupCall.localDeviceState.joinState == .joined,
            let firstMember = call.groupCall.remoteDeviceStates.sortedBySpeakerTime.first,
            firstMember.presenting == true
        {
            let presentingName = databaseStorage.read { tx in
                contactsManager.shortDisplayName(for: SignalServiceAddress(Aci(fromUUID: firstMember.userId)), transaction: tx)
            }
            let formatString = OWSLocalizedString(
                "GROUP_CALL_PRESENTING_FORMAT",
                comment: "Text explaining that a member is presenting. Embeds {member name}")
            callTitleText = String(format: formatString, presentingName)
        } else {
            // FIXME: This should auto-update if the group name changes.
            callTitleText = databaseStorage.read { transaction in
                contactsManager.displayName(for: call.thread, transaction: transaction)
            }
        }

        callTitleLabel.text = callTitleText
    }

    func updateGroupMembersButton() {
        let isJoined = call.groupCall.localDeviceState.joinState == .joined
        let remoteMemberCount = isJoined ? call.groupCall.remoteDeviceStates.count : Int(call.groupCall.peekInfo?.deviceCountExcludingPendingDevices ?? 0)
        groupMembersButton.updateMemberCount(remoteMemberCount + (isJoined ? 1 : 0))
    }

    // For testing abnormal scenarios.
    @objc
    private func injectDisconnect() {
        call.groupCall.disconnect()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension CallHeader: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        owsAssertDebug(call.isGroupCall)

        if call.groupCall.localDeviceState.joinState == .joined {
            gradientView.isHidden = false
            avatarView.superview!.isHidden = true // hide the container
            if callDurationTimer == nil {
                let kDurationUpdateFrequencySeconds = 1 / 20.0
                callDurationTimer = WeakTimer.scheduledTimer(
                    timeInterval: TimeInterval(kDurationUpdateFrequencySeconds),
                    target: self,
                    userInfo: nil,
                    repeats: true
                ) {[weak self] _ in
                    self?.updateCallStatusLabel()
                }
            }
        } else {
            gradientView.isHidden = true
            avatarView.superview!.isHidden = false
            callDurationTimer?.invalidate()
            callDurationTimer = nil
        }

        updateCallStatusLabel()
        updateGroupMembersButton()
    }

    func groupCallPeekChanged(_ call: SignalCall) {
        updateCallStatusLabel()
        updateGroupMembersButton()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        updateCallTitleLabel()
        updateCallStatusLabel()
        updateGroupMembersButton()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        callDurationTimer?.invalidate()
        callDurationTimer = nil

        updateCallStatusLabel()
        updateGroupMembersButton()
    }
}

private class GroupMembersButton: UIButton {
    private let iconImageView = UIImageView()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        autoSetDimension(.height, toSize: 40)

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.setTemplateImage(#imageLiteral(resourceName: "group-fill"), tintColor: .ows_white)
        addSubview(iconImageView)
        iconImageView.autoPinEdge(toSuperviewEdge: .leading)
        iconImageView.autoSetDimensions(to: CGSize(square: 22))
        iconImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 2)

        countLabel.font = UIFont.dynamicTypeFootnoteClamped.monospaced()
        countLabel.textColor = .ows_white
        addSubview(countLabel)
        countLabel.autoPinEdge(.leading, to: .trailing, of: iconImageView, withOffset: 5)
        countLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: 5)
        countLabel.autoAlignAxis(.horizontal, toSameAxisOf: iconImageView)
        countLabel.setContentHuggingHorizontalHigh()
        countLabel.setCompressionResistanceHorizontalHigh()
    }

    func updateMemberCount(_ count: Int) {
        countLabel.text = String(OWSFormat.formatInt(count))
        self.isHidden = count == 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.5 : 1
        }
    }
}
