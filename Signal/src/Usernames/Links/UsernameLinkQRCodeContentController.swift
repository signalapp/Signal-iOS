//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit

/// A content controller supporting toggling between presenting and scanning a
/// username link QR code.
class UsernameLinkQRCodeContentController: OWSViewController, OWSNavigationChildController {
    private enum Mode: Int {
        case present = 0
        case scan
    }

    private lazy var contentSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl()

        control.insertSegment(
            withTitle: OWSLocalizedString(
                "USERNAME_LINK_QR_CODE_VIEW_TITLE_CODE",
                comment: "A title for a view that allows you to view and interact with a QR code for your username link."
            ),
            at: 0,
            animated: false
        )

        control.insertSegment(
            withTitle: OWSLocalizedString(
                "USERNAME_LINK_QR_CODE_VIEW_TITLE_SCAN",
                comment: "A title for a view that allows you to scan a username link QR code using the camera."
            ),
            at: 1,
            animated: false
        )

        control.setWidth(100, forSegmentAt: 0)
        control.setWidth(100, forSegmentAt: 1)
        control.addTarget(self, action: #selector(configureForSelected), for: .valueChanged)

        return control
    }()

    private let presentQRCodeViewController: UsernameLinkPresentQRCodeViewController
    private let scanQRCodeViewController: UsernameLinkScanQRCodeViewController
    private var activeViewController: (UIViewController & OWSNavigationChildController)?

    /// Creates a new controller.
    ///
    /// - Parameter usernameLink
    /// The user's current username link, if available. If `nil` is passed, the
    /// link will be reset when this controller loads.
    init(
        db: DB,
        localUsernameManager: LocalUsernameManager,
        schedulers: Schedulers,
        username: String,
        usernameLink: Usernames.UsernameLink?,
        changeDelegate: UsernameChangeDelegate,
        scanDelegate: UsernameLinkScanDelegate
    ) {
        presentQRCodeViewController = UsernameLinkPresentQRCodeViewController(
            db: db,
            localUsernameManager: localUsernameManager,
            schedulers: schedulers,
            username: username,
            usernameLink: usernameLink,
            usernameChangeDelegate: changeDelegate
        )

        scanQRCodeViewController = UsernameLinkScanQRCodeViewController(
            scanDelegate: scanDelegate
        )

        super.init()
    }

    /// Delegate out nav controller configuration to our children.
    var childForOWSNavigationConfiguration: OWSNavigationChildController? {
        return activeViewController
    }

    /// Lock username link QR code views to portrait.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(presentQRCodeViewController)
        addChild(scanQRCodeViewController)

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(didTapDone),
            accessibilityIdentifier: "done"
        )

        contentSegmentedControl.selectedSegmentIndex = 0
        navigationItem.titleView = contentSegmentedControl

        configureForSelected()
    }

    private func setActive(
        viewController: UIViewController & OWSNavigationChildController
    ) {
        activeViewController = viewController

        view.removeAllSubviews()
        view.addSubview(viewController.view)
        viewController.view.autoPinEdgesToSuperviewEdges()
    }

    // MARK: Events

    @objc
    private func configureForSelected() {
        guard let selectedMode = Mode(rawValue: contentSegmentedControl.selectedSegmentIndex) else {
            owsFail("Unexpected selected segment. How did this happen?")
        }

        switch selectedMode {
        case .present:
            setActive(viewController: presentQRCodeViewController)
        case .scan:
            setActive(viewController: scanQRCodeViewController)
        }
    }

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }
}
