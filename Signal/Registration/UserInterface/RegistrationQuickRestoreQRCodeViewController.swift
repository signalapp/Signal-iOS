//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationMethodPresenter: AnyObject {
    func cancelChosenRestoreMethod()
}

protocol RegistrationQuickRestoreQRCodePresenter: RegistrationMethodPresenter {
    func didReceiveRegistrationMessage(_ message: RegistrationProvisioningMessage)
}

class RegistrationQuickRestoreQRCodeViewController:
    OWSViewController,
    OWSNavigationChildController,
    ProvisioningSocketManagerUIDelegate
{
    private weak var presenter: RegistrationQuickRestoreQRCodePresenter?

    private var provisioningSocketManager: ProvisioningSocketManager
    private var model: RotatingQRCodeView.Model

    init(presenter: RegistrationQuickRestoreQRCodePresenter) {
        self.presenter = presenter
        self.provisioningSocketManager = ProvisioningSocketManager(linkType: .quickRestore)
        self.model = RotatingQRCodeView.Model(
            urlDisplayMode: .loading,
            onRefreshButtonPressed: { [weak provisioningSocketManager] in
                provisioningSocketManager?.reset()
            }
        )
        super.init()

        self.provisioningSocketManager.delegate = self

        self.addChild(hostingController)
        self.view.addSubview(hostingController.view)
        hostingController.view.autoPinEdgesToSuperviewEdges()
        hostingController.didMove(toParent: self)
    }

    private lazy var hostingController = UIHostingController(rootView: ContentStack(
        model: model,
        cancelAction: { [weak self] in
            self?.provisioningSocketManager.stop()
            self?.presenter?.cancelChosenRestoreMethod()
        }
    ))

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        provisioningSocketManager.reset()

        Task {
            do {
                let message: RegistrationProvisioningMessage = try await provisioningSocketManager.waitForMessage()
                presenter?.didReceiveRegistrationMessage(message)
            } catch {
                // TODO: [Backups]: Prompt the user with the error
                Logger.error("Encountered error waiting for qick restore message")
            }
        }
    }

    // MARK: ProvisioningSocketManagerUIDelegate

    func provisioningSocketManager(
        _ provisioningSocketManager: ProvisioningSocketManager,
        didUpdateProvisioningURL url: URL
    ) {
        self.model.updateURLDisplayMode(.loaded(url))
    }

    func provisioningSocketManagerDidPauseQRRotation(_ provisioningSocketManager: ProvisioningSocketManager) {
        self.model.updateURLDisplayMode(.refreshButton)
    }

    // MARK: OWSNavigationChildController

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    public var navbarBackgroundColorOverride: UIColor? { .clear }

    public var prefersNavigationBarHidden: Bool { true }
}

// MARK: - SwiftUI

private struct ContentStack: View {
    @ObservedObject var model: RotatingQRCodeView.Model

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

            RotatingQRCodeView(model: model)
                .padding(.horizontal, 50)

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

#if DEBUG
@available(iOS 17, *)
#Preview {
    @Previewable @State var displayMode: RotatingQRCodeView.Model.URLDisplayMode = .loading

    let url1 = URL(string: "https://support.signal.org/hc/articles/6712070553754-Phone-Number-Privacy-and-Usernames")!
    let url2 = URL(string: "https://support.signal.org/hc/articles/6255134251546-Edit-Message")!
    let cycle: () async -> Void = { @MainActor in
        displayMode = .loading
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC/2)
        displayMode = .loaded(url1)
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 3)
        displayMode = .loaded(url2)
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 3)
        displayMode = .refreshButton
    }

    ContentStack(
        model: .init(
            urlDisplayMode: displayMode,
            onRefreshButtonPressed: { Task { await cycle() } }
        ),
        cancelAction: {}
    )
    .task {
        await cycle()
    }
}
#endif
