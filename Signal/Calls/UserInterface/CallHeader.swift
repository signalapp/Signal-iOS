//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI
import UIKit

@objc
protocol CallHeaderDelegate: AnyObject {
    func didTapBackButton()
    func didTapMembersButton()
}

class CallHeader: UIView {
    // MARK: - Views

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

    private var avatarView: UIView?

    private let callTitleLabel = MarqueeLabel()
    private let callStatusLabel = UILabel()

    private let groupCall: GroupCall
    private let ringRtcCall: SignalRingRTC.GroupCall
    private weak var delegate: CallHeaderDelegate!

    init(groupCall: GroupCall, delegate: CallHeaderDelegate) {
        self.groupCall = groupCall
        self.ringRtcCall = groupCall.ringRtcCall
        self.delegate = delegate
        super.init(frame: .zero)

        addSubview(gradientView)
        gradientView.autoPinEdgesToSuperviewEdges()

        // Back button

        let backButton = UIButton()
        backButton.setTemplateImage(UIImage(imageLiteralResourceName: "NavBarBack"), tintColor: .ows_white)
        backButton.autoSetDimensions(to: CGSize(square: 40))
        backButton.ows_imageEdgeInsets = UIEdgeInsets(top: -12, leading: -18, bottom: 0, trailing: 0)
        backButton.addTarget(delegate, action: #selector(CallHeaderDelegate.didTapBackButton), for: .touchUpInside)
        addShadow(to: backButton)

        addSubview(backButton)
        backButton.autoPinLeadingToSuperviewMargin(withInset: 8)
        backButton.autoPinTopToSuperviewMargin()

        // Group members button

        let topRightButton = OWSButton(
            imageName: "info",
            tintColor: .ows_white,
            dimsWhenHighlighted: true
        ) { [weak delegate] in
            delegate?.didTapMembersButton()
        }

        addShadow(to: topRightButton)

        addSubview(topRightButton)
        topRightButton.autoPinTrailingToSuperviewMargin(withInset: 8)
        topRightButton.autoPinTopToSuperviewMargin()

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
        switch groupCall.concreteType {
        case .groupThread(let call):
            let avatarView = ConversationAvatarView(
                sizeClass: .customDiameter(96),
                localUserDisplayMode: .asLocalUser,
                badged: false
            )
            avatarView.updateWithSneakyTransactionIfNecessary {
                $0.setGroupIdWithSneakyTransaction(groupId: call.groupId.serialize().asData)
            }
            let avatarPaddingView = UIView()
            avatarPaddingView.addSubview(avatarView)
            avatarView.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)

            vStack.addArrangedSubview(avatarPaddingView)
            vStack.setCustomSpacing(16, after: avatarPaddingView)
            self.avatarView = avatarView
        case .callLink:
            break
        }

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
        callTitleLabel.addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(injectDisconnect))
        )
        callTitleLabel.isUserInteractionEnabled = true
#endif

        vStack.addArrangedSubview(callTitleLabel)

        // Make the title view as wide as possible, but don't overlap either button.
        // This gets combined with the vStack's centered alignment, so we won't ever get an unbalanced title label.
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            callTitleLabel.autoPinWidthToSuperview()
        }
        callTitleLabel.autoPinEdge(.leading, to: .trailing, of: backButton, withOffset: 13, relation: .greaterThanOrEqual)
        callTitleLabel.autoPinEdge(.trailing, to: .leading, of: topRightButton, withOffset: -13, relation: .lessThanOrEqual)

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

        groupCall.addObserver(self, syncStateImmediately: true)
    }

    override func didMoveToSuperview() {
        guard let superview = self.superview else {
            return
        }
        // The bottom of the avatar must be no more than 25% down the screen.
        // This constraint is on the avatar view container rather than the full view
        // because the label may change its number of lines,
        // and we don't want that to affect the vertical position.
        avatarView?.autoMatch(.height, to: .height, of: superview, withMultiplier: 0.25)
    }

    private func addShadow(to view: UIView) {
        view.layer.shadowOffset = .zero
        view.layer.shadowOpacity = 0.25
        view.layer.shadowRadius = 4
    }

    private func describeMembers(
        count: Int,
        names: [String],
        zeroMemberString: @autoclosure () -> String,
        oneMemberFormat: @autoclosure () -> String,
        twoMemberFormat: @autoclosure () -> String,
        manyMemberFormat: @autoclosure () -> String
    ) -> String {
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

    private func fetchGroupSizeAndMemberNamesWithSneakyTransaction(groupThreadCall: GroupThreadCall) -> (Int, [String]) {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            // FIXME: Register for notifications so we can update if someone leaves the group while the screen is up?
            guard let groupThread = TSGroupThread.fetch(forGroupId: groupThreadCall.groupId, tx: transaction) else {
                owsFailDebug("Couldn't fetch thread for active call.")
                return (0, [] as [String])
            }
            let memberNames = groupThread.sortedMemberNames(
                includingBlocked: false,
                useShortNameIfAvailable: true,
                transaction: transaction
            )
            return (memberNames.count, Array(memberNames.prefix(2)))
        }
    }

    private func updateCallStatusLabel() {
        callStatusLabel.text = self.callStatusLabelText()
    }

    private func callStatusLabelText() -> String {
        switch ringRtcCall.localDeviceState.joinState {
        case .notJoined, .joining:
            switch groupCall.concreteType {
            case .groupThread(let groupThreadCall):
                if case .incomingRing(let caller, _) = groupThreadCall.groupCallRingState {
                    return incomingRingText(caller: caller)
                }
                if let joinedMembers = ringRtcCall.peekInfo?.joinedMembers, !joinedMembers.isEmpty {
                    return whoIsHereText(joinedMembers: joinedMembers)
                }
                if ringRtcCall.peekInfo == nil, groupThreadCall.ringRestrictions.contains(.callInProgress) {
                    // If we think there might already be a call, don't show anything until we have proper peek info.
                    return ""
                }
                if groupThreadCall.ringRestrictions.isEmpty, case .shouldRing = groupThreadCall.groupCallRingState {
                    return willRingOthersText(groupThreadCall: groupThreadCall)
                } else {
                    return willNotifyOthersText(groupThreadCall: groupThreadCall)
                }
            case .callLink:
                return whoIsHereText(joinedMembers: (
                    ringRtcCall.peekInfo?.joinedMembers.nilIfEmpty
                    ?? Array(repeating: nil, count: Int(ringRtcCall.peekInfo?.deviceCountExcludingPendingDevices ?? 0))
                ))
            }
        case .pending:
            return OWSLocalizedString(
                "CALL_WAITING_TO_BE_LET_IN",
                comment: "Shown in the header below the name of the call while waiting for the host to allow you to enter the call."
            )
        case .joined:
            if ringRtcCall.localDeviceState.connectionState == .reconnecting {
                return OWSLocalizedString(
                    "GROUP_CALL_RECONNECTING",
                    comment: "Text indicating that the user has lost their connection to the call and we are reconnecting."
                )
            }
            switch groupCall.concreteType {
            case .groupThread(let groupThreadCall):
                if ringRtcCall.remoteDeviceStates.isEmpty, case .ringing = groupThreadCall.groupCallRingState {
                    return ringingOthersText(groupThreadCall: groupThreadCall)
                }
                fallthrough
            case .callLink:
                guard let peekInfo = ringRtcCall.peekInfo else {
                    return ""
                }
                if !peekInfo.pendingUsers.isEmpty {
                    return howManyAreWaitingText(count: peekInfo.pendingUsers.count)
                }
                if peekInfo.deviceCountExcludingPendingDevices > 0 {
                    return howManyAreHereText(count: Int(peekInfo.deviceCountExcludingPendingDevices))
                }
            }
            return noOneElseIsHereText()
        }
    }

    private func incomingRingText(caller: SignalServiceAddress) -> String {
        let callerName = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            SSKEnvironment.shared.contactManagerRef.displayName(for: caller, tx: transaction).resolvedValue(useShortNameIfAvailable: true)
        }
        let formatString = OWSLocalizedString(
            "GROUP_CALL_INCOMING_RING_FORMAT",
            comment: "Text explaining that someone has sent a ring to the group. Embeds {ring sender name}"
        )
        return String(format: formatString, callerName)
    }

    private func whoIsHereText(joinedMembers: [UUID?]) -> String {
        if joinedMembers.isEmpty {
            return noOneElseIsHereText()
        }
        let upToTwoKnownMemberNames: [String] = SSKEnvironment.shared.databaseStorageRef.read { tx -> [String] in
            joinedMembers
                .lazy
                .compactMap { $0 }
                .map { SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(Aci(fromUUID: $0)), tx: tx) }
                .filter { $0.hasKnownValue }
                .prefix(2)
                .map { $0.resolvedValue(useShortNameIfAvailable: true) }
        }
        let noneOneOrBothKnownMemberNames: (String, String?)? = (
            upToTwoKnownMemberNames.first.map { ($0, upToTwoKnownMemberNames.dropFirst().first) }
        )
        let otherOrUnknownMemberCount = joinedMembers.count - upToTwoKnownMemberNames.count
        switch (noneOneOrBothKnownMemberNames, otherOrUnknownMemberCount) {
        case ((let someMember, nil)?, 0):
            // exactly one member, known
            let format = OWSLocalizedString(
                "GROUP_CALL_ONE_PERSON_HERE_FORMAT",
                comment: "Text explaining that there is one person in the group call. Embeds {member name}"
            )
            return String(format: format, someMember)
        case ((let someMember, let someOtherMember?)?, 0):
            // exactly two members, both known
            let format = OWSLocalizedString(
                "GROUP_CALL_TWO_PEOPLE_HERE_FORMAT",
                comment: "Text explaining that there are two people in the group call. Embeds {{ %1$@ participant1, %2$@ participant2 }}"
            )
            return String(format: format, someMember, someOtherMember)
        case ((let someMember, let someOtherMember?)?, let otherCount):
            // two or more members, at least two known
            let format = OWSLocalizedString(
                "GROUP_CALL_MANY_PEOPLE_HERE_%d",
                tableName: "PluralAware",
                comment: "Text explaining that there are three or more people in the group call. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"
            )
            return String.localizedStringWithFormat(format, otherCount, someMember, someOtherMember)
        case ((let someMember, nil)?, let unknownCount):
            // two or more members, only one known
            let format = OWSLocalizedString(
                "GROUP_CALL_ONE_KNOWN_AND_MANY_OTHERS_HERE",
                tableName: "PluralAware",
                comment: "Text explaining that there is at least one person whose name is known in the call as well as others whose names may or may not be known."
            )
            return String.localizedStringWithFormat(format, unknownCount, someMember)
        case (nil, let unknownCount):
            // no known members
            let format = OWSLocalizedString(
                "GROUP_CALL_MANY_OTHERS_HERE",
                tableName: "PluralAware",
                comment: "Text explaining that there are people in the call whose names we don't know. The argument is how many people are in the call."
            )
            return String.localizedStringWithFormat(format, unknownCount)
        }
    }

    private func willRingOthersText(groupThreadCall: GroupThreadCall) -> String {
        let (memberCount, firstTwoNames) = fetchGroupSizeAndMemberNamesWithSneakyTransaction(groupThreadCall: groupThreadCall)
        return describeMembers(
            count: memberCount,
            names: firstTwoNames,
            zeroMemberString: "",
            oneMemberFormat: OWSLocalizedString(
                "GROUP_CALL_WILL_RING_ONE_PERSON_FORMAT",
                comment: "Text shown before the user starts a group call if the user has enabled ringing and there is one other person in the group. Embeds {member name}"
            ),
            twoMemberFormat: OWSLocalizedString(
                "GROUP_CALL_WILL_RING_TWO_PEOPLE_FORMAT",
                comment: "Text shown before the user starts a group call if the user has enabled ringing and there are two other people in the group. Embeds {{ %1$@ participant1, %2$@ participant2 }}"
            ),
            manyMemberFormat: OWSLocalizedString(
                "GROUP_CALL_WILL_RING_MANY_PEOPLE_%d",
                tableName: "PluralAware",
                comment: "Text shown before the user starts a group call if the user has enabled ringing and there are three or more other people in the group. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"
            )
        )
    }

    private func willNotifyOthersText(groupThreadCall: GroupThreadCall) -> String {
        let (memberCount, firstTwoNames) = fetchGroupSizeAndMemberNamesWithSneakyTransaction(groupThreadCall: groupThreadCall)
        return describeMembers(
            count: memberCount,
            names: firstTwoNames,
            zeroMemberString: "",
            oneMemberFormat: OWSLocalizedString(
                "GROUP_CALL_WILL_NOTIFY_ONE_PERSON_FORMAT",
                comment: "Text shown before the user starts a group call if the user has not enabled ringing and there is one other person in the group. Embeds {member name}"
            ),
            twoMemberFormat: OWSLocalizedString(
                "GROUP_CALL_WILL_NOTIFY_TWO_PEOPLE_FORMAT",
                comment: "Text shown before the user starts a group call if the user has not enabled ringing and there are two other people in the group. Embeds {{ %1$@ participant1, %2$@ participant2 }}"
            ),
            manyMemberFormat: OWSLocalizedString(
                "GROUP_CALL_WILL_NOTIFY_MANY_PEOPLE_%d",
                tableName: "PluralAware",
                comment: "Text shown before the user starts a group call if the user has not enabled ringing and there are three or more other people in the group. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"
            )
        )
    }

    private func ringingOthersText(groupThreadCall: GroupThreadCall) -> String {
        let (memberCount, firstTwoNames) = fetchGroupSizeAndMemberNamesWithSneakyTransaction(groupThreadCall: groupThreadCall)
        return describeMembers(
            count: memberCount,
            names: firstTwoNames,
            zeroMemberString: "",
            oneMemberFormat: OWSLocalizedString(
                "GROUP_CALL_IS_RINGING_ONE_PERSON_FORMAT",
                comment: "Text shown before the user starts a group call if the user has enabled ringing and there is one other person in the group. Embeds {member name}"
            ),
            twoMemberFormat: OWSLocalizedString(
                "GROUP_CALL_IS_RINGING_TWO_PEOPLE_FORMAT",
                comment: "Text shown before the user starts a group call if the user has enabled ringing and there are two other people in the group. Embeds {{ %1$@ participant1, %2$@ participant2 }}"
            ),
            manyMemberFormat: OWSLocalizedString(
                "GROUP_CALL_IS_RINGING_MANY_PEOPLE_%d",
                tableName: "PluralAware",
                comment: "Text shown before the user starts a group call if the user has enabled ringing and there are three or more other people in the group. Embeds {{ %1$@ participantCount-2, %2$@ participant1, %3$@ participant2 }}"
            )
        )
    }

    private func noOneElseIsHereText() -> String {
        return OWSLocalizedString(
            "GROUP_CALL_NO_ONE_HERE",
            comment: "Text explaining that you are the only person currently in the group call"
        )
    }

    private func howManyAreWaitingText(count: Int) -> String {
        let format = OWSLocalizedString(
            "CALL_PEOPLE_WAITING",
            tableName: "PluralAware",
            comment: "Text shown in the header of a call to indicate how many people have requested to join and need to be approved."
        )
        return String.localizedStringWithFormat(format, count)
    }

    private func howManyAreHereText(count: Int) -> String {
        let format = OWSLocalizedString(
            "CALL_PEOPLE_HERE",
            tableName: "PluralAware",
            comment: "Text shown in the header of a call to indicate how many people are present."
        )
        return String.localizedStringWithFormat(format, count)
    }

    private func updateCallTitleLabel() {
        callTitleLabel.text = self.callTitleLabelText()
    }

    private func callTitleLabelText() -> String {
        if
            ringRtcCall.localDeviceState.joinState == .joined,
            let firstMember = ringRtcCall.remoteDeviceStates.sortedBySpeakerTime.first,
            firstMember.presenting == true
        {
            let presentingName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                SSKEnvironment.shared.contactManagerRef.displayName(for: SignalServiceAddress(Aci(fromUUID: firstMember.userId)), tx: tx).resolvedValue(useShortNameIfAvailable: true)
            }
            let formatString = OWSLocalizedString(
                "GROUP_CALL_PRESENTING_FORMAT",
                comment: "Text explaining that a member is presenting. Embeds {member name}"
            )
            return String(format: formatString, presentingName)
        }
        switch groupCall.concreteType {
        case .groupThread(let groupThreadCall):
            // FIXME: This should auto-update if the group name changes.
            let databaseStorage = SSKEnvironment.shared.databaseStorageRef
            return databaseStorage.read { tx in
                let contactManager = SSKEnvironment.shared.contactManagerRef
                guard let groupThread = TSGroupThread.fetch(forGroupId: groupThreadCall.groupId, tx: tx) else {
                    return TSGroupThread.defaultGroupName
                }
                return contactManager.displayName(for: groupThread, transaction: tx)
            }
        case .callLink(let call):
            return call.callLinkState.localizedName
        }
    }

    // For testing abnormal scenarios.
    @objc
    private func injectDisconnect() {
        ringRtcCall.disconnect()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension CallHeader: GroupCallObserver {
    func groupCallLocalDeviceStateChanged(_ call: GroupCall) {
        if call.hasJoinedOrIsWaitingForAdminApproval {
            gradientView.isHidden = false
            avatarView?.isHidden = true // hide the container
        } else {
            gradientView.isHidden = true
            avatarView?.isHidden = false
        }

        updateCallStatusLabel()
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        updateCallStatusLabel()
    }

    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        updateCallTitleLabel()
        updateCallStatusLabel()
    }

    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason) {
        updateCallStatusLabel()
    }
}
