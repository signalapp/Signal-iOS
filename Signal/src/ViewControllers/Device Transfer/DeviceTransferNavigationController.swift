//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

class DeviceTransferNavigationController: UINavigationController {

    required init() {
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pushViewController(DeviceTransferInitialViewController(), animated: false)
        setNavigationBarHidden(true, animated: false)

        let dismissButton = UIButton()
        dismissButton.setTemplateImageName("x-24", tintColor: Theme.primaryIconColor)
        dismissButton.addTarget(self, action: #selector(tappedDismiss), for: .touchUpInside)

        view.addSubview(dismissButton)

        dismissButton.autoSetDimensions(to: CGSize(square: 40))
        dismissButton.autoPinEdge(toSuperviewEdge: .leading, withInset: 8)
        dismissButton.autoPinEdge(toSuperviewEdge: .top, withInset: 10)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func tappedDismiss() {
        AssertIsOnMainThread()

        if let topVC = topViewController as? DeviceTransferBaseViewController, topVC.requiresDismissConfirmation {
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_TITLE",
                                         comment: "The title of the dialog asking the user if they want to cancel a device transfer"),
                message: OWSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_MESSAGE",
                                           comment: "The message of the dialog asking the user if they want to cancel a device transfer")
            )
            actionSheet.addAction(OWSActionSheets.cancelAction)

            let okAction = ActionSheetAction(
                title: OWSLocalizedString("DEVICE_TRANSFER_CANCEL_CONFIRMATION_ACTION",
                                         comment: "The stop action of the dialog asking the user if they want to cancel a device transfer"),
                style: .destructive
            ) { _ in
                self.dismissActionSheet()
            }
            actionSheet.addAction(okAction)

            present(actionSheet, animated: true)
        } else {
            dismissActionSheet()
        }
    }

    func dismissActionSheet() {
        AssertIsOnMainThread()

        deviceTransferService.cancelTransferToNewDevice()

        actionSheetController?.dismiss(animated: true, completion: nil)
    }

    var actionSheetController: ActionSheetController?
    func present(fromViewController: UIViewController) {
        let actionSheetController = ActionSheetController()
        self.actionSheetController = actionSheetController
        actionSheetController.customHeader = view
        view.autoSetDimension(.height, toSize: 440)
        fromViewController.presentActionSheet(actionSheetController)
    }
}

class DeviceTransferBaseViewController: UIViewController {
    var transferNavigationController: DeviceTransferNavigationController? {
        return navigationController as? DeviceTransferNavigationController
    }

    var requiresDismissConfirmation: Bool { false }

    let contentView = UIStackView()

    override func loadView() {
        view = UIView()
        view.backgroundColor = Theme.actionSheetBackgroundColor

        view.addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges()

        contentView.isLayoutMarginsRelativeArrangement = true
        contentView.layoutMargins = UIEdgeInsets(top: 16, leading: 32, bottom: 16, trailing: 32)
        contentView.axis = .vertical
    }

    func titleLabel(text: String) -> UILabel {
        let titleLabel = UILabel()
        titleLabel.text = text
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        return titleLabel
    }

    func explanationLabel(explanationText: String) -> UILabel {
        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = .dynamicTypeBody2
        explanationLabel.text = explanationText
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        return explanationLabel
    }

    func button(title: String, selector: Selector) -> OWSFlatButton {
        let font = UIFont.dynamicTypeBodyClamped.semibold()
        let buttonHeight = OWSFlatButton.heightForFont(font)
        let button = OWSFlatButton.button(title: title,
                                          font: font,
                                          titleColor: .white,
                                          backgroundColor: .ows_accentBlue,
                                          target: self,
                                          selector: selector)
        button.autoSetDimension(.height, toSize: buttonHeight)
        return button
    }
}
