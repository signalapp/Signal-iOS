//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI
import UIKit

enum GroupCallVideoContextMenuConfiguration {
    private static var contactManager: ContactManager { SSKEnvironment.shared.contactManagerRef }
    private static var db: DB { DependenciesBridge.shared.db }
    private static var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }
    private static var windowManager: WindowManager { AppEnvironment.shared.windowManagerRef }

    static func build(
        call: SignalCall,
        groupCall: GroupCall,
        ringRtcCall: SignalRingRTC.GroupCall,
        remoteDevice: RemoteDeviceState,
        interactionProvider: @escaping () -> UIContextMenuInteraction?,
    ) -> UIContextMenuConfiguration {
        return build(
            call: call,
            groupCall: groupCall,
            ringRtcCall: ringRtcCall,
            demuxId: remoteDevice.demuxId,
            aci: remoteDevice.aci,
            isAudioMuted: remoteDevice.audioMuted,
            interactionProvider: interactionProvider,
        )
    }

    static func build(
        call: SignalCall,
        groupCall: GroupCall,
        ringRtcCall: SignalRingRTC.GroupCall,
        demuxId: DemuxId,
        aci: Aci,
        isAudioMuted: Bool?,
        interactionProvider: @escaping () -> UIContextMenuInteraction?,
    ) -> UIContextMenuConfiguration {
        let displayName: String = db.read { tx in
            return contactManager.displayName(
                for: SignalServiceAddress(aci),
                tx: tx,
            ).resolvedValue()
        }

        return UIContextMenuConfiguration(
            previewProvider: {
                // A dedicated "call member" preview lets us avoid issues with
                // cell reuse, add/remove, etc in the various group-call video
                // collection views.
                return GroupCallVideoContextMenuPreviewController(
                    demuxId: demuxId,
                    aci: aci,
                    displayName: displayName,
                    call: call,
                    groupCall: groupCall,
                    interactionProvider: interactionProvider,
                )
            },
            actionProvider: { _ in
                let actions = contextMenuActions(
                    demuxId: demuxId,
                    aci: aci,
                    displayName: displayName,
                    isAudioMuted: isAudioMuted == true,
                    groupCall: groupCall,
                    ringRtcGroupCall: ringRtcCall,
                )

                return UIMenu(
                    title: displayName,
                    children: actions,
                )
            },
        )
    }

    static func contextMenuActions(
        demuxId: SignalRingRTC.DemuxId,
        aci: Aci,
        displayName: String,
        isAudioMuted: Bool,
        groupCall: GroupCall,
        ringRtcGroupCall: SignalRingRTC.GroupCall,
    ) -> [UIAction] {
        var contextMenuActions: [UIAction] = []

        if BuildFlags.RemoteMute.send {
            let attributes: UIMenuElement.Attributes = isAudioMuted ? .disabled : []

            contextMenuActions.append(UIAction(
                title: OWSLocalizedString(
                    "GROUP_CALL_CONTEXT_MENU_MUTE_AUDIO",
                    comment: "Context menu action to mute a call participant's audio.",
                ),
                image: .micSlash,
                attributes: attributes,
                handler: { [weak ringRtcGroupCall] _ in
                    guard let ringRtcGroupCall else { return }

                    MainActor.assumeIsolated {
                        ringRtcGroupCall.sendRemoteMuteRequest(demuxId)
                    }
                },
            ))
        }

        contextMenuActions.append(UIAction(
            title: OWSLocalizedString(
                "GROUP_CALL_CONTEXT_MENU_GO_TO_CHAT",
                comment: "Context menu action to navigate to the chat with a call participant.",
            ),
            image: .arrowSquareUprightLight,
            handler: { _ in
                MainActor.assumeIsolated {
                    windowManager.minimizeCallIfNeeded()
                    SignalApp.shared.presentConversationForAddress(
                        SignalServiceAddress(aci),
                        animated: true,
                    )
                }
            },
        ))

        contextMenuActions.append(UIAction(
            title: OWSLocalizedString(
                "GROUP_CALL_CONTEXT_MENU_PROFILE_DETAILS",
                comment: "Context menu action to view a call participant's profile details.",
            ),
            image: .personCircle,
            handler: { _ in
                guard let frontmostVC = CurrentAppContext().frontmostViewController() else {
                    return
                }

                MainActor.assumeIsolated {
                    windowManager.minimizeCallIfNeeded()
                    ProfileSheetSheetCoordinator(
                        address: SignalServiceAddress(aci),
                        groupViewHelper: nil,
                        spoilerState: SpoilerRenderState(),
                    ).presentAppropriateSheet(from: frontmostVC)
                }
            },
        ))

        if
            let callLinkCall = groupCall as? CallLinkCall,
            callLinkCall.isAdmin,
            let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction,
            !localIdentifiers.contains(serviceId: aci)
        {
            contextMenuActions.append(UIAction(
                title: OWSLocalizedString(
                    "GROUP_CALL_CONTEXT_MENU_REMOVE_FROM_CALL",
                    comment: "Context menu action to remove a call participant from the call.",
                ),
                image: .minusCircle,
                attributes: .destructive,
                handler: { _ in
                    removeFromCallWithConfirmation(
                        demuxId: demuxId,
                        displayName: displayName,
                        ringRtcGroupCall: ringRtcGroupCall,
                    )
                },
            ))
        }

        return contextMenuActions
    }

    private static func removeFromCallWithConfirmation(
        demuxId: DemuxId,
        displayName: String,
        ringRtcGroupCall: SignalRingRTC.GroupCall,
    ) {
        let actionSheet = ActionSheetController(
            title: String(
                format: OWSLocalizedString(
                    "GROUP_CALL_REMOVE_MEMBER_CONFIRMATION_ACTION_SHEET_TITLE",
                    comment: "Title for action sheet confirming removal of a member from a group call. embeds {{ name }}",
                ),
                displayName,
            ),
        )
        actionSheet.overrideUserInterfaceStyle = .dark

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUP_CALL_REMOVE_MEMBER_CONFIRMATION_ACTION_SHEET_REMOVE_ACTION",
                comment: "Label for the button to confirm removing a member from a group call.",
            ),
        ) { _ in
            ringRtcGroupCall.removeClient(demuxId: demuxId)
        })

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUP_CALL_REMOVE_MEMBER_CONFIRMATION_ACTION_SHEET_BLOCK_ACTION",
                comment: "Label for a button to block a member from a group call.",
            ),
        ) { _ in
            ringRtcGroupCall.blockClient(demuxId: demuxId)
        })

        actionSheet.addAction(.cancel)

        guard
            let frontmostCallViewController = windowManager.callViewWindow
                .findFrontmostViewController(ignoringAlerts: true)
        else {
            owsFailDebug("Missing frontmostViewController from call window: how?")
            return
        }

        frontmostCallViewController.presentActionSheet(actionSheet)
    }
}

// MARK: -

/// Wraps a `CallMemberView` for the purposes of a context-menu preview.
private class GroupCallVideoContextMenuPreviewController: UIViewController, GroupCallObserver {
    private let demuxId: DemuxId
    private let aci: Aci
    private let displayName: String
    private let interactionProvider: () -> UIContextMenuInteraction?

    private weak var call: SignalCall?
    private weak var groupCall: GroupCall?

    private lazy var callMemberView = CallMemberView(type: .remoteInGroup(.contextMenuPreview))

    init(
        demuxId: DemuxId,
        aci: Aci,
        displayName: String,
        call: SignalCall,
        groupCall: GroupCall,
        interactionProvider: @escaping () -> UIContextMenuInteraction?,
    ) {
        self.demuxId = demuxId
        self.aci = aci
        self.displayName = displayName
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
            let actions = GroupCallVideoContextMenuConfiguration.contextMenuActions(
                demuxId: demuxId,
                aci: aci,
                displayName: displayName,
                isAudioMuted: remoteDevice.audioMuted == true,
                groupCall: groupCall,
                ringRtcGroupCall: groupCall.ringRtcCall,
            )

            interaction.updateVisibleMenu { menu in
                return menu.replacingChildren(actions)
            }
        }
    }
}
