//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

class CreateCallLinkViewController: InteractiveSheetViewController {
    private lazy var _navigationController = OWSNavigationController()
    private let _callLinkViewController: CallLinkViewController

    override var interactiveScrollViews: [UIScrollView] { [self._callLinkViewController.tableView] }

    override var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

    // MARK: -

    init(callLink: CallLink, adminPasskey: Data, callLinkState: CallLinkState) {
        self._callLinkViewController = CallLinkViewController.forJustCreated(
            callLink: callLink,
            adminPasskey: adminPasskey,
            callLinkState: callLinkState
        )
        super.init()
        self.allowsExpansion = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self._navigationController.viewControllers = [ self._callLinkViewController ]
        self.addChild(self._navigationController)
        self._navigationController.didMove(toParent: self)
        self.contentView.addSubview(self._navigationController.view)
        self._navigationController.view.autoPinEdgesToSuperviewEdges()

        self._callLinkViewController.navigationItem.rightBarButtonItem = .doneButton(
            action: { [unowned self] in
                self._callLinkViewController.persistIfNeeded()
                self.dismiss(animated: true)
            }
        )
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        self.view.layoutIfNeeded()
        // InteractiveSheetViewController doesn't work with adjustedContentInset.
        self._callLinkViewController.tableView.contentInsetAdjustmentBehavior = .never
        self._callLinkViewController.tableView.contentInset = UIEdgeInsets(
            top: self._navigationController.navigationBar.bounds.size.height,
            left: 0,
            bottom: self.view.safeAreaInsets.bottom,
            right: 0
        )

        self.minimizedHeight = (
            self._callLinkViewController.tableView.contentSize.height
            + self._callLinkViewController.tableView.contentInset.totalHeight
            + InteractiveSheetViewController.Constants.handleHeight
        )
    }

    // MARK: - Create & Present

    static func createCallLinkOnServerAndPresent(from viewController: UIViewController) {
        ModalActivityIndicatorViewController.present(
            fromViewController: viewController,
            presentationDelay: 0.25,
            asyncBlock: { modal in
                do {
                    let callLink = CallLink.generate()
                    let callService = AppEnvironment.shared.callService!
                    let createResult = try await callService.callLinkManager.createCallLink(rootKey: callLink.rootKey)
                    modal.dismissIfNotCanceled {
                        viewController.present(CreateCallLinkViewController(
                            callLink: callLink,
                            adminPasskey: createResult.adminPasskey,
                            callLinkState: createResult.callLinkState
                        ), animated: true)
                    }
                } catch {
                    Logger.warn("Call link creation failed: \(error)")
                    modal.dismissIfNotCanceled {
                        OWSActionSheets.showActionSheet(
                            title: CallStrings.callLinkErrorSheetTitle,
                            message: OWSLocalizedString(
                                "CALL_LINK_CREATION_FAILURE_SHEET_DESCRIPTION",
                                comment: "Description of sheet presented when call link creation fails."
                            )
                        )
                    }
                }
            }
        )
    }
}
