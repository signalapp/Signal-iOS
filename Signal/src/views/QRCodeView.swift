//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class QRCodeView: UIView {

    // MARK: - UIView overrides

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(qrCodeWrapper)
        qrCodeWrapper.autoCenterInSuperview()
        qrCodeWrapper.autoPinToSquareAspectRatio()
        qrCodeWrapper.autoSetDimension(
            .width,
            toSize: UIDevice.current.isNarrowerThanIPhone6 ? 256 : 311,
            relation: .greaterThanOrEqual
        )
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
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
        wrapper.backgroundColor = .ows_gray02
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

    func setQR(url: URL) throws { setQR(image: try buildQRImage(url: url)) }

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
        qrCodeView.autoMatch(.height, to: .height, of: qrCodeWrapper, withMultiplier: 0.6)
    }

    private func buildQRImage(url: URL) throws -> UIImage {
        guard let urlData: Data = url.absoluteString.data(using: .utf8) else {
            throw OWSAssertionError("urlData was unexpectedly nil")
        }

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw OWSAssertionError("filter was unexpectedly nil")
        }
        filter.setDefaults()
        filter.setValue(urlData, forKey: "inputMessage")

        guard let ciImage = filter.outputImage else {
            throw OWSAssertionError("ciImage was unexpectedly nil")
        }

        // Change the color using CIFilter
        let colorParameters = [
            "inputColor0": CIColor(color: Theme.lightThemePrimaryColor), // Foreground
            "inputColor1": CIColor(color: .clear) // Background
        ]

        let recoloredCIIimage = ciImage.applyingFilter("CIFalseColor", parameters: colorParameters)

        // UIImages backed by a CIImage won't render without antialiasing, so we convert the backing
        // image to a CGImage, which can be scaled crisply.
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(recoloredCIIimage, from: recoloredCIIimage.extent) else {
            throw OWSAssertionError("cgImage was unexpectedly nil")
        }

        let image = UIImage(cgImage: cgImage)

        return image
    }
}
