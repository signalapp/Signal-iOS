//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationQuickRestoreQRCodePresenter: AnyObject {
    func cancel()
}

public struct RegistrationQuickRestoreQRCodeState: Equatable {
    let url: URL
}

class RegistrationQuickRestoreQRCodeViewController: OWSViewController, OWSNavigationChildController {
    private let state: RegistrationQuickRestoreQRCodeState
    private weak var presenter: RegistrationQuickRestoreQRCodePresenter?

    init(
        state: RegistrationQuickRestoreQRCodeState,
        presenter: RegistrationQuickRestoreQRCodePresenter
    ) {
        self.state = state
        self.presenter = presenter
        super.init()

        self.addChild(hostingController)
        self.view.addSubview(hostingController.view)
        hostingController.view.autoPinEdgesToSuperviewEdges()
        hostingController.didMove(toParent: self)
    }

    private lazy var hostingController = UIHostingController(rootView: ContentStack(
        url: self.state.url,
        cancelAction: { [weak self] in
            self?.presenter?.cancel()
        }
    ))

    // MARK: OWSNavigationChildController

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    public var navbarBackgroundColorOverride: UIColor? { .clear }

    public var prefersNavigationBarHidden: Bool { true }
}

// MARK: - SwiftUI

private struct ContentStack: View {
    let url: URL
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
            QRCode(url: url)
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

private struct QRCode: View {
    let url: URL

    var body: some View {
        ZStack {
            Color(.ows_gray02)
                .frame(width: 296, height: 296)
                .cornerRadius(24)
            Color(.ows_white)
                .frame(width: 216, height: 216)
                .cornerRadius(12)
            QRCodeViewRepresentable(url: url)
                .frame(width: 212, height: 212)
        }
    }
}

private struct QRCodeViewRepresentable: UIViewRepresentable {
    var url: URL

    func makeUIView(context: Context) -> QRCodeView {
        let view = QRCodeView(contentInset: 4)

        view.setQRCode(url: url)
        return view
    }

    func updateUIView(_ qrCodeView: QRCodeView, context: Context) {
        // The url will never change, so there's no need to implement this.
    }
}

#if DEBUG

#Preview() {
    ContentStack(url: URL(string: "www.signal.org")!, cancelAction: {})
}

#endif
