//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class Deprecated_SecondaryLinkingSetDeviceNameViewController: Deprecated_OnboardingBaseViewController {

    let provisioningController: Deprecated_ProvisioningController

    init(provisioningController: Deprecated_ProvisioningController) {
        self.provisioningController = provisioningController
        super.init(onboardingController: provisioningController.onboardingController)
    }

    // MARK: UIViewController overrides

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(text: NSLocalizedString("SECONDARY_ONBOARDING_CHOOSE_DEVICE_NAME", comment: "header text when this device is being added as a secondary"))
        primaryView.addSubview(titleLabel)
        titleLabel.accessibilityIdentifier = "linking.deviceName.titleLabel"
        titleLabel.setContentHuggingHigh()

        let explanationLabel = self.createExplanationLabel(explanationText: NSLocalizedString("SECONDARY_ONBOARDING_CHOOSE_DEVICE_NAME_EXPLANATION",
                                                                                        comment: "label text"))
        explanationLabel.accessibilityIdentifier = "linking.deviceName.explanationLabel"

        textField.autoSetDimension(.width, toSize: 200)
        textField.placeholder = NSLocalizedString("SECONDARY_ONBOARDING_CHOOSE_DEVICE_NAME_PLACEHOLDER", comment: "text field placeholder")
        textField.textColor = Theme.primaryTextColor
        textField.font = UIFont.ows_dynamicTypeBodyClamped
        textField.accessibilityIdentifier = "linking.deviceName.textField"
        textField.text = UIDevice.current.name
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        textField.setCompressionResistanceHigh()

        textFieldStrokeNormal = textField.addBottomStroke()
        textFieldStrokeError = textField.addBottomStroke(color: .ows_accentRed, strokeWidth: 2)
        textFieldStrokeError.isHidden = true

        validationErrorLabel = UILabel()
        validationErrorLabel.textColor = .ows_accentRed
        validationErrorLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        validationErrorLabel.autoSetDimension(.height, toSize: validationErrorLabel.font.lineHeight)
        validationErrorLabel.accessibilityIdentifier = "linking.deviceName.validationErrorLabel"
        validationErrorLabel.setCompressionResistanceHigh()

        let textFieldStack = UIStackView(arrangedSubviews: [textField, validationErrorLabel])
        textFieldStack.axis = .vertical
        textFieldStack.alignment = .center
        textFieldStack.setCompressionResistanceHigh()

        let primaryButton = self.primaryButton(title: NSLocalizedString("SECONDARY_ONBOARDING_COMPLETE_LINKING_PROCESS", comment: "body text while displaying a QR code which, when scanned, will link this device."),
                                               selector: #selector(didTapFinalizeLinking))
        primaryButton.accessibilityIdentifier = "onboarding.confirmLink.confirmButton"
        let primaryButtonView = Deprecated_OnboardingBaseViewController.horizontallyWrap(primaryButton: primaryButton)

        let aboveTextFieldSpacer = UIView.vStretchingSpacer(maxHeight: 60)
        let belowTextFieldSpacer = UIView.vStretchingSpacer()
        let compressableBottomMargin = UIView.vStretchingSpacer(minHeight: 16, maxHeight: primaryLayoutMargins.bottom)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            aboveTextFieldSpacer,
            textFieldStack,
            belowTextFieldSpacer,
            primaryButtonView,
            compressableBottomMargin
            ])

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        primaryView.addSubview(stackView)

        // Because of the keyboard, vertical spacing can get pretty cramped,
        // so we have custom spacer logic.
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)
        stackView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)
    }

    // MARK: -

    let textField = UITextField()
    var validationErrorLabel: UILabel!
    var textFieldStrokeError: UIView!
    var textFieldStrokeNormal: UIView!

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    var textFieldValidationError: ValidationError? {
        didSet {
            guard textFieldValidationError != oldValue else { return }

            updateValidationUI()
        }
    }

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        // We want to remove the validation error as soon as possible
        // but we don't want to risk adding a validation error prematurely.
        guard textFieldValidationError != nil else { return }
        _ = validateDeviceName()
    }

    func updateValidationUI() {
        guard let textFieldValidationError = textFieldValidationError else {
            validationErrorLabel.isHidden = true
            textFieldStrokeError.isHidden = true
            textFieldStrokeNormal.isHidden = false
            return
        }

        validationErrorLabel.isHidden = false
        textFieldStrokeError.isHidden = false
        textFieldStrokeNormal.isHidden = true

        switch textFieldValidationError {
        case .empty:
            validationErrorLabel.text = NSLocalizedString("VALIDATION_ERROR_CANNOT_BE_BLANK", comment: "error label near a field")
        case .tooLong:
            validationErrorLabel.text = NSLocalizedString("VALIDATION_ERROR_TOO_LONG", comment: "error label near a field")
        }
    }

    enum ValidationError {
        case empty, tooLong
    }

    func validateDeviceName() -> String? {
        guard let deviceName = textField.text?.filterStringForDisplay(), !deviceName.isEmpty else {
            textFieldValidationError = .empty
            return nil
        }

        let characterLimit = 50
        guard deviceName.count <= characterLimit else {
            textFieldValidationError = .tooLong
            return nil
        }

        textFieldValidationError = nil
        return deviceName
    }

    @objc
    func didTapFinalizeLinking() {
        guard let deviceName = validateDeviceName() else {
            return
        }

        provisioningController.didSetDeviceName(String(deviceName), from: self)
    }

}
