//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

class QRCodeView: UIView {

    // MARK: - UIView overrides

    private let qrCodeGenerator: QRCodeGenerator
    private let useCircularWrapper: Bool

    public required init(
        qrCodeGenerator: QRCodeGenerator = BasicDisplayQRCodeGenerator(),
        useCircularWrapper: Bool = true
    ) {
        self.qrCodeGenerator = qrCodeGenerator
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

    func setQR(url: URL) {
        owsAssertDebug(qrCodeView == nil)

        guard let qrCodeImage = qrCodeGenerator.generateQRCode(url: url) else {
            owsFailDebug("Failed to generate QR code image!")
            return
        }

        // Don't remove until we successfully generate the image!
        placeholderView.removeFromSuperview()

        let qrCodeView = UIImageView(image: qrCodeImage)

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
}
