//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit
import SignalUI
import SwiftUI

class ProvisioningTransferQRCodeViewController: ProvisioningBaseViewController {
    private let provisioningTransferQRCodeViewModel: ProvisioningTransferQRCodeView.Model

    override init(provisioningController: ProvisioningController) {
        provisioningTransferQRCodeViewModel = ProvisioningTransferQRCodeView.Model(url: nil)

        super.init(provisioningController: provisioningController)

        navigationItem.hidesBackButton = true
   }

    override func viewDidLoad() {
        super.viewDidLoad()

        let qrCodeHostingViewContainer = HostingContainer(wrappedView: ProvisioningTransferQRCodeView(
            model: provisioningTransferQRCodeViewModel,
            onGetHelpTapped: { [weak self] in self?.didTapHelp() },
            onCancelTapped: { [weak self] in self?.didTapCancel() }
        ))
        addChild(qrCodeHostingViewContainer)
        view.addSubview(qrCodeHostingViewContainer.view)
        qrCodeHostingViewContainer.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            qrCodeHostingViewContainer.view.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            qrCodeHostingViewContainer.view.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            qrCodeHostingViewContainer.view.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            qrCodeHostingViewContainer.view.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])
        qrCodeHostingViewContainer.didMove(toParent: self)
    }

    // MARK: -

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        AppEnvironment.shared.deviceTransferServiceRef.addObserver(self)

        Task { @MainActor in
            do {
                let url = try AppEnvironment.shared.deviceTransferServiceRef.startAcceptingTransfersFromOldDevices(
                    mode: .linked // TODO: .primary
                )

                provisioningTransferQRCodeViewModel.qrCodeViewModel.qrCodeURL = url
            } catch {
                owsFailDebug("error \(error)")
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        AppEnvironment.shared.deviceTransferServiceRef.removeObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.stopAcceptingTransfersFromOldDevices()
    }

    // MARK: - Events

    weak var permissionActionSheetController: ActionSheetController?

    private func didTapHelp() {
        let turnOnView = TurnOnPermissionView(
            title: OWSLocalizedString(
                "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_TITLE",
                comment: "Title for local network permission action sheet"
            ),
            message: OWSLocalizedString(
                "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_BODY",
                comment: "Body for local network permission action sheet"
            ),
            steps: [
                .init(
                    icon: #imageLiteral(resourceName: "settings-app-icon-32"),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_ONE",
                        comment: "First step for local network permission action sheet"
                    )
                ),
                .init(
                    icon: UIImage(resource: UIApplication.shared.currentAppIcon.previewImageResource),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_TWO",
                        comment: "Second step for local network permission action sheet"
                    )
                ),
                .init(
                    icon: UIImage(imageLiteralResourceName: "toggle-32"),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_THREE",
                        comment: "Third step for local network permission action sheet"
                    )
                )
            ],
            button: UIButton(
                configuration: .largePrimary(title: OWSLocalizedString(
                    "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_NEED_HELP",
                    comment: "A button asking the user if they need further help getting their transfer working."
                )),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapContactSupport()
                }
            )
        )

        let actionSheetController = ActionSheetController()
        permissionActionSheetController = actionSheetController
        actionSheetController.customHeader = turnOnView
        actionSheetController.isCancelable = true
        presentActionSheet(actionSheetController)
    }

    private func didTapCancel() {
        guard let navigationController = navigationController else {
            owsFailDebug("Unexpectedly missing nav controller!")
            return
        }

        provisioningController.pushTransferChoiceView(onto: navigationController)
    }

    @objc
    private func didTapContactSupport() {
        Logger.info("")

        permissionActionSheetController?.dismiss(animated: true)
        permissionActionSheetController = nil

        ContactSupportActionSheet.present(
            emailFilter: .deviceTransfer,
            logDumper: .fromGlobals(),
            fromViewController: self
        )
    }
}

extension ProvisioningTransferQRCodeViewController: DeviceTransferServiceObserver {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {}

    func deviceTransferServiceDidStartTransfer(progress: Progress) {
        provisioningController.accountTransferInProgress(fromViewController: self, progress: progress)
    }

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        if let error = error {
            owsFailDebug("unexpected error while rendering QR code \(error)")
        }
    }

    func deviceTransferServiceDidRequestAppRelaunch() {
        owsFail("Relaunch not supported for provisioning; only on the receiving device during transfer")
    }
}

// MARK: -

private struct ProvisioningTransferQRCodeView: View {
    class Model: ObservableObject {
        let qrCodeViewModel: QRCodeViewRepresentable.Model

        init(url: URL?) {
            qrCodeViewModel = QRCodeViewRepresentable.Model(qrCodeURL: url)
        }
    }

    @ObservedObject
    private var model: Model

    private let onGetHelpTapped: () -> Void
    private let onCancelTapped: () -> Void

    init(
        model: Model,
        onGetHelpTapped: @escaping () -> Void,
        onCancelTapped: @escaping () -> Void
    ) {
        self.model = model
        self.onGetHelpTapped = onGetHelpTapped
        self.onCancelTapped = onCancelTapped
    }

    var body: some View {
        GeometryReader { overallGeometry in
            VStack(spacing: 12) {
                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_QRCODE_TITLE",
                    comment: "The title for the device transfer qr code view"
                ))
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.Signal.label)

                Text(OWSLocalizedString(
                    "DEVICE_TRANSFER_QRCODE_EXPLANATION",
                    comment: "The explanation for the device transfer qr code view"
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)

                Spacer()
                    .frame(height: overallGeometry.size.height * 0.05)

                GeometryReader { qrCodeGeometry in
                    ZStack {
                        Color(UIColor.ows_gray02)
                            .cornerRadius(24)

                        QRCodeViewRepresentable(
                            model: model.qrCodeViewModel,
                            qrCodeStylingMode: .brandedWithoutLogo
                        )
                        .padding(qrCodeGeometry.size.height * 0.1)
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                Spacer()
                    .frame(height: overallGeometry.size.height * (overallGeometry.size.isLandscape ? 0.05 : 0.1))

                Button(OWSLocalizedString(
                    "DEVICE_TRANSFER_QRCODE_NOT_SEEING",
                    comment: "A prompt to provide further explanation if the user is not seeing the transfer on both devices."
                )) {
                    onGetHelpTapped()
                }
                .buttonStyle(Registration.UI.MediumSecondaryButtonStyle())

                Button(CommonStrings.cancelButton) {
                    onCancelTapped()
                }
                .buttonStyle(Registration.UI.MediumSecondaryButtonStyle())
                .padding(.bottom, NSDirectionalEdgeInsets.buttonContainerLayoutMargins.bottom)
            }
            .multilineTextAlignment(.center)
        }
    }
}

// MARK: -

private struct PreviewView: View {
    let url: URL?

    var body: some View {
        ProvisioningTransferQRCodeView(
            model: ProvisioningTransferQRCodeView.Model(url: url),
            onGetHelpTapped: {},
            onCancelTapped: {}
        )
        .padding(112)
    }
}

#Preview("Loaded") {
    PreviewView(url: URL(string: "https://signal.org")!)
}

#Preview("Loading") {
    PreviewView(url: nil)
}
