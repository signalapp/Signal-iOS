//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SignalRingRTC
import SignalServiceKit
import SignalUI

@MainActor
class CallLinkAdminManager {
    typealias CallLinkState = SignalServiceKit.CallLinkState

    private let rootKey: CallLinkRootKey
    private let adminPasskey: Data
    let callNamePublisher: CurrentValueSubject<String?, Never>
    private(set) var callLinkState: CallLinkState?
    var didUpdateCallLinkState: (@MainActor (CallLinkState) -> Void)?

    init(rootKey: CallLinkRootKey, adminPasskey: Data, callLinkState: CallLinkState?) {
        self.rootKey = rootKey
        self.adminPasskey = adminPasskey
        self.callLinkState = callLinkState
        self.callNamePublisher = .init(callLinkState?.name)
    }

    // MARK: Convenience properties

    var editCallNameButtonTitle: String {
        callLinkState?.name != nil ? CallStrings.editCallName : CallStrings.addCallName
    }

    // MARK: Actions

    func updateName(_ name: String) async throws {
        try await updateCallLink(
            { callLinkManager, authCredential in
                return try await callLinkManager.updateCallLinkName(
                    name,
                    rootKey: self.rootKey,
                    adminPasskey: self.adminPasskey,
                    authCredential: authCredential
                )
            }
        )
    }

    func toggleApproveAllMembersWithActivityIndicator(
        _ sender: UISwitch,
        from viewController: UIViewController
    ) {
        let isOn = sender.isOn
        ModalActivityIndicatorViewController.present(
            fromViewController: viewController,
            presentationDelay: 0.25,
            asyncBlock: { modal in
                let updateResult = await Result {
                    try await self.updateCallLink { callLinkManager, authCredential in
                        return try await callLinkManager.updateCallLinkRestrictions(
                            requiresAdminApproval: isOn,
                            rootKey: self.rootKey,
                            adminPasskey: self.adminPasskey,
                            authCredential: authCredential
                        )
                    }
                }
                modal.dismissIfNotCanceled {
                    do {
                        _ = try updateResult.get()
                    } catch {
                        if error.isNetworkFailureOrTimeout {
                            // [CallLink] TODO: Refresh switch UI, as we don't know whether the operation succeeded or failed.
                        } else {
                            Logger.warn("Call link approve members switch update failed with error \(error)")
                            // The operation definitely failed. Revert switch state.
                            sender.isOn = !isOn
                            OWSActionSheets.showActionSheet(
                                title: CallStrings.callLinkErrorSheetTitle,
                                message: CallStrings.callLinkUpdateErrorSheetDescription,
                                fromViewController: viewController
                            )
                        }
                    }
                }
            }
        )
    }

    // MARK: Private

    private func updateCallLink(
        _ performUpdate: (CallLinkManager, SignalServiceKit.CallLinkAuthCredential) async throws -> CallLinkState
    ) async throws {
        let callLinkManager = AppEnvironment.shared.callService.callLinkManager
        let callLinkStateUpdater = AppEnvironment.shared.callService.callLinkStateUpdater
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        _ = try await callLinkStateUpdater.updateExclusively(rootKey: rootKey) { authCredential in
            let callLinkState = try await performUpdate(callLinkManager, authCredential)
            await databaseStorage.awaitableWrite { [rootKey, adminPasskey] tx in
                CallLinkUpdateMessageSender(
                    messageSenderJobQueue: SSKEnvironment.shared.messageSenderJobQueueRef
                ).sendCallLinkUpdateMessage(rootKey: rootKey, adminPasskey: adminPasskey, tx: tx)
            }
            self.callLinkState = callLinkState
            self.didUpdateCallLinkState?(callLinkState)
            self.callNamePublisher.send(callLinkState.name)
            return callLinkState
        }
    }
}
