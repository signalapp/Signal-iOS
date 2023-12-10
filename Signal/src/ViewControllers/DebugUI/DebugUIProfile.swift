//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalMessaging
import SignalUI

#if USE_DEBUG_UI

class DebugUIProfile: DebugUIPage, Dependencies {

    let name = "Profile"

    func section(thread aThread: TSThread?) -> OWSTableSection? {
        let sectionItems = [
            OWSTableItem(title: "Clear Profile Whitelist") {
                Self.profileManagerImpl.clearProfileWhitelist()
            },
            { () -> OWSTableItem? in
                guard let thread = aThread else {
                    owsFailDebug("thread was unexpectedly nil")
                    return nil
                }
                let name = Self.contactsManager.displayNameWithSneakyTransaction(thread: thread)
                return OWSTableItem(title: "Remove “\(name)” from Profile Whitelist") {
                    Self.profileManagerImpl.removeThread(fromProfileWhitelist: thread)
                }
            }(),
            OWSTableItem(title: "Log Profile Whitelist") {
                Self.profileManagerImpl.logProfileWhitelist()
            },
            OWSTableItem(title: "Log User Profiles") {
                Self.profileManagerImpl.logUserProfiles()
            },
            OWSTableItem(title: "Log Profile Key") {
                let localProfileKey = Self.profileManagerImpl.localProfileKey()
                Logger.info("localProfileKey: \(localProfileKey.keyData.hexadecimalString)")
                Self.profileManagerImpl.logUserProfiles()
            },
            OWSTableItem(title: "Regenerate Profile/ProfileKey") {
                Self.profileManagerImpl.debug_regenerateLocalProfileWithSneakyTransaction()
            },
            OWSTableItem(title: "Send Profile Key Message") { [weak self] in
                guard let self else { return }
                guard let aThread = aThread else {
                    owsFailDebug("Missing thread.")
                    return
                }

                let message = Self.databaseStorage.read { OWSProfileKeyMessage(thread: aThread, transaction: $0) }
                Task {
                    do {
                        try await self.messageSender.sendMessage(message.asPreparer)
                        Logger.info("Successfully sent profile key message to thread: \(String(describing: aThread))")
                    } catch {
                        owsFailDebug("Failed to send profile key message to thread: \(String(describing: aThread))")
                    }
                }
            },
            OWSTableItem(title: "Re-upload Profile") {
                Self.profileManagerImpl.reuploadLocalProfile(authedAccount: .implicit())
            },
            OWSTableItem(title: "Log Local Profile") {
                Self.profileManagerImpl.logLocalProfile()
            },
            OWSTableItem(title: "Fetch Local Profile") {
                ProfileFetcherJob.fetchProfile(
                    address: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.aciAddress,
                    ignoreThrottling: true
                )
            }
        ].compactMap { $0 }

        return OWSTableSection(title: "Profile", items: sectionItems)
    }
}

#endif
