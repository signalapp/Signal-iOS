//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SafariServices

@objc
public class SecondaryLinkingQRCodeViewController: OnboardingBaseViewController {

    let provisioningController: ProvisioningController

    required init(provisioningController: ProvisioningController) {
        self.provisioningController = provisioningController
        super.init(onboardingController: provisioningController.onboardingController)
    }

    let qrCodeView = ProvisioningQRCodeView()

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.titleLabel(text: NSLocalizedString("SECONDARY_ONBOARDING_SCAN_CODE_TITLE", comment: "header text while displaying a QR code which, when scanned, will link this device."))
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.linking.titleLabel"
        titleLabel.setContentHuggingHigh()

        let bodyLabel = self.titleLabel(text: NSLocalizedString("SECONDARY_ONBOARDING_SCAN_CODE_BODY", comment: "body text while displaying a QR code which, when scanned, will link this device."))
        bodyLabel.font = UIFont.ows_dynamicTypeBody
        bodyLabel.numberOfLines = 0
        primaryView.addSubview(bodyLabel)
        bodyLabel.accessibilityIdentifier = "onboarding.linking.bodyLabel"
        bodyLabel.setContentHuggingHigh()

        qrCodeView.setContentHuggingVerticalLow()

        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("SECONDARY_ONBOARDING_SCAN_CODE_HELP_TEXT",
                                                  comment: "Link text for page with troubleshooting info shown on the QR scanning screen")
        explanationLabel.textColor = .ows_signalBlue
        explanationLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapExplanationLabel)))
        explanationLabel.accessibilityIdentifier = "onboarding.linking.helpLink"
        explanationLabel.setContentHuggingHigh()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            qrCodeView,
            explanationLabel
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchAndSetQRCode()
    }

    // MARK: - Events

    override func shouldShowBackButton() -> Bool {
        // Never show the back buton here
        // TODO: Linked phones, clean up state to allow backing out
        return false
    }

    @objc
    func didTapExplanationLabel(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            owsFailDebug("unexpected state: \(sender.state)")
            return
        }

        let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/en-us/articles/360007320451")!)
        present(vc, animated: true)
    }

    // MARK: -

    private var hasFetchedAndSetQRCode = false
    public func fetchAndSetQRCode() {
        guard !hasFetchedAndSetQRCode else { return }
        hasFetchedAndSetQRCode = true

        provisioningController.getProvisioningURL().done { url in
            self.qrCodeView.setQRImage(try buildQRImage(url: url))
        }.catch { error in
            let title = NSLocalizedString("SECONDARY_DEVICE_ERROR_FETCHING_LINKING_CODE", comment: "alert title")
            let alert = ActionSheetController(title: title, message: error.localizedDescription)

            let retryAction = ActionSheetAction(title: CommonStrings.retryButton,
                                            accessibilityIdentifier: "alert.retry",
                                            style: .default) { _ in
                                                self.provisioningController.resetPromises()
                                                self.fetchAndSetQRCode()
            }
            alert.addAction(retryAction)
            self.present(alert, animated: true)
        }.retainUntilComplete()
    }
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

    // UIImages backed by a CIImage won't render without antialiasing, so we convert the backing
    // image to a CGImage, which can be scaled crisply.
    let context = CIContext(options: nil)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
        throw OWSAssertionError("cgImage was unexpectedly nil")
    }

    let image = UIImage(cgImage: cgImage)

    return image
}

public class ProvisioningQRCodeView: UIView {

    // MARK: - UIView overrides

    public override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(qrCodeWrapper)
        qrCodeWrapper.autoCenterInSuperview()
        qrCodeWrapper.autoPinToSquareAspectRatio()
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

        let activityIndicator = UIActivityIndicatorView(style: .white)
        placeholder.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()
        activityIndicator.autoSetDimensions(to: .init(width: 40, height: 40))
        activityIndicator.startAnimating()

        return placeholder
    }()

    // MARK: -

    public func setQRImage(_ qrImage: UIImage) {
        assert(qrCodeView == nil)
        placeholderView.removeFromSuperview()

        let qrCodeView = UIImageView(image: qrImage)

        // Don't antialias QR Codes.
        qrCodeView.layer.magnificationFilter = .nearest
        qrCodeView.layer.minificationFilter = .nearest

        self.qrCodeView = qrCodeView

        qrCodeWrapper.addSubview(qrCodeView)
        qrCodeView.autoPinToSquareAspectRatio()
        qrCodeView.autoCenterInSuperview()
        qrCodeView.autoMatch(.height, to: .height, of: qrCodeWrapper, withMultiplier: 0.6)
    }
}
