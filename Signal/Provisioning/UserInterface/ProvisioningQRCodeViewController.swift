//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class ProvisioningQRCodeViewController: ProvisioningBaseViewController, ProvisioningSocketManagerUIDelegate {
    private let provisioningQRCodeViewModel: ProvisioningQRCodeView.Model
    private let provisioningSocketManager: ProvisioningSocketManager

    init(
        provisioningController: ProvisioningController,
        provisioningSocketManager: ProvisioningSocketManager
    ) {
        provisioningQRCodeViewModel = ProvisioningQRCodeView.Model(urlDisplayMode: .loading)
        self.provisioningSocketManager = provisioningSocketManager

        super.init(provisioningController: provisioningController)

        provisioningSocketManager.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        let qrCodeViewHostingContainer = HostingContainer(wrappedView: ProvisioningQRCodeView(
            model: provisioningQRCodeViewModel,
            onRefreshButtonPressed: { [weak self] in
                self?.provisioningSocketManager.reset()
            }
        ))

        addChild(qrCodeViewHostingContainer)
        primaryView.addSubview(qrCodeViewHostingContainer.view)
        qrCodeViewHostingContainer.view.autoPinEdgesToSuperviewMargins()
        qrCodeViewHostingContainer.didMove(toParent: self)

        provisioningQRCodeViewModel.updateURLDisplayMode(.loading)
        provisioningSocketManager.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        provisioningSocketManager.stop()
    }

    // MARK: -

    override func shouldShowBackButton() -> Bool {
        // Never show the back button here
        return false
    }

    func reset() {
        provisioningSocketManager.stop()
        provisioningQRCodeViewModel.updateURLDisplayMode(.loading)
        provisioningSocketManager.start()
    }

    func provisioningSocketManager(_ provisioningSocketManager: ProvisioningSocketManager, didUpdateProvisioningURL url: URL) {
        provisioningQRCodeViewModel.updateURLDisplayMode(.loaded(url))
    }

    public func provisioningSocketManagerDidPauseQRRotation(_ provisioningSocketManager: ProvisioningSocketManager) {
        provisioningQRCodeViewModel.updateURLDisplayMode(.refreshButton)
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
