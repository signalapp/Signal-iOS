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

    private enum QRCodeImageMode {
        case image(UIImage)
        case templateImage(UIImage, tintColor: UIColor)
        case error
    }

    /// Generate and display a QR code for the given URL.
    func setQR(url: URL, generator: QRCodeGenerator = BasicDisplayQRCodeGenerator()) {
        guard let qrCodeImage = generator.generateQRCode(url: url) else {
            setQR(imageMode: .error)
            return
        }

        setQR(imageMode: .image(qrCodeImage))
    }

    /// Display the given QR code template image, tinted with the given color.
    ///
    /// - Parameter templateImage
    /// The QR code image to display. This image should be a template image. See
    /// ``UIImage.RenderingMode``.
    func setQR(templateImage: UIImage, tintColor: UIColor) {
        setQR(imageMode: .templateImage(templateImage, tintColor: tintColor))
    }

    func setQRError() {
        setQR(imageMode: .error)
    }

    private func setQR(imageMode: QRCodeImageMode) {
        qrCodeView?.removeFromSuperview()
        placeholderView.removeFromSuperview()

        let qrCodeImageView: UIImageView = {
            switch imageMode {
            case let .image(qrCodeImage):
                return UIImageView(image: qrCodeImage)
            case let .templateImage(qrCodeTemplateImage, tintColor):
                return UIImageView.withTemplateImage(
                    qrCodeTemplateImage,
                    tintColor: tintColor
                )
            case .error:
                return UIImageView.withTemplateImageName(
                    "error-circle",
                    tintColor: .ows_accentRed
                )
            }
        }()

        defer {
            qrCodeView = qrCodeImageView
        }

        // Don't antialias QR Codes.
        qrCodeImageView.layer.magnificationFilter = .nearest
        qrCodeImageView.layer.minificationFilter = .nearest

        qrCodeWrapper.addSubview(qrCodeImageView)
        qrCodeImageView.autoCenterInSuperview()

        switch imageMode {
        case .image, .templateImage:
            qrCodeImageView.autoPinToSquareAspectRatio()

            if useCircularWrapper {
                qrCodeImageView.autoMatch(
                    .height,
                    to: .height,
                    of: qrCodeWrapper,
                    withMultiplier: Constants.circleToQRCodeSizeMultiplier
                )
            } else {
                qrCodeImageView.autoPinEdgesToSuperviewEdges()
            }
        case .error:
            qrCodeImageView.autoSetDimensions(to: .square(48))
        }
    }

    public enum Constants {
        public static let circleToQRCodeSizeMultiplier: CGFloat = 0.6
    }
}
