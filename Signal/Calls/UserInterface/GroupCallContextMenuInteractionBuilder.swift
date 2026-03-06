//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import SignalServiceKit
import UIKit

enum GroupCallContextMenuInteractionBuilder {
    static func build(
        demuxId: SignalRingRTC.DemuxId,
        contactAci: Aci,
        contactName: String,
        isAudioMuted: Bool,
        ringRtcGroupCall: SignalRingRTC.GroupCall,
    ) -> UIContextMenuConfiguration? {
        guard BuildFlags.RemoteMute.send else {
            return nil
        }

        var contextMenuActions: [UIAction] = []

        if !isAudioMuted {
            contextMenuActions.append(UIAction(
                title: "Mute Audio",
                handler: { [weak ringRtcGroupCall] _ in
                    guard let ringRtcGroupCall else { return }

                    MainActor.assumeIsolated {
                        ringRtcGroupCall.sendRemoteMuteRequest(demuxId)
                    }
                },
            ))
        }

        return UIContextMenuConfiguration(
            actionProvider: { _ in
                return UIMenu(
                    title: contactName,
                    children: contextMenuActions,
                )
            },
        )
    }
}
