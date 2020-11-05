//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

class GroupCallNotificationView: UIView {
    private let call: SignalCall

    private struct ActiveMember: Hashable {
        let demuxId: UInt32
        let uuid: UUID
        var address: SignalServiceAddress { return SignalServiceAddress(uuid: uuid) }
    }
    private var activeMembers = Set<ActiveMember>()
    private var membersPendingJoinNotification = Set<ActiveMember>()
    private var membersPendingLeaveNotification = Set<ActiveMember>()

    init(call: SignalCall) {
        self.call = call
        super.init(frame: .zero)

        call.addObserverAndSyncState(observer: self)

        isUserInteractionEnabled = false
    }

    deinit { call.removeObserver(self) }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateActiveMembers() {
        let newActiveMembers = Set(call.groupCall.remoteDeviceStates.values.map {
            ActiveMember(demuxId: $0.demuxId, uuid: $0.userId)
        })

        let joinedMembers = newActiveMembers.subtracting(activeMembers)
        let leftMembers = activeMembers.subtracting(newActiveMembers)

        membersPendingJoinNotification.subtract(leftMembers)
        membersPendingJoinNotification.formUnion(joinedMembers)

        membersPendingLeaveNotification.subtract(joinedMembers)
        membersPendingLeaveNotification.formUnion(leftMembers)

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
        bannerView.autoPinWidthToSuperviewMargins()

        let onScreenConstraint = bannerView.autoPinEdge(toSuperviewMargin: .top)
        onScreenConstraint.isActive = false

        let offScreenConstraint = bannerView.autoPinEdge(.bottom, to: .top, of: self)

        layoutIfNeeded()

        firstly(on: .main) {
            UIView.animate(.promise, duration: 0.35) {
                offScreenConstraint.isActive = false
                onScreenConstraint.isActive = true

                self.layoutIfNeeded()
            }
        }.then(on: .main) { _ in
            UIView.animate(.promise, duration: 0.35, delay: 2, options: .curveEaseInOut) {
                onScreenConstraint.isActive = false
                offScreenConstraint.isActive = true

                self.layoutIfNeeded()
            }
        }.done(on: .main) { _ in
            bannerView.removeFromSuperview()
            self.isPresentingNotification = false
            self.presentNextNotificationIfNecessary()
        }
    }
}

extension GroupCallNotificationView: CallObserver {
    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {}

    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateActiveMembers()
    }

    func groupCallJoinedMembersChanged(_ call: SignalCall) {
        AssertIsOnMainThread()
        owsAssertDebug(call.isGroupCall)

        updateActiveMembers()
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {}

    func groupCallRequestMembershipProof(_ call: SignalCall) {}
    func groupCallRequestGroupMembers(_ call: SignalCall) {}

    func individualCallStateDidChange(_ call: SignalCall, state: CallState) {}
    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool) {}
    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool) {}
    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool) {}
}

private class BannerView: UIView {
    enum Action: Equatable { case join, leave }

    init(addresses: [SignalServiceAddress], action: Action) {
        super.init(frame: .zero)

        owsAssertDebug(!addresses.isEmpty)

        autoSetDimension(.height, toSize: 64, relation: .greaterThanOrEqual)
        layer.cornerRadius = 8
        clipsToBounds = true

        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundColor = .ows_blackAlpha80
        } else {
            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
            backgroundColor = .ows_blackAlpha40
        }

        let displayNames = databaseStorage.uiRead { transaction in
            return addresses.map { address in
                return (
                    displayName: self.contactsManager.displayName(for: address, transaction: transaction),
                    comparableName: self.contactsManager.comparableName(for: address, transaction: transaction)
                )
            }
        }.sorted { $0.comparableName.caseInsensitiveCompare($1.comparableName) == .orderedAscending }
        .map { $0.displayName }

        let actionText: String
        if displayNames.count > 2 {
            let formatText = action == .join
                ? NSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_MANY_JOINED_FORMAT",
                    comment: "Copy explaining that many new users have joined the group call. Embeds {first member name}, {second member name}, {number of additional members}"
                )
                : NSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_MANY_LEFT_FORMAT",
                    comment: "Copy explaining that many users have left the group call. Embeds {first member name}, {second member name}, {number of additional members}"
                )
            actionText = String(format: formatText, displayNames[0], displayNames[1], displayNames.count - 2)
        } else if displayNames.count > 1 {
            let formatText = action == .join
                ? NSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_TWO_JOINED_FORMAT",
                    comment: "Copy explaining that two users have joined the group call. Embeds {first member name}, {second member name}"
                )
                : NSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_TWO_LEFT_FORMAT",
                    comment: "Copy explaining that two users have left the group call. Embeds {first member name}, {second member name}"
                )
            actionText = String(format: formatText, displayNames[0], displayNames[1])
        } else {
            let formatText = action == .join
                ? NSLocalizedString(
                    "GROUP_CALL_NOTIFICATION_ONE_JOINED_FORMAT",
                    comment: "Copy explaining that a user has joined the group call. Embeds {member name}"
                )
                : NSLocalizedString(
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

            let conversationColorName = databaseStorage.uiRead { transaction in
                return self.contactsManager.conversationColorName(for: address, transaction: transaction)
            }

            let avatarBuilder = OWSContactAvatarBuilder(
                address: address,
                colorName: conversationColorName,
                diameter: 40
            )

            if address.isLocalAddress {
                avatarView.image = OWSProfileManager.shared().localProfileAvatarImage() ?? avatarBuilder.buildDefaultImage()
            } else {
                avatarView.image = avatarBuilder.build()
            }
        }

        let label = UILabel()
        hStack.addArrangedSubview(label)
        label.numberOfLines = 0
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold
        label.textColor = .ows_white
        label.text = actionText
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
