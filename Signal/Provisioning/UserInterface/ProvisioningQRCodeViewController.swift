//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class ProvisioningQRCodeViewController: ProvisioningBaseViewController {
    private let provisioningQRCodeViewModel: ProvisioningQRCodeView.Model
    private var rotateQRCodeTask: Task<Void, Never>?

    override init(provisioningController: ProvisioningController) {
        provisioningQRCodeViewModel = ProvisioningQRCodeView.Model(urlDisplayMode: .loading)

        super.init(provisioningController: provisioningController)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        let qrCodeViewHostingContainer = HostingContainer(wrappedView: ProvisioningQRCodeView(
            model: provisioningQRCodeViewModel,
            onRefreshButtonPressed: { [weak self] in
                self?.startQRCodeRotationTask()
            }
        ))

        addChild(qrCodeViewHostingContainer)
        primaryView.addSubview(qrCodeViewHostingContainer.view)
        qrCodeViewHostingContainer.view.autoPinEdgesToSuperviewMargins()
        qrCodeViewHostingContainer.didMove(toParent: self)

        startQRCodeRotationTask()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        rotateQRCodeTask?.cancel()
    }

    // MARK: -

    override func shouldShowBackButton() -> Bool {
        // Never show the back button here
        return false
    }

    // MARK: -

    func reset() {
        rotateQRCodeTask?.cancel()
        rotateQRCodeTask = nil
        provisioningQRCodeViewModel.updateURLDisplayMode(.loading)
        startQRCodeRotationTask()
    }

    private func startQRCodeRotationTask() {
        AssertIsOnMainThread()

        guard rotateQRCodeTask == nil else {
            return
        }

        rotateQRCodeTask = Task {
            /// Every 45s, five times, rotate the provisioning socket for which
            /// we're displaying a QR code. If we fail, or once we've exhausted
            /// the five rotations, fall back to showing a manual "refresh"
            /// button.
            ///
            /// Note that the server will close provisioning sockets after 90s,
            /// so hopefully rotating every 45s means no primary will ever end
            /// up trying to send into a closed socket.
            do {
                for _ in 0..<5 {
                    let provisioningUrl = try await provisioningController.openNewProvisioningSocket()

                    try Task.checkCancellation()

                    provisioningQRCodeViewModel.updateURLDisplayMode(.loaded(provisioningUrl))

                    let rotationDelaySecs: UInt64
#if TESTABLE_BUILD
                    rotationDelaySecs = 3
#else
                    rotationDelaySecs = 45
#endif

                    try await Task.sleep(nanoseconds: rotationDelaySecs * NSEC_PER_SEC)

                    try Task.checkCancellation()
                }
            } catch is CancellationError {
                // We've been canceled; bail! It's the canceler's responsibility
                // to make sure the UI is updated.
                return
            } catch {
                // Fall through as if we'd exhausted our rotations.
            }

            provisioningQRCodeViewModel.updateURLDisplayMode(.refreshButton)
            rotateQRCodeTask = nil
        }
    }
}

// MARK: -

private struct ProvisioningQRCodeView: View {
    class Model: ObservableObject {
        enum URLDisplayMode {
            case loading
            case loaded(URL)
            case refreshButton
        }

        @Published
        private(set) var urlDisplayMode: URLDisplayMode

        let qrCodeViewModel: QRCodeViewRepresentable.Model

        init(urlDisplayMode: URLDisplayMode) {
            self.urlDisplayMode = .loading
            self.qrCodeViewModel = QRCodeViewRepresentable.Model(qrCodeURL: nil)

            updateURLDisplayMode(urlDisplayMode)
        }

        func updateURLDisplayMode(_ newValue: URLDisplayMode) {
            urlDisplayMode = newValue

            qrCodeViewModel.qrCodeURL = switch urlDisplayMode {
            case .loaded(let url): url
            case .loading, .refreshButton: nil
            }
        }
    }

    @ObservedObject
    private var model: Model

    private let onRefreshButtonPressed: () -> Void

    init(model: Model, onRefreshButtonPressed: @escaping () -> Void) {
        self.model = model
        self.onRefreshButtonPressed = onRefreshButtonPressed
    }

    var body: some View {
        GeometryReader { overallGeometry in
            VStack(spacing: 12) {
                Text(OWSLocalizedString(
                    "SECONDARY_ONBOARDING_SCAN_CODE_TITLE",
                    comment: "header text while displaying a QR code which, when scanned, will link this device."
                ))
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(Color.Signal.label)

                Text(OWSLocalizedString(
                    "SECONDARY_ONBOARDING_SCAN_CODE_BODY",
                    comment: "body text while displaying a QR code which, when scanned, will link this device."
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.label)

                Spacer()
                    .frame(height: overallGeometry.size.height * 0.05)

                GeometryReader { qrCodeGeometry in
                    ZStack {
                        Color(UIColor.ows_gray02)
                            .cornerRadius(24)

                        switch model.urlDisplayMode {
                        case .loading, .loaded:
                            QRCodeViewRepresentable(model: model.qrCodeViewModel)
                                .padding(qrCodeGeometry.size.height * 0.1)
                        case .refreshButton:
                            Button(action: onRefreshButtonPressed) {
                                HStack {
                                    Image("refresh")

                                    Text(OWSLocalizedString(
                                        "SECONDARY_ONBOARDING_SCAN_CODE_REFRESH_CODE_BUTTON",
                                        comment: "Text for a button offering to refresh the QR code to link an iPad."
                                    ))
                                    .font(.body)
                                    .fontWeight(.bold)
                                }
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                            }
                            .background {
                                Capsule().fill(Color.white)
                            }
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                Spacer()
                    .frame(height: overallGeometry.size.height * (overallGeometry.size.isLandscape ? 0.05 : 0.1))

                Link(
                    OWSLocalizedString(
                        "SECONDARY_ONBOARDING_SCAN_CODE_HELP_TEXT",
                        comment: "Link text for page with troubleshooting info shown on the QR scanning screen"
                    ),
                    destination: URL(string: "https://support.signal.org/hc/articles/360007320451")!
                )
                .font(.subheadline)
                .foregroundStyle(Color.Signal.accent)

#if TESTABLE_BUILD
                if
                    #available(iOS 16.0, *),
                    let provisioningUrl = model.qrCodeViewModel.qrCodeURL
                {
                    // If on a physical device, this prefixing with some text
                    // allows one to AirDrop the URL to macOS to be copied into
                    // a simulator, instead of having macOS automatically try
                    // and open the URL (which Signal Desktop will try, and
                    // fail, to handle).
                    ShareLink(item: "Provisioning URL: \(provisioningUrl)") {
                        Text(LocalizationNotNeeded(
                            "Debug only: Share URL"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(Color.Signal.accent)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        // When tapped, also copy to the clipboard for easy
                        // extraction from a simulator.
                        UIPasteboard.general.url = provisioningUrl
                    })
                }
#endif
            }
            .multilineTextAlignment(.center)
        }
    }
}

// MARK: -

private struct PreviewView: View {
    let urlDisplayMode: ProvisioningQRCodeView.Model.URLDisplayMode

    var body: some View {
        ProvisioningQRCodeView(
            model: ProvisioningQRCodeView.Model(urlDisplayMode: urlDisplayMode),
            onRefreshButtonPressed: {}
        )
        .padding(112)
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
