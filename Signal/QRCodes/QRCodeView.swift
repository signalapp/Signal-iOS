//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class QRCodeView: UIView {
    private let qrCodeTintColor: QRCodeColor

    private let loadingSpinner = UIActivityIndicatorView()
    private let qrCodeImageView = UIImageView()
    private let errorImageView: UIImageView = .withTemplateImageName("error-circle", tintColor: .ows_gray25)

    init(
        qrCodeTintColor: QRCodeColor = .blue,
        contentInset: CGFloat = 20,
        cornerRadius: CGFloat = 12,
        borderWidth: CGFloat = 2,
    ) {
        self.qrCodeTintColor = qrCodeTintColor

        super.init(frame: .zero)

        // MARK: View properties

        backgroundColor = .white
        layoutMargins = UIEdgeInsets(margin: contentInset)
        layer.cornerRadius = cornerRadius
        layer.borderWidth = borderWidth
        layer.borderColor = qrCodeTintColor.paddingBorder.cgColor

        loadingSpinner.style = .large
        loadingSpinner.color = Theme.lightThemePrimaryColor
        loadingSpinner.hidesWhenStopped = true

        // Don't antialias QR codes
        qrCodeImageView.layer.magnificationFilter = .nearest
        qrCodeImageView.layer.minificationFilter = .nearest

        // MARK: Layout

        addSubview(loadingSpinner)
        loadingSpinner.autoSetDimensions(to: .square(40))
        loadingSpinner.autoPinEdgesToSuperviewMargins()

        addSubview(qrCodeImageView)
        qrCodeImageView.autoPinEdgesToSuperviewMargins()
        qrCodeImageView.contentMode = .scaleAspectFit

        addSubview(errorImageView)
        errorImageView.autoSetDimensions(to: .square(40))
        errorImageView.autoCenterInSuperviewMargins()

        setLoading()
    }

    required init?(coder: NSCoder) {
        owsFail("Not implemented!")
    }

    // MARK: -

    private enum Mode {
        case loadingSpinner
        case qrCodeImage(UIImage)
        case errorImage
    }

    private func setMode(_ mode: Mode) {
        switch mode {
        case .loadingSpinner:
            loadingSpinner.startAnimating()
            qrCodeImageView.isHidden = true
            errorImageView.isHidden = true
        case .qrCodeImage(let image):
            loadingSpinner.stopAnimating()
            qrCodeImageView.isHidden = false
            errorImageView.isHidden = true

            qrCodeImageView.setTemplateImage(image, tintColor: qrCodeTintColor.foreground)
        case .errorImage:
            loadingSpinner.stopAnimating()
            qrCodeImageView.isHidden = true
            errorImageView.isHidden = false
        }
    }

    // MARK: -

    func setLoading() {
        setMode(.loadingSpinner)
    }

    func setError() {
        setMode(.errorImage)
    }

    func setQRCode(image: UIImage) {
        setMode(.qrCodeImage(image))
    }

    func setQRCode(
        url: URL,
        stylingMode: QRCodeGenerator.StylingMode = .brandedWithLogo,
    ) {
        let qrCodeImage = QRCodeGenerator().generateQRCode(
            url: url,
            stylingMode: stylingMode,
        )

        if let qrCodeImage {
            setMode(.qrCodeImage(qrCodeImage))
        } else {
            setMode(.errorImage)
        }
    }
}

// MARK: -

struct QRCodeViewRepresentable: UIViewRepresentable {
    class Model: ObservableObject {
        @Published var qrCodeURL: URL?

        init(qrCodeURL: URL?) {
            self.qrCodeURL = qrCodeURL
        }
    }

    @ObservedObject
    private var model: Model

    private let qrCodeStylingMode: QRCodeGenerator.StylingMode
    private let qrCodeTintColor: QRCodeColor
    private let contentInset: CGFloat
    private let cornerRadius: CGFloat
    private let borderWidth: CGFloat

    init(
        model: Model,
        qrCodeStylingMode: QRCodeGenerator.StylingMode = .brandedWithLogo,
        qrCodeTintColor: QRCodeColor = .blue,
        contentInset: CGFloat = 20,
        cornerRadius: CGFloat = 12,
        borderWidth: CGFloat = 2,
    ) {
        self.model = model
        self.qrCodeStylingMode = qrCodeStylingMode
        self.qrCodeTintColor = qrCodeTintColor
        self.contentInset = contentInset
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
    }

    // MARK: -

    typealias UIViewType = QRCodeView

    func makeUIView(context: Context) -> QRCodeView {
        let qrCodeView = QRCodeView(
            qrCodeTintColor: qrCodeTintColor,
            contentInset: contentInset,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
        )

        updateUIView(qrCodeView, context: context)
        return qrCodeView
    }

    func updateUIView(_ qrCodeView: QRCodeView, context: Context) {
        if let url = model.qrCodeURL {
            qrCodeView.setQRCode(
                url: url,
                stylingMode: qrCodeStylingMode,
            )
        } else {
            qrCodeView.setLoading()
        }
    }
}

struct RotatingQRCodeView: View {
    class Model: ObservableObject {
        enum URLDisplayMode {
            case loading
            case loaded(URL)
            case refreshButton
        }

        @Published
        private(set) var urlDisplayMode: URLDisplayMode
        let onRefreshButtonPressed: () -> Void

        let qrCodeViewModel: QRCodeViewRepresentable.Model

        init(urlDisplayMode: URLDisplayMode, onRefreshButtonPressed: @escaping () -> Void) {
            self.urlDisplayMode = .loading
            self.onRefreshButtonPressed = onRefreshButtonPressed
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

    @ObservedObject var model: Model

    var body: some View {
        GeometryReader { qrCodeGeometry in
            ZStack {
                Color(UIColor.ows_gray02)
                    .cornerRadius(24)

                switch model.urlDisplayMode {
                case .loading, .loaded:
                    QRCodeViewRepresentable(model: model.qrCodeViewModel)
                        .padding(qrCodeGeometry.size.height * 0.1)
                case .refreshButton:
                    Button(action: model.onRefreshButtonPressed) {
                        HStack {
                            Image("refresh")

                            Text(OWSLocalizedString(
                                "SECONDARY_ONBOARDING_SCAN_CODE_REFRESH_CODE_BUTTON",
                                comment: "Text for a button offering to refresh the QR code to link an iPad.",
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
    }
}

// MARK: - Previews

#Preview {
    VStack {
        RotatingQRCodeView(model: .init(
            urlDisplayMode: .loaded(URL(string: "https://signal.org")!),
            onRefreshButtonPressed: {},
        ))

        RotatingQRCodeView(model: .init(urlDisplayMode: .loading, onRefreshButtonPressed: {}))

        RotatingQRCodeView(model: .init(urlDisplayMode: .refreshButton, onRefreshButtonPressed: {}))
    }
    .padding()
}
