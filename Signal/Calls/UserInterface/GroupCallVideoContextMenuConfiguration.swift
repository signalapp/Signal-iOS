//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import UIKit

enum GroupCallVideoContextMenuConfiguration {
    private static var contactManager: ContactManager { SSKEnvironment.shared.contactManagerRef }
    private static var db: DB { DependenciesBridge.shared.db }

    static func build(
        call: SignalCall,
        groupCall: GroupCall,
        ringRtcCall: SignalRingRTC.GroupCall,
        remoteDevice: RemoteDeviceState,
        interactionProvider: @escaping () -> UIContextMenuInteraction?,
    ) -> UIContextMenuConfiguration {
        return UIContextMenuConfiguration(
            previewProvider: {
                // A dedicated "call member" preview lets us avoid issues with
                // cell reuse, add/remove, etc in the various group-call video
                // collection views.
                return GroupCallVideoContextMenuPreviewController(
                    demuxId: remoteDevice.demuxId,
                    call: call,
                    groupCall: groupCall,
                    interactionProvider: interactionProvider,
                )
            },
            actionProvider: { _ in
                let contactDisplayName: DisplayName = db.read { tx in
                    return contactManager.displayName(
                        for: SignalServiceAddress(remoteDevice.aci),
                        tx: tx,
                    )
                }
                let actions = GroupCallContextMenuActionsBuilder.build(
                    demuxId: remoteDevice.demuxId,
                    contactAci: remoteDevice.aci,
                    isAudioMuted: remoteDevice.audioMuted == true,
                    ringRtcGroupCall: ringRtcCall,
                )

                return UIMenu(
                    title: contactDisplayName.resolvedValue(),
                    children: actions,
                )
            },
        )
    }
}

// MARK: -

/// Wraps a `CallMemberView` for the purposes of a context-menu preview.
private class GroupCallVideoContextMenuPreviewController: UIViewController, GroupCallObserver {
    private let demuxId: DemuxId
    private let interactionProvider: () -> UIContextMenuInteraction?

    private weak var call: SignalCall?
    private weak var groupCall: GroupCall?

    private lazy var callMemberView = CallMemberView(type: .remoteInGroup(.contextMenuPreview))

    init(
        demuxId: DemuxId,
        call: SignalCall,
        groupCall: GroupCall,
        interactionProvider: @escaping () -> UIContextMenuInteraction?,
    ) {
        self.demuxId = demuxId
        self.call = call
        self.groupCall = groupCall
        self.interactionProvider = interactionProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { owsFail("") }

    override func viewDidLoad() {
        super.viewDidLoad()

        callMemberView.applyChangesToCallMemberViewAndVideoView { _view in
            view.addSubview(_view)
            _view.autoPinEdgesToSuperviewEdges()
        }

        reconfigureCallMemberView()
        groupCall?.addObserver(self)
    }

    // MARK: - GroupCallObserver

    func groupCallRemoteDeviceStatesChanged(_ call: GroupCall) {
        reconfigureCallMemberView()
    }

    func groupCallPeekChanged(_ call: GroupCall) {
        reconfigureCallMemberView()
    }

    func groupCallEnded(_ call: GroupCall, reason: CallEndReason) {
        reconfigureCallMemberView()
    }

    func groupCallReceivedRaisedHands(_ call: GroupCall, raisedHands: [DemuxId]) {
        reconfigureCallMemberView()
    }

    private func reconfigureCallMemberView() {
        guard
            let call,
            let groupCall,
            let remoteDevice = groupCall.ringRtcCall.remoteDeviceStates[demuxId]
        else {
            return
        }

        callMemberView.configure(call: call, remoteGroupMemberDeviceState: remoteDevice)

        if let interaction = interactionProvider() {
            let actions = GroupCallContextMenuActionsBuilder.build(
                demuxId: remoteDevice.demuxId,
                contactAci: remoteDevice.aci,
                isAudioMuted: remoteDevice.audioMuted == true,
                ringRtcGroupCall: groupCall.ringRtcCall,
            )

            interaction.updateVisibleMenu { menu in
                return menu.replacingChildren(actions)
            }
        }
    }
}
