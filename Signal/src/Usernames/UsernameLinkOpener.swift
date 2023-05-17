//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

struct UsernameLinkOpener {
    private let link: Usernames.UsernameLink

    init(link: Usernames.UsernameLink) {
        self.link = link
    }

    func open(fromViewController: UIViewController) {
        struct Deps: Dependencies {}
        let deps = Deps()

        UsernameQuerier(
            contactsManager: deps.contactsManager,
            databaseStorage: deps.databaseStorage,
            networkManager: deps.networkManager,
            profileManager: deps.profileManager,
            recipientFetcher: DependenciesBridge.shared.recipientFetcher,
            schedulers: DependenciesBridge.shared.schedulers,
            storageServiceManager: deps.storageServiceManager,
            tsAccountManager: deps.tsAccountManager,
            usernameLookupManager: DependenciesBridge.shared.usernameLookupManager
        ).queryForUsername(
            username: link.username,
            fromViewController: fromViewController,
            onSuccess: { aci in
                AssertIsOnMainThread()

                SignalApp.shared.presentConversationForAddress(
                    SignalServiceAddress(aci),
                    animated: true
                )
            }
        )
    }
}
