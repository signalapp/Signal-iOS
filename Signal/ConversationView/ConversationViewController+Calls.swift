//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

public extension ConversationViewController {

    var isCurrentCallForThread: Bool {
        switch AppEnvironment.shared.callService.callServiceState.currentCall?.mode {
        case nil:
            return false
        case .individual(let call):
            return call.thread.uniqueId == thread.uniqueId
        case .groupThread(let call):
            return call.groupId.serialize() == (thread as? TSGroupThread)?.groupId
        case .callLink:
            return false
        }
    }

    var isCallingSupported: Bool {
        canCall
    }

    var canCall: Bool {
        ConversationViewController.canCall(threadViewModel: threadViewModel)
    }

    private var callStarterContext: CallStarter.Context {
        .init(
            blockingManager: SSKEnvironment.shared.blockingManagerRef,
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            callService: AppEnvironment.shared.callService,
        )
    }

    @objc
    func showGroupLobbyOrActiveCall() {
        guard let groupId = try? (thread as? TSGroupThread)?.groupIdentifier else {
            owsFailDebug("Tried to present group call for non-group thread.")
            return
        }

        _ = CallStarter(
            groupId: groupId,
            context: self.callStarterContext,
        ).startCall(from: self)
    }

    @objc
    func startIndividualAudioCall() {
        startIndividualCall(withVideo: false)
    }

    @objc
    func startIndividualVideoCall() {
        startIndividualCall(withVideo: true)
    }

    func startIndividualCall(withVideo: Bool) {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        let startCallResult = CallStarter(
            contactThread: contactThread,
            withVideo: withVideo,
            context: self.callStarterContext,
        ).startCall(from: self)

        switch startCallResult {
        case .callStarted:
            NotificationCenter.default.post(name: ChatListViewController.clearSearch, object: nil)
        case .callNotStarted:
            break
        case .promptedToUnblock:
            self.userHasScrolled = false
        }

    }

    func refreshCallState() {
        if let groupId = try? (thread as? TSGroupThread)?.groupIdentifier {
            Task {
                await SSKEnvironment.shared.groupCallManagerRef.peekGroupCallAndUpdateThread(
                    forGroupId: groupId,
                    peekTrigger: .localEvent(),
                )
            }
        }
    }
}
