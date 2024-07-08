//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

// [CallLink] TODO: Switch this to InterativeSheetViewController.
class CreateCallLinkViewController: OWSTableViewController2 {
    private let callLink: CallLink = .generate()

    // MARK: -

    override func viewDidLoad() {
        self.setContents(buildTableContents(), shouldReload: false)
        super.viewDidLoad()
    }

    private func buildTableContents() -> OWSTableContents {
        let linkItem = OWSTableItem.item(name: callLink.url().absoluteString)

        // [CallLink] TODO: Build the rest of this interface.

        return OWSTableContents(
            title: "Create Call Link",
            sections: [
                OWSTableSection(items: [linkItem]),
            ]
        )
    }

    // MARK: - Create & Present

    func createCallLinkOnServerAndPresent(fromViewController: UIViewController) {
        ModalActivityIndicatorViewController.present(fromViewController: fromViewController, asyncBlock: { modalViewController in
            do {
                let callService = AppEnvironment.shared.callService!
                _ = try await callService.callLinkManager.createCallLink(rootKey: self.callLink.rootKey)
                modalViewController.dismissIfNotCanceled {
                    self.presentAfterCreatingCallLinkOnServer(fromViewController: fromViewController)
                }
            } catch {
                modalViewController.dismissIfNotCanceled {
                    // [CallLink] TODO: Present these errors to the user.
                    Logger.warn("\(error)")
                }
            }
        })
    }

    private func presentAfterCreatingCallLinkOnServer(fromViewController: UIViewController) {
        let navigationController = OWSNavigationController(rootViewController: self)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheetPresentationController = navigationController.sheetPresentationController {
            sheetPresentationController.detents = [.medium()]
            sheetPresentationController.preferredCornerRadius = 16
            sheetPresentationController.prefersGrabberVisible = true
        }
        fromViewController.present(navigationController, animated: true)
    }
}
