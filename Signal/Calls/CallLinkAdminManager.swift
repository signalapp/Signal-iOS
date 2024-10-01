//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SignalRingRTC
import SignalServiceKit
import SignalUI

class CallLinkAdminManager {
    typealias CallLinkState = SignalServiceKit.CallLinkState

    private let callLink: CallLink
    private let adminPasskey: Data
    let callLinkStatePublisher: CurrentValueSubject<CallLinkState, Never>
    var callLinkState: CallLinkState { callLinkStatePublisher.value }

    init(callLink: CallLink, adminPasskey: Data, callLinkState: CallLinkState) {
        self.callLink = callLink
        self.adminPasskey = adminPasskey
        self.callLinkStatePublisher = .init(callLinkState)
    }

    // MARK: Convenience properties

    var editCallNameButtonTitle: String {
        callLinkState.name != nil ? CallStrings.editCallName : CallStrings.addCallName
    }

    // MARK: Actions

    func updateName(_ name: String) async throws {
        try await updateCallLink(
            { callLinkManager, authCredential in
                return try await callLinkManager.updateCallLinkName(
                    name,
                    rootKey: self.callLink.rootKey,
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
            asyncBlock: { [weak self] modal in
                guard let self else { return }
                let updateResult = await Result { [weak self] in
                    guard let self else { return }
                    try await self.updateCallLink { callLinkManager, authCredential in
                        return try await callLinkManager.updateCallLinkRestrictions(
                            requiresAdminApproval: isOn,
                            rootKey: self.callLink.rootKey,
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

    private var priorTask: Task<Void, any Error>?
    private func updateCallLink(
        _ performUpdate: @escaping (_ callLinkManager: CallLinkManager, _ authCredential: SignalServiceKit.CallLinkAuthCredential) async throws -> CallLinkState
    ) async throws {
        let priorTask = self.priorTask
        let newTask = Task {
            try? await priorTask?.value
            return try await self._updateCallLink(performUpdate)
        }
        self.priorTask = newTask
        return try await newTask.value
    }

    private func _updateCallLink(
        _ performUpdate: (CallLinkManager, SignalServiceKit.CallLinkAuthCredential) async throws -> CallLinkState
    ) async throws {
        let authCredentialManager = AppEnvironment.shared.callService.authCredentialManager
        let callLinkManager = AppEnvironment.shared.callService.callLinkManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!
        let authCredential = try await authCredentialManager.fetchCallLinkAuthCredential(localIdentifiers: localIdentifiers)
        let callLinkState = try await performUpdate(callLinkManager, authCredential)
        self.callLinkStatePublisher.send(callLinkState)
    }
}
