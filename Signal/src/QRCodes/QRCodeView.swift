//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

class QRCodeView: UIView {

    // MARK: - UIView overrides

    private let useCircularWrapper: Bool

    public required init(useCircularWrapper: Bool = true) {
        self.useCircularWrapper = useCircularWrapper

        super.init(frame: .zero)

        addSubview(qrCodeWrapper)

        qrCodeWrapper.autoPinToSquareAspectRatio()

        if useCircularWrapper {
            qrCodeWrapper.autoCenterInSuperview()
            qrCodeWrapper.autoSetDimension(
                .width,
                toSize: UIDevice.current.isNarrowerThanIPhone6 ? 256 : 311,
                relation: .greaterThanOrEqual
            )
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                qrCodeWrapper.autoPinEdgesToSuperviewMargins()
            }
        } else {
            qrCodeWrapper.autoPinEdgesToSuperviewMargins()
        }

        qrCodeWrapper.addSubview(placeholderView)
        placeholderView.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        qrCodeWrapper.layer.cornerRadius = qrCodeWrapper.frame.width / 2
    }

    // MARK: - Subviews

    private var qrCodeView: UIView?

    private lazy var qrCodeWrapper: UIView = {
        let wrapper = UIView()
        if useCircularWrapper {
            wrapper.backgroundColor = .ows_gray02
        }
        return wrapper
    }()

    private lazy var placeholderView: UIView = {
        let placeholder = UIView()

        let activityIndicator = UIActivityIndicatorView(style: .large)
        placeholder.addSubview(activityIndicator)
        activityIndicator.color = Theme.lightThemePrimaryColor
        activityIndicator.autoCenterInSuperview()
        activityIndicator.autoSetDimensions(to: .init(width: 40, height: 40))
        activityIndicator.startAnimating()

        return placeholder
    }()

    // MARK: -

    /// Generate and display a QR code for the given URL.
    func setQR(url: URL, generator: QRCodeGenerator = BasicDisplayQRCodeGenerator()) {
        guard let qrCodeImage = generator.generateQRCode(url: url) else {
            owsFailDebug("Failed to generate QR code image!")
            return
        }

        setQR(imageView: UIImageView(image: qrCodeImage))
    }

    /// Display the given QR code template image, tinted with the given color.
    ///
    /// - Parameter templateImage
    /// The QR code image to display. This image should be a template image. See
    /// ``UIImage.RenderingMode``.
    func setQR(templateImage: UIImage, tintColor: UIColor) {
        owsAssert(templateImage.renderingMode == .alwaysTemplate)

        let imageView = UIImageView(image: templateImage)
        imageView.tintColor = tintColor

        setQR(imageView: imageView)
    }

    /// Display the given QR code image.
    private func setQR(imageView qrCodeImageView: UIImageView) {
        qrCodeView?.removeFromSuperview()
        placeholderView.removeFromSuperview()

        // Don't antialias QR Codes.
        qrCodeImageView.layer.magnificationFilter = .nearest
        qrCodeImageView.layer.minificationFilter = .nearest

        qrCodeWrapper.addSubview(qrCodeImageView)
        qrCodeImageView.autoPinToSquareAspectRatio()
        qrCodeImageView.autoCenterInSuperview()
        if useCircularWrapper {
            qrCodeImageView.autoMatch(.height, to: .height, of: qrCodeWrapper, withMultiplier: 0.6)
        } else {
            qrCodeImageView.autoPinEdgesToSuperviewMargins()
        }

        qrCodeView = qrCodeImageView
    }
}
