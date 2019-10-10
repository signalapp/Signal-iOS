//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SecondaryLinkingQRCodeViewController: OnboardingBaseViewController {

    var provisioningController: ProvisioningController?

    func configure(provisioningController: ProvisioningController) {
        assert(self.provisioningController == nil)
        self.provisioningController = provisioningController
    }

    override public func loadView() {
        view = UIView()

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_SECONDARY_SCAN_CODE_TITLE", comment: "header text while displaying a QR code which, when scanned, will link this device."))
        view.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.linking.titleLabel"
        titleLabel.setContentHuggingHigh()

        let bodyLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_SECONDARY_SCAN_CODE_BODY", comment: "body text while displaying a QR code which, when scanned, will link this device."))
        bodyLabel.font = UIFont.ows_dynamicTypeBody
        bodyLabel.numberOfLines = 0
        view.addSubview(bodyLabel)
        bodyLabel.accessibilityIdentifier = "onboarding.linking.bodyLabel"
        bodyLabel.setContentHuggingHigh()

        guard let provisioningController = provisioningController else {
            owsFailDebug("provisioningController was unexpectedly nil")
            return
        }
        let qrCodeView = ProvisioningQRCodeView()
        provisioningController.getProvisioningQRImage().done { qrImage in
            qrCodeView.setQRImage(qrImage)
        }.retainUntilComplete()
        qrCodeView.setContentHuggingVerticalLow()

        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("ONBOARDING_SECONDARY_SCAN_CODE_HELP_TEXT",
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
        stackView.layoutMargins = primaryLayoutMargins
        stackView.spacing = 12
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
    }

    // MARK: - Events

    @objc
    func didTapExplanationLabel(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            owsFailDebug("unexpected state: \(sender.state)")
            return
        }

        let alert = UIAlertController(title: "TODO", message: nil, preferredStyle: .alert)
        alert.addAction(OWSAlerts.dismissAction)

        presentAlert(alert)
    }
}

class OnboardingConfirmSecondaryLinkViewController: OnboardingBaseViewController {
    var provisioningController: ProvisioningController?

    func configure(provisioningController: ProvisioningController) {
        assert(self.provisioningController == nil)
        self.provisioningController = provisioningController
    }

    let textField = UITextField()

    // MARK: UIViewController overrides

    override public func loadView() {
        view = UIView()

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_SECONDARY_CHOOSE_DEVICE_NAME", comment: "header text when this device is being added as a secondary"))
        view.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "onboarding.linking.titleLabel"
        titleLabel.setContentHuggingHigh()

        // FIXME NEEDS_DESIGN
        textField.borderStyle = .roundedRect
        let textFieldWrapper = UIView()
        textFieldWrapper.addSubview(textField)
        textField.autoSetDimension(.width, toSize: 200)
        textField.autoCenterInSuperview()

        let primaryButton = self.primaryButton(title: NSLocalizedString("ONBOARDING_SECONDARY_COMPLETE_LINKING_PROCESS", comment: "body text while displaying a QR code which, when scanned, will link this device."),
                           selector: #selector(didTapFinalizeLinking))
        primaryButton.accessibilityIdentifier = "onboarding.confirmLink.confirmButton"
        let primaryButtonView = OWSFlatButton.horizontallyWrap(primaryButton: primaryButton)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            textFieldWrapper,
            UIView.vStretchingSpacer(),
            primaryButtonView
            ])

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = primaryLayoutMargins
        stackView.spacing = 12
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
    }

    // MARK: -

    @objc
    func didTapFinalizeLinking() {
        // TODO sanatize
        guard let deviceName = textField.text?.ows_stripped() else {
            return
        }

        guard let provisioningController = self.provisioningController else {
            owsFailDebug("provisioningController was unexpectedly nil")
            return
        }

        provisioningController.provisioningDidChooseDeviceName(deviceName)
    }
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
