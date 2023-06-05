//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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

    var qrCodeView: UIView?

    lazy var qrCodeWrapper: UIView = {
        let wrapper = UIView()
        if useCircularWrapper {
            wrapper.backgroundColor = .ows_gray02
        }
        return wrapper
    }()

    lazy var placeholderView: UIView = {
        let placeholder = UIView()

        let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)
        placeholder.addSubview(activityIndicator)
        activityIndicator.color = Theme.lightThemePrimaryColor
        activityIndicator.autoCenterInSuperview()
        activityIndicator.autoSetDimensions(to: .init(width: 40, height: 40))
        activityIndicator.startAnimating()

        return placeholder
    }()

    // MARK: -

    func setQR(url: URL) throws { setQR(image: try Self.buildQRImage(url: url)) }

    func setQR(image: UIImage) {
        assert(qrCodeView == nil)
        placeholderView.removeFromSuperview()

        let qrCodeView = UIImageView(image: image)

        // Don't antialias QR Codes.
        qrCodeView.layer.magnificationFilter = .nearest
        qrCodeView.layer.minificationFilter = .nearest

        self.qrCodeView = qrCodeView

        qrCodeWrapper.addSubview(qrCodeView)
        qrCodeView.autoPinToSquareAspectRatio()
        qrCodeView.autoCenterInSuperview()
        if useCircularWrapper {
            qrCodeView.autoMatch(.height, to: .height, of: qrCodeWrapper, withMultiplier: 0.6)
        } else {
            qrCodeView.autoPinEdgesToSuperviewMargins()
        }
    }

    public static func buildQRImage(url: URL, forExport: Bool = false) throws -> UIImage {
        guard let urlData: Data = url.absoluteString.data(using: .utf8) else {
            throw OWSAssertionError("urlData was unexpectedly nil")
        }
        return try buildQRImage(data: urlData, forExport: forExport)
    }

    public static func buildQRImage(data: Data, forExport: Bool = false) throws -> UIImage {
        let foregroundColor: UIColor = (forExport ? .black : Theme.lightThemePrimaryColor)
        let backgroundColor: UIColor = (forExport ? .white : .clear)
        return try buildQRImage(data: data,
                                foregroundColor: foregroundColor,
                                backgroundColor: backgroundColor,
                                largeSize: forExport)
    }

    public static func buildQRImage(data: Data,
                                    foregroundColor: UIColor,
                                    backgroundColor: UIColor,
                                    largeSize: Bool) throws -> UIImage {

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw OWSAssertionError("filter was unexpectedly nil")
        }
        filter.setDefaults()
        filter.setValue(data, forKey: "inputMessage")

        guard let ciImage = filter.outputImage else {
            throw OWSAssertionError("ciImage was unexpectedly nil")
        }

        // Change the color using CIFilter
        let colorParameters = [
            "inputColor0": CIColor(color: foregroundColor),
            "inputColor1": CIColor(color: backgroundColor)
        ]

        let recoloredCIImage = ciImage.applyingFilter("CIFalseColor", parameters: colorParameters)

        // When exporting, scale up the output so that each pixel of the
        // QR code is represented by a 10x10 pixel block.
        let scaledCIIimage = (largeSize
            ? recoloredCIImage.transformed(by: CGAffineTransform.scale(10.0))
            : recoloredCIImage)

        // UIImages backed by a CIImage won't render without antialiasing, so we convert the backing
        // image to a CGImage, which can be scaled crisply.
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaledCIIimage, from: scaledCIIimage.extent) else {
            throw OWSAssertionError("cgImage was unexpectedly nil")
        }

        let image = UIImage(cgImage: cgImage)
        return image
    }
}
