//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class ProvisioningQRCodeViewController: ProvisioningBaseViewController, ProvisioningSocketManagerUIDelegate {
    private let provisioningQRCodeViewModel: RotatingQRCodeView.Model
    private let provisioningSocketManager: ProvisioningSocketManager

    init(
        provisioningController: ProvisioningController,
        provisioningSocketManager: ProvisioningSocketManager,
    ) {
        provisioningQRCodeViewModel = RotatingQRCodeView.Model(
            urlDisplayMode: .loading,
            onRefreshButtonPressed: { [weak provisioningSocketManager] in
                provisioningSocketManager?.reset()
            },
        )
        self.provisioningSocketManager = provisioningSocketManager

        super.init(provisioningController: provisioningController)

        provisioningSocketManager.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.hidesBackButton = true

        let qrCodeViewHostingContainer = HostingContainer(wrappedView: ProvisioningQRCodeView(
            model: provisioningQRCodeViewModel,
            onCancel: { [unowned self] in
                self.provisioningSocketManager.stop()
                self.provisioningController.cancelProvisioning(from: self)
            },
        ))

        addChild(qrCodeViewHostingContainer)
        view.addSubview(qrCodeViewHostingContainer.view)
        qrCodeViewHostingContainer.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            qrCodeViewHostingContainer.view.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            qrCodeViewHostingContainer.view.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            qrCodeViewHostingContainer.view.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            qrCodeViewHostingContainer.view.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ])
        qrCodeViewHostingContainer.didMove(toParent: self)

        provisioningQRCodeViewModel.updateURLDisplayMode(.loading)
        provisioningSocketManager.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        provisioningSocketManager.stop()
    }

    // MARK: -

    func reset() {
        provisioningSocketManager.stop()
        provisioningQRCodeViewModel.updateURLDisplayMode(.loading)
        provisioningSocketManager.start()
    }

    func provisioningSocketManager(_ provisioningSocketManager: ProvisioningSocketManager, didUpdateProvisioningURL url: URL) {
        provisioningQRCodeViewModel.updateURLDisplayMode(.loaded(url))
    }

    func provisioningSocketManagerDidPauseQRRotation(_ provisioningSocketManager: ProvisioningSocketManager) {
        provisioningQRCodeViewModel.updateURLDisplayMode(.refreshButton)
    }
}

// MARK: -

private struct ProvisioningQRCodeView: View {
    @ObservedObject var model: RotatingQRCodeView.Model
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { overallGeometry in
            let contentWidth = min(overallGeometry.size.width - 48, 440)

            ScrollableContentPinnedFooterView(centersContentVertically: true) {
                VStack(alignment: .center, spacing: 0) {
                    titleLabel

                    Spacer()
                        .frame(height: 24)

                    qrCode(dimension: contentWidth)

                    Spacer()
                        .frame(height: 32)

                    instructionSteps

                    Spacer()
                        .frame(height: 24)

                    helpLink

#if TESTABLE_BUILD
                    if let qrCodeUrl = model.qrCodeViewModel.qrCodeURL {
                        Spacer().frame(height: 24)

                        debugURLActions(qrCodeUrl: qrCodeUrl)
                    }
#endif
                }
                .frame(maxWidth: contentWidth)
            } pinnedFooter: {
                cancelButton
            }
        }
    }

    private var titleLabel: some View {
        Text(OWSLocalizedString(
            "SECONDARY_ONBOARDING_SCAN_CODE_TITLE",
            comment: "header text while displaying a QR code which, when scanned, will link this device.",
        ))
        .font(.title)
        .fontWeight(.semibold)
        .foregroundStyle(Color.Signal.label)
        .multilineTextAlignment(.center)
    }

    private func qrCode(dimension: CGFloat) -> some View {
        RotatingQRCodeView(model: self.model)
            .frame(width: dimension, height: dimension)
    }

    private var instructionSteps: some View {
        VStack(alignment: .leading, spacing: 24) {
            InstructionStep(
                icon: .devicePhone,
                text: OWSLocalizedString(
                    "SECONDARY_ONBOARDING_SCAN_CODE_STEP_OPEN_PRIMARY",
                    comment: "First bullet point on the QR code screen for linking a device",
                ),
            )
            InstructionStep(
                icon: .personCircle,
                text: OWSLocalizedString(
                    "SECONDARY_ONBOARDING_SCAN_CODE_STEP_OPEN_SETTINGS",
                    comment: "Second bullet point on the QR code screen for linking a device",
                ),
            )
            InstructionStep(
                icon: .devices,
                text: OWSLocalizedString(
                    "SECONDARY_ONBOARDING_SCAN_CODE_STEP_LINK_DEVICE",
                    comment: "Third bullet point on the QR code screen for linking a device",
                ),
            )
        }
    }

    @ViewBuilder
    private func debugURLActions(qrCodeUrl: URL) -> some View {
        Button(LocalizationNotNeeded("Debug only: Copy URL")) {
            UIPasteboard.general.url = qrCodeUrl
        }
    }

    private var helpLink: some View {
        Link(
            OWSLocalizedString(
                "SECONDARY_ONBOARDING_SCAN_CODE_HELP_TEXT",
                comment: "Link text for page with troubleshooting info shown on the QR scanning screen",
            ),
            destination: URL.Support.troubleshootingMultipleDevices,
        )
        .font(.subheadline.weight(.semibold))
    }

    private var cancelButton: some View {
        Button(CommonStrings.cancelButton, action: onCancel)
            .buttonStyle(Registration.UI.MediumSecondaryButtonStyle())
            .padding(.bottom, NSDirectionalEdgeInsets.buttonContainerLayoutMargins.bottom)
    }
}

// MARK: -

private struct InstructionStep: View {
    let icon: ImageResource
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
            Text(text)
                .font(.headline.weight(.regular))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.Signal.secondaryLabel)
    }
}

// MARK: - Previews

#if DEBUG
private struct PreviewView: View {
    let urlDisplayMode: RotatingQRCodeView.Model.URLDisplayMode

    var body: some View {
        ProvisioningQRCodeView(
            model: RotatingQRCodeView.Model(
                urlDisplayMode: urlDisplayMode,
                onRefreshButtonPressed: {},
            ),
            onCancel: {},
        )
        .padding(.horizontal, 16)
    }
}

#Preview("Loaded") {
    PreviewView(urlDisplayMode: .loaded(URL(string: "https://signal.org")!))
}

#Preview("Loading") {
    PreviewView(urlDisplayMode: .loading)
}

#Preview("Refresh Button") {
    PreviewView(urlDisplayMode: .refreshButton)
}
#endif
