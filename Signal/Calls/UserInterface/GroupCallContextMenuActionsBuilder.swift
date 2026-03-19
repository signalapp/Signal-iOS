//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import SignalUI
import UIKit

enum GroupCallContextMenuActionsBuilder {
    static func build(
        demuxId: SignalRingRTC.DemuxId,
        contactAci: Aci,
        isAudioMuted: Bool,
        ringRtcGroupCall: SignalRingRTC.GroupCall,
    ) -> [UIAction] {
        var contextMenuActions: [UIAction] = []

        if
            BuildFlags.RemoteMute.send,
            !isAudioMuted
        {
            contextMenuActions.append(UIAction(
                title: OWSLocalizedString(
                    "GROUP_CALL_CONTEXT_MENU_MUTE_AUDIO",
                    comment: "Context menu action to mute a call participant's audio.",
                ),
                image: .micSlash,
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
                    AppEnvironment.shared.windowManagerRef.minimizeCallIfNeeded()
                    SignalApp.shared.presentConversationForAddress(
                        SignalServiceAddress(contactAci),
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
                    AppEnvironment.shared.windowManagerRef.minimizeCallIfNeeded()
                    ProfileSheetSheetCoordinator(
                        address: SignalServiceAddress(contactAci),
                        groupViewHelper: nil,
                        spoilerState: SpoilerRenderState(),
                    ).presentAppropriateSheet(from: frontmostVC)
                }
            },
        ))

        return contextMenuActions
    }
}
