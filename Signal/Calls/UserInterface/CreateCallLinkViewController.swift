//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import SignalUI

class CreateCallLinkViewController: InteractiveSheetViewController {
    private let _navigationController = OWSNavigationController()
    private let _callLinkViewController: CallLinkViewController

    override var interactiveScrollViews: [UIScrollView] { [_callLinkViewController.tableView] }

    override var sheetBackgroundColor: UIColor { OWSTableViewController2.tableBackgroundColor }

    // MARK: -

    init(callLink: CallLink, adminPasskey: Data, callLinkState: SignalServiceKit.CallLinkState) {
        _callLinkViewController = CallLinkViewController.forJustCreated(
            callLink: callLink,
            adminPasskey: adminPasskey,
            callLinkState: callLinkState,
        )
        super.init()
        allowsExpansion = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        _navigationController.viewControllers = [_callLinkViewController]
        addChild(_navigationController)
        _navigationController.didMove(toParent: self)
        contentView.addSubview(_navigationController.view)
        _navigationController.view.autoPinEdgesToSuperviewEdges()

        _callLinkViewController.navigationItem.rightBarButtonItem = .doneButton(
            action: { [unowned self] in
                self._callLinkViewController.persistIfNeeded()
                self.dismiss(animated: true)
            },
        )
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        // Setting up appearance must be done just before view becomes visible,
        // otherwise UINavigationBar doesn't resolve the background color correctly.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = sheetBackgroundColor
        _navigationController.navigationBar.standardAppearance = appearance
        _navigationController.navigationBar.compactAppearance = appearance
        _navigationController.navigationBar.scrollEdgeAppearance = appearance

        view.layoutIfNeeded()
        // InteractiveSheetViewController doesn't work with adjustedContentInset.
        _callLinkViewController.tableView.contentInsetAdjustmentBehavior = .never
        _callLinkViewController.tableView.contentInset = UIEdgeInsets(
            top: self._navigationController.navigationBar.bounds.size.height,
            left: 0,
            bottom: self.view.safeAreaInsets.bottom,
            right: 0,
        )

        minimizedHeight = (
            _callLinkViewController.tableView.contentSize.height
                + _callLinkViewController.tableView.contentInset.totalHeight
                + InteractiveSheetViewController.Constants.handleHeight,
        )
    }

    // MARK: - Create & Present

    static func createCallLinkOnServerAndPresent(from viewController: UIViewController) {
        ModalActivityIndicatorViewController.present(
            fromViewController: viewController,
            title: OWSLocalizedString(
                "CALL_LINK_CREATING_MODAL",
                comment: "Displayed in a full screen modal view when creating a Call Link",
            ),
            canCancel: true,
            presentationDelay: 0.25,
            asyncBlock: { modal in
                do {
                    let rootKey = CallLinkRootKey.generate()
                    let callService = AppEnvironment.shared.callService!
                    let createResult = try await callService.callLinkManager.createCallLink(rootKey: rootKey)
                    let callLink = CallLink(rootKey: createResult.callLinkState.rootKey)
                    modal.dismissIfNotCanceled {
                        viewController.present(CreateCallLinkViewController(
                            callLink: callLink,
                            adminPasskey: createResult.adminPasskey,
                            callLinkState: createResult.callLinkState,
                        ), animated: true)
                    }
                } catch {
                    Logger.warn("Call link creation failed: \(error)")
                    modal.dismissIfNotCanceled {
                        OWSActionSheets.showActionSheet(
                            title: CallStrings.callLinkErrorSheetTitle,
                            message: OWSLocalizedString(
                                "CALL_LINK_CREATION_FAILURE_SHEET_DESCRIPTION",
                                comment: "Description of sheet presented when call link creation fails.",
                            ),
                        )
                    }
                }
            },
        )
    }
}
