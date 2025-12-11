//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI
import SignalUI
import SignalServiceKit

class BaseQuickRestoreQRCodeViewController:
    OWSViewController,
    OWSNavigationChildController,
    ProvisioningSocketManagerUIDelegate
{
    private var provisioningSocketManager: ProvisioningSocketManager
    private var model: RotatingQRCodeView.Model

    override init() {
        self.provisioningSocketManager = ProvisioningSocketManager(linkType: .quickRestore)
        self.model = RotatingQRCodeView.Model(
            urlDisplayMode: .loading,
            onRefreshButtonPressed: { [weak provisioningSocketManager] in
                provisioningSocketManager?.reset()
            }
        )
        super.init()

        self.provisioningSocketManager.delegate = self
        self.navigationItem.hidesBackButton = true
    }

    private lazy var hostingController = UIHostingController(rootView: ContentStack(
        model: model,
        cancelAction: { [weak self] in
            self?.cancel()
        }
    ))

    func cancel() {
        provisioningSocketManager.stop()
    }

    func reset() {
        provisioningSocketManager.reset()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        provisioningSocketManager.reset()
    }

    func waitForMessage() async throws -> RegistrationProvisioningMessage {
        return try await provisioningSocketManager.waitForMessage()
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
}

// MARK: - SwiftUI

private struct ContentStack: View {
    @ObservedObject var model: RotatingQRCodeView.Model

    let cancelAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                Text(OWSLocalizedString(
                    "REGISTRATION_SCAN_QR_CODE_TITLE",
                    comment: "Title for screen containing QR code that users scan with their old phone when they want to transfer/restore their message history to a new device."
                ))
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                RotatingQRCodeView(model: model)
                    .padding(.horizontal, 40)

                TutorialStack()

                Button(CommonStrings.cancelButton) {
                    self.cancelAction()
                }
                .buttonStyle(Registration.UI.MediumSecondaryButtonStyle())
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .padding(.bottom, NSDirectionalEdgeInsets.buttonContainerLayoutMargins.bottom)
            }
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
            .fixedSize(horizontal: false, vertical: true)
            Label(
                OWSLocalizedString(
                "REGISTRATION_SCAN_QR_CODE_TUTORIAL_TAP_CAMERA",
                comment: "Tutorial text describing the second step to scanning the restore/transfer QR code with your old phone: tap the camera icon"
                ),
                image: "camera"
            )
            .fixedSize(horizontal: false, vertical: true)
            Label(
                OWSLocalizedString(
                "REGISTRATION_SCAN_QR_CODE_TUTORIAL_SCAN",
                comment: "Tutorial text describing the third step to scanning the restore/transfer QR code with your old phone: scan the code"
                ),
                image: "qr_code"
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }
}

#if DEBUG
@available(iOS 17, *)
#Preview {
    @Previewable @State var displayMode: RotatingQRCodeView.Model.URLDisplayMode = .loading

    let url1 = URL(string: "https://signal.org")!
    let url2 = URL(string: "https://support.signal.org")!
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
