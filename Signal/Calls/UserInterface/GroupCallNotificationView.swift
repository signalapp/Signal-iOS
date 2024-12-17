//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit

class GroupCallNotificationView: UIView {
    private let groupCall: GroupCall
    private let ringRtcCall: SignalRingRTC.GroupCall
    private var callService: CallService { AppEnvironment.shared.callService }

    private struct ActiveMember: Hashable {
        let demuxId: UInt32
        let aci: Aci
        var address: SignalServiceAddress { return SignalServiceAddress(aci) }
    }
    private var activeMembers = Set<ActiveMember>()
    private var membersPendingJoinNotification = Set<ActiveMember>()
    private var membersPendingLeaveNotification = Set<ActiveMember>()

    init(groupCall: GroupCall) {
        self.groupCall = groupCall
        self.ringRtcCall = groupCall.ringRtcCall
        super.init(frame: .zero)

        groupCall.addObserver(self, syncStateImmediately: true)

        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hasJoined = false
    private func updateActiveMembers() {
        let newActiveMembers = Set(ringRtcCall.remoteDeviceStates.values.map {
            ActiveMember(demuxId: $0.demuxId, aci: Aci(fromUUID: $0.userId))
        })

        if hasJoined {
            let joinedMembers = newActiveMembers.subtracting(activeMembers)
            let leftMembers = activeMembers.subtracting(newActiveMembers)

            membersPendingJoinNotification.subtract(leftMembers)
            membersPendingJoinNotification.formUnion(joinedMembers)

            membersPendingLeaveNotification.subtract(joinedMembers)
            membersPendingLeaveNotification.formUnion(leftMembers)
        } else {
            hasJoined = ringRtcCall.localDeviceState.joinState == .joined
        }

        activeMembers = newActiveMembers

        presentNextNotificationIfNecessary()
    }

    private var isPresentingNotification = false
    private func presentNextNotificationIfNecessary() {
        guard !isPresentingNotification else { return }

        guard let bannerView: BannerView = {
            if membersPendingJoinNotification.count > 0 {
                callService.audioService.playJoinSound()
                let addresses = membersPendingJoinNotification.map { $0.address }
                membersPendingJoinNotification.removeAll()
                return BannerView(addresses: addresses, action: .join)
            } else if membersPendingLeaveNotification.count > 0 {
                callService.audioService.playLeaveSound()
                let addresses = membersPendingLeaveNotification.map { $0.address }
                membersPendingLeaveNotification.removeAll()
                return BannerView(addresses: addresses, action: .leave)
            } else {
                return nil
            }
        }() else { return }

        isPresentingNotification = true

        addSubview(bannerView)
        bannerView.autoHCenterInSuperview()

        // Prefer to be full width, but don't exceed the maximum width
        bannerView.autoSetDimension(.width, toSize: 512, relation: .lessThanOrEqual)
        bannerView.autoMatch(
            .width,
            to: .width,
            of: self,
            withOffset: -(layoutMargins.left + layoutMargins.right),
            relation: .lessThanOrEqual
        )
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            bannerView.autoPinWidthToSuperviewMargins()
        }

        let onScreenConstraint = bannerView.autoPinEdge(toSuperviewMargin: .top)
        onScreenConstraint.isActive = false

        let offScreenConstraint = bannerView.autoPinEdge(.bottom, to: .top, of: self)

        layoutIfNeeded()

        UIView.animate(withDuration: 0.35, delay: 0) {
            offScreenConstraint.isActive = false
            onScreenConstraint.isActive = true

            self.layoutIfNeeded()
        } completion: { _ in
            UIView.animate(withDuration: 0.35, delay: 2, options: .curveEaseInOut) {
                onScreenConstraint.isActive = false
                offScreenConstraint.isActive = true

                self.layoutIfNeeded()
            } completion: { _ in
                bannerView.removeFromSuperview()
                self.isPresentingNotification = false
                self.presentNextNotificationIfNecessary()
            }
        }
    }
}

extension GroupCallNotificationView: GroupCallObserver {
    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        updateActiveMembers()
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        AssertIsOnMainThread()
        updateActiveMembers()
    }

    func groupCallEnded(_ call: GroupCall, reason: GroupCallEndReason) {
        AssertIsOnMainThread()

        hasJoined = false
        activeMembers.removeAll()
        membersPendingJoinNotification.removeAll()
        membersPendingLeaveNotification.removeAll()

        updateActiveMembers()
    }
}

private class BannerView: UIView {
    enum Action: Equatable { case join, leave }

    init(addresses: [SignalServiceAddress], action: Action) {
        super.init(frame: .zero)

        owsAssertDebug(!addresses.isEmpty)

        autoSetDimension(.height, toSize: 64, relation: .greaterThanOrEqual)
        layer.cornerRadius = 8
        clipsToBounds = true

        let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        addSubview(blurEffectView)
        blurEffectView.autoPinEdgesToSuperviewEdges()
        backgroundColor = .ows_blackAlpha40

        let displayNames = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerImplRef.sortedComparableNames(for: addresses, tx: tx)
        }.sorted(by: <).map { $0.resolvedValue() }

        let actionText: String
        if displayNames.count > 2 {
            let formatText = action == .join
                ? OWSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_MANY_JOINED_%d", tableName: "PluralAware",
                    comment: "Copy explaining that many new users have joined the group call. Embeds {number of additional members}, {first member name}, {second member name}"
                )
                : OWSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_MANY_LEFT_%d", tableName: "PluralAware",
                    comment: "Copy explaining that many users have left the group call. Embeds {number of additional members}, {first member name}, {second member name}"
                )
            actionText = String.localizedStringWithFormat(formatText, displayNames.count - 2, displayNames[0], displayNames[1])
        } else if displayNames.count > 1 {
            let formatText = action == .join
                ? OWSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_TWO_JOINED_FORMAT",
                    comment: "Copy explaining that two users have joined the group call. Embeds {first member name}, {second member name}"
                )
                : OWSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_TWO_LEFT_FORMAT",
                    comment: "Copy explaining that two users have left the group call. Embeds {first member name}, {second member name}"
                )
            actionText = String(format: formatText, displayNames[0], displayNames[1])
        } else {
            let formatText = action == .join
                ? OWSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_ONE_JOINED_FORMAT",
                    comment: "Copy explaining that a user has joined the group call. Embeds {member name}"
                )
                : OWSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_ONE_LEFT_FORMAT",
                    comment: "Copy explaining that a user has left the group call. Embeds {member name}"
                )
            actionText = String(format: formatText, displayNames[0])
        }

        let hStack = UIStackView()
        hStack.spacing = 12
        hStack.axis = .horizontal
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()

        if addresses.count == 1, let address = addresses.first {
            let avatarContainer = UIView()
            hStack.addArrangedSubview(avatarContainer)
            avatarContainer.autoSetDimension(.width, toSize: 40)

            let avatarView = UIImageView()
            avatarView.layer.cornerRadius = 20
            avatarView.clipsToBounds = true
            avatarContainer.addSubview(avatarView)
            avatarView.autoPinWidthToSuperview()
            avatarView.autoVCenterInSuperview()
            avatarView.autoMatch(.height, to: .width, of: avatarView)

            if address.isLocalAddress,
               let avatarImage = SSKEnvironment.shared.profileManagerRef.localProfileAvatarImage {
                avatarView.image = avatarImage
            } else {
                let avatar = SSKEnvironment.shared.avatarBuilderRef.avatarImageWithSneakyTransaction(forAddress: address,
                                                                                                     diameterPoints: 40,
                                                                                                     localUserDisplayMode: .asUser)
                avatarView.image = avatar
            }
        }

        let label = UILabel()
        hStack.addArrangedSubview(label)
        label.setCompressionResistanceHorizontalHigh()
        label.numberOfLines = 0
        label.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        label.textColor = .ows_white
        label.text = actionText

        hStack.addArrangedSubview(.hStretchingSpacer())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
