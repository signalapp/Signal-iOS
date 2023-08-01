//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalMessaging
import SignalServiceKit
import SignalUI

protocol LinkDeviceViewControllerDelegate: AnyObject {
    func expectMoreDevices()
}

class LinkDeviceViewController: OWSViewController {

    weak var delegate: LinkDeviceViewControllerDelegate?

    private lazy var scanningInstructionsLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString(
            "LINK_DEVICE_SCANNING_INSTRUCTIONS",
            comment: "QR Scanning screen instructions, placed alongside a camera view for scanning QR Codes"
        )
        label.textColor = Theme.secondaryTextAndIconColor
        label.font = .dynamicTypeBody2
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        return label
    }()

    private lazy var qrCodeScanViewController = QRCodeScanViewController(appearance: .masked())

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("LINK_NEW_DEVICE_TITLE", comment: "Navigation title when scanning QR code to add new device.")

#if TESTABLE_BUILD
        navigationItem.rightBarButtonItem = .init(
            title: LocalizationNotNeeded("ENTER"),
            style: .plain,
            target: self,
            action: #selector(manuallyEnterLinkURL)
        )
#endif

        view.backgroundColor = Theme.backgroundColor

        qrCodeScanViewController.delegate = self

        view.addSubview(qrCodeScanViewController.view)
        qrCodeScanViewController.view.autoPinWidthToSuperview()
        qrCodeScanViewController.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        qrCodeScanViewController.view.autoPinToSquareAspectRatio()
        addChild(qrCodeScanViewController)

        let bottomView = UIView()
        bottomView.preservesSuperviewLayoutMargins = true
        view.addSubview(bottomView)
        bottomView.autoPinEdge(.top, to: .bottom, of: qrCodeScanViewController.view)
        bottomView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)

        let heroImage = UIImage(imageLiteralResourceName: "ic_devices_ios")
        let imageView = UIImageView(image: heroImage)
        imageView.autoSetDimensions(to: heroImage.size)

        let bottomStack = UIStackView(arrangedSubviews: [ imageView, scanningInstructionsLabel ])
        bottomStack.axis = .vertical
        bottomStack.alignment = .center
        bottomStack.spacing = 8
        bottomView.addSubview(bottomStack)
        bottomStack.autoPinWidthToSuperviewMargins()
        bottomStack.autoPinHeightToSuperviewMargins(relation: .lessThanOrEqual)
        bottomStack.autoVCenterInSuperview()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !UIDevice.current.isIPad {
            UIDevice.current.ows_setOrientation(.portrait)
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.isIPad ? .all : .portrait
    }

    override func themeDidChange() {
        super.themeDidChange()

        view.backgroundColor = Theme.backgroundColor
        scanningInstructionsLabel.textColor = Theme.secondaryTextAndIconColor
    }

    // MARK: -

    func confirmProvisioningWithUrl(_ deviceProvisioningUrl: DeviceProvisioningURL) {
        let title = NSLocalizedString(
            "LINK_DEVICE_PERMISSION_ALERT_TITLE",
            comment: "confirm the users intent to link a new device"
        )
        let linkingDescription = NSLocalizedString(
            "LINK_DEVICE_PERMISSION_ALERT_BODY",
            comment: "confirm the users intent to link a new device"
        )

        let actionSheet = ActionSheetController(title: title, message: linkingDescription)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: { _ in
                DispatchQueue.main.async {
                    self.popToLinkedDeviceList()
                }
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString("CONFIRM_LINK_NEW_DEVICE_ACTION", comment: "Button text"),
            style: .default,
            handler: { _ in
                self.provisionWithUrl(deviceProvisioningUrl)
            }
        ))
        presentActionSheet(actionSheet)
    }

    private func provisionWithUrl(_ deviceProvisioningUrl: DeviceProvisioningURL) {
        databaseStorage.write { transaction in
            // Optimistically set this flag.
            DependenciesBridge.shared.deviceManager.setMayHaveLinkedDevices(
                true,
                transaction: transaction.asV2Write
            )
        }

        let aciIdentityKeyPair = identityManager.identityKeyPair(for: .aci)
        let pniIdentityKeyPair = identityManager.identityKeyPair(for: .pni)
        let accountAddress = tsAccountManager.localAddress
        let pni = tsAccountManager.localPni
        let myProfileKeyData = profileManager.localProfileKey().keyData
        let areReadReceiptsEnabled = receiptManager.areReadReceiptsEnabled()

        guard let myAci = accountAddress?.uuid, let myPhoneNumber = accountAddress?.phoneNumber else {
            owsFail("Can't provision without an aci & phone number.")
        }
        guard let aciIdentityKeyPair else {
            owsFail("Can't provision without an aci identity.")
        }

        let deviceProvisioner = OWSDeviceProvisioner(
            myAciIdentityKeyPair: aciIdentityKeyPair.identityKeyPair,
            myPniIdentityKeyPair: pniIdentityKeyPair?.identityKeyPair,
            theirPublicKey: deviceProvisioningUrl.publicKey,
            theirEphemeralDeviceId: deviceProvisioningUrl.ephemeralDeviceId,
            myAci: myAci,
            myPhoneNumber: myPhoneNumber,
            myPni: pni,
            profileKey: myProfileKeyData,
            readReceiptsEnabled: areReadReceiptsEnabled,
            provisioningService: DeviceProvisioningServiceImpl(
                networkManager: networkManager,
                schedulers: DependenciesBridge.shared.schedulers
            ),
            schedulers: DependenciesBridge.shared.schedulers
        )

        deviceProvisioner.provision().map(on: DispatchQueue.main) {
            Logger.info("Successfully provisioned device.")

            self.delegate?.expectMoreDevices()
            self.popToLinkedDeviceList()

            // The service implementation of the socket connection caches the linked
            // device state, so all sync message sends will fail on the socket until it
            // is cycled.
            self.socketManager.cycleSocket()

            // Fetch the local profile to determine if all linked devices support UD.
            self.profileManager.fetchLocalUsersProfile(authedAccount: .implicit())

        }.catch(on: DispatchQueue.main) { error in
            Logger.error("Failed to provision device with error: \(error)")
            self.presentActionSheet(self.retryActionSheetController(error: error, retryBlock: { [weak self] in
                self?.provisionWithUrl(deviceProvisioningUrl)
            }))
        }
    }

    private func retryActionSheetController(error: Error, retryBlock: @escaping () -> Void) -> ActionSheetController {
        switch error {
        case let error as DeviceLimitExceededError:
            let actionSheet = ActionSheetController(
                title: error.errorDescription,
                message: error.recoverySuggestion
            )
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.okButton,
                handler: { [weak self] _ in
                    self?.popToLinkedDeviceList()
                }
            ))
            return actionSheet

        default:
            let actionSheet = ActionSheetController(
                title: OWSLocalizedString("LINKING_DEVICE_FAILED_TITLE", comment: "Alert Title"),
                message: error.userErrorDescription
            )
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.retryButton,
                style: .default,
                handler: { action in retryBlock() }
            ))
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
                handler: { [weak self] action in
                    DispatchQueue.main.async { self?.dismiss(animated: true) }
                }
            ))
            return actionSheet
        }
    }

    private func popToLinkedDeviceList() {
        navigationController?.popViewController(animated: true, completion: {
            UIViewController.attemptRotationToDeviceOrientation()
        })
    }

    #if TESTABLE_BUILD
    @objc
    private func manuallyEnterLinkURL() {
        let alertController = UIAlertController(
            title: LocalizationNotNeeded("Manually enter linking code."),
            message: LocalizationNotNeeded("Copy the URL represented by the QR code into the field below."),
            preferredStyle: .alert
        )
        alertController.addTextField()
        alertController.addAction(UIAlertAction(
            title: CommonStrings.okayButton,
            style: .default,
            handler: { _ in
                guard let qrCodeString = alertController.textFields?.first?.text else { return }
                self.qrCodeScanViewScanned(
                    self.qrCodeScanViewController,
                    qrCodeData: nil,
                    qrCodeString: qrCodeString
                )
            }
        ))
        alertController.addAction(UIAlertAction(
            title: CommonStrings.cancelButton,
            style: .cancel
        ))
        present(alertController, animated: true)
    }
    #endif
}

extension LinkDeviceViewController: QRCodeScanDelegate {

    @discardableResult
    func qrCodeScanViewScanned(
        _ qrCodeScanViewController: QRCodeScanViewController,
        qrCodeData: Data?,
        qrCodeString: String?
    ) -> QRCodeScanOutcome {
        AssertIsOnMainThread()

        guard let qrCodeString else {
            // Only accept QR codes with a valid string payload.
            return .continueScanning
        }

        guard let url = DeviceProvisioningURL(urlString: qrCodeString) else {
            Logger.error("Unable to parse provisioning params from QRCode: \(qrCodeString)")

            let title = NSLocalizedString("LINK_DEVICE_INVALID_CODE_TITLE", comment: "report an invalid linking code")
            let body = NSLocalizedString("LINK_DEVICE_INVALID_CODE_BODY", comment: "report an invalid linking code")

            let actionSheet = ActionSheetController(title: title, message: body)
            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
                handler: { _ in
                    DispatchQueue.main.async {
                        self.popToLinkedDeviceList()
                    }
                }
            ))
            actionSheet.addAction(ActionSheetAction(
                title: NSLocalizedString("LINK_DEVICE_RESTART", comment: "attempt another linking"),
                style: .default,
                handler: { _ in
                    self.qrCodeScanViewController.tryToStartScanning()
                }
            ))
            presentActionSheet(actionSheet)

            return .stopScanning
        }

        confirmProvisioningWithUrl(url)

        return .stopScanning
    }

    func qrCodeScanViewDismiss(_ qrCodeScanViewController: SignalUI.QRCodeScanViewController) {
        AssertIsOnMainThread()
        popToLinkedDeviceList()
    }
}
