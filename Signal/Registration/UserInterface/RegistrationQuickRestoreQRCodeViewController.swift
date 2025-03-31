//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationQuickRestoreQRCodePresenter: AnyObject {

    func didReceiveRegistrationMessage(_ message: RegistrationProvisioningMessage)

    // Cancel out to the splash screen
    func cancel()
}

class RegistrationQuickRestoreQRCodeViewController:
    OWSViewController,
    OWSNavigationChildController,
    ProvisioningSocketManagerUIDelegate
{
    private weak var presenter: RegistrationQuickRestoreQRCodePresenter?

    private var provisioningSocketManager: ProvisioningSocketManager
    private var viewModel: QRCodeViewRepresentable.Model

    init(presenter: RegistrationQuickRestoreQRCodePresenter) {
        self.presenter = presenter
        self.provisioningSocketManager = ProvisioningSocketManager(linkType: .quickRestore)
        self.viewModel = QRCodeViewRepresentable.Model(qrCodeURL: nil)
        super.init()

        self.provisioningSocketManager.delegate = self

        self.addChild(hostingController)
        self.view.addSubview(hostingController.view)
        hostingController.view.autoPinEdgesToSuperviewEdges()
        hostingController.didMove(toParent: self)
    }

    private lazy var hostingController = UIHostingController(rootView: ContentStack(
        viewModel: viewModel,
        cancelAction: { [weak self] in
            self?.presenter?.cancel()
        }
    ))

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        provisioningSocketManager.start()

        Task {
            do {
                let message: RegistrationProvisioningMessage = try await provisioningSocketManager.waitForMessage()
                presenter?.didReceiveRegistrationMessage(message)
            } catch {
                // TODO: [Backup]: Prompt the user with the error
                Logger.error("Encountered error waiting for qick restore message")
            }
        }
    }

    // MARK: ProvisioningSocketManagerUIDelegate

    func provisioningSocketManager(
        _ provisioningSocketManager: ProvisioningSocketManager,
        didUpdateProvisioningURL url: URL
    ) {
        self.viewModel.qrCodeURL = url
    }

    func provisioningSocketManagerDidPauseQRRotation(_ provisioningSocketManager: ProvisioningSocketManager) {
        // [TODO: Backups]: Show the 'refresh' UI.
    }

    // MARK: OWSNavigationChildController

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    public var navbarBackgroundColorOverride: UIColor? { .clear }

    public var prefersNavigationBarHidden: Bool { true }
}

// MARK: - SwiftUI

private struct ContentStack: View {
    @ObservedObject var viewModel: QRCodeViewRepresentable.Model

    let cancelAction: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Text(OWSLocalizedString(
                "REGISTRATION_SCAN_QR_CODE_TITLE",
                comment: "Title for screen containing QR code that users scan with their old phone when they want to transfer/restore their message history to a new device."
            ))
                .font(.title)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .multilineTextAlignment(.center)
            Spacer()
            QRCodeViewRepresentable(model: viewModel).frame(width: 300, height: 300)
            Spacer()
            TutorialStack()
            Spacer()
            Spacer()
            Button(CommonStrings.cancelButton, action: self.cancelAction)
                .font(.body.weight(.bold))
                .tint(Color.Signal.ultramarine)
                .padding(.vertical, 14)
            Spacer()
        }
    }
}

private struct TutorialStack: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label(
                OWSLocalizedString(
                "REGISTRATION_SCAN_QR_CODE_TUTORIAL_OPEN_SIGNAL",
                comment: "Tutorial text describing the first step to scanning the restore/transfer QR code with your old phone: opening Signal"
                ),
                image: "device-phone"
            )
            Label(
                OWSLocalizedString(
                "REGISTRATION_SCAN_QR_CODE_TUTORIAL_TAP_CAMERA",
                comment: "Tutorial text describing the second step to scanning the restore/transfer QR code with your old phone: tap the camera icon"
                ),
                image: "camera"
            )
            Label(
                OWSLocalizedString(
                "REGISTRATION_SCAN_QR_CODE_TUTORIAL_SCAN",
                comment: "Tutorial text describing the third step to scanning the restore/transfer QR code with your old phone: scan the code"
                ),
                image: "qr_code"
            )
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }
}
