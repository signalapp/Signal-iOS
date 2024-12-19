//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit

class QRCodeView: UIView {
    private let qrCodeTintColor: QRCodeColor

    private let loadingSpinner = UIActivityIndicatorView()
    private let qrCodeImageView = UIImageView()
    private let errorImageView: UIImageView = .withTemplateImageName("error-circle", tintColor: .ows_gray25)

    init(
        qrCodeTintColor: QRCodeColor = .blue,
        contentInset: CGFloat = 20,
        cornerRadius: CGFloat = 12,
        borderWidth: CGFloat = 2
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
        stylingMode: QRCodeGenerator.StylingMode = .brandedWithLogo
    ) {
        let qrCodeImage = QRCodeGenerator().generateQRCode(
            url: url,
            stylingMode: stylingMode
        )

        if let qrCodeImage {
            setMode(.qrCodeImage(qrCodeImage))
        } else {
            setMode(.errorImage)
        }
    }
}
