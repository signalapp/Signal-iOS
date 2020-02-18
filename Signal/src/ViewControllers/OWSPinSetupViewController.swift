//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import Lottie

@objc(OWSPinSetupViewController)
public class PinSetupViewController: OWSViewController {

    private let pinTextField = UITextField()
    private let pinTypeToggle = UIButton()
    private let nextButton = OWSFlatButton()

    private lazy var pinStrokeNormal = pinTextField.addBottomStroke()
    private lazy var pinStrokeError = pinTextField.addBottomStroke(color: .ows_accentRed, strokeWidth: 2)
    private let validationWarningLabel = UILabel()
    private let recommendationLabel = UILabel()

    enum Mode {
        case creating
        case recreating
        case changing
        case confirming(pinToMatch: String)

        var isChanging: Bool {
            guard case .changing = self else { return false }
            return true
        }

        var isConfirming: Bool {
            guard case .confirming = self else { return false }
            return true
        }
    }
    private let mode: Mode

    private let initialMode: Mode

    enum ValidationState {
        case valid
        case tooShort
        case mismatch

        var isInvalid: Bool {
            return self != .valid
        }
    }
    private var validationState: ValidationState = .valid {
        didSet {
            updateValidationWarnings()
        }
    }

    private var pinType: KeyBackupService.PinType {
        didSet {
            updatePinType()
        }
    }

    // Called once pin setup has finished. Error will be nil upon success
    private let completionHandler: (PinSetupViewController, Error?) -> Void

    init(mode: Mode, initialMode: Mode? = nil, pinType: KeyBackupService.PinType = .numeric, completionHandler: @escaping (PinSetupViewController, Error?) -> Void) {
        assert(TSAccountManager.sharedInstance().isRegisteredPrimaryDevice)
        self.mode = mode
        self.initialMode = initialMode ?? mode
        self.pinType = pinType
        self.completionHandler = completionHandler
        super.init(nibName: nil, bundle: nil)

        if case .confirming = self.initialMode {
            owsFailDebug("pin setup flow should never start in the confirming state")
        }
    }

    @objc
    class func creating(completionHandler: @escaping (PinSetupViewController, Error?) -> Void) -> PinSetupViewController {
        return .init(mode: .creating, completionHandler: completionHandler)
    }

    @objc
    class func changing(completionHandler: @escaping (PinSetupViewController, Error?) -> Void) -> PinSetupViewController {
        return .init(mode: .changing, completionHandler: completionHandler)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Hide the nav bar when not changing.
        navigationController?.setNavigationBarHidden(!initialMode.isChanging, animated: false)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // TODO: Maybe do this in will appear, to avoid the keyboard sliding in when the view is pushed?
        pinTextField.becomeFirstResponder()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDarkThemeEnabled ? .lightContent : .default
    }

    override public func loadView() {
        view = UIView()

        if navigationController == nil {
            owsFailDebug("This view should always be presented in a nav controller")
        }

        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero

        let topRow: UIView?
        let titleLabel: UILabel?

        // We have a nav bar and use the nav bar back button + title
        if initialMode.isChanging {
            topRow = nil
            titleLabel = nil

            title = NSLocalizedString("PIN_CREATION_CHANGING_TITLE", comment: "Title of the 'pin creation' recreation view.")

        // We have no nav bar and build our own back button + title label
        } else {
            // Back button

            let topButton = UIButton()
            let topButtonImage = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "NavBarBackRTL") : #imageLiteral(resourceName: "NavBarBack")

            topButton.setTemplateImage(topButtonImage, tintColor: Theme.secondaryTextAndIconColor)
            topButton.autoSetDimensions(to: CGSize(width: 40, height: 40))
            topButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)

            // Title

            let label = UILabel()
            label.textColor = Theme.primaryTextColor
            label.font = .systemFont(ofSize: 26, weight: .semibold)
            label.textAlignment = .center

            titleLabel = label

            let arrangedSubviews: [UIView]

            // If we're in creating mode AND we're the rootViewController, don't allow going back
            if case .creating = mode, navigationController?.viewControllers.first == self {
                arrangedSubviews = [label]
            } else {
                arrangedSubviews = [topButton, label, UIView.spacer(withWidth: 40)]
            }

            let row = UIStackView(arrangedSubviews: arrangedSubviews)
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0)
            topRow = row
        }

        switch initialMode {
        case .recreating:
            titleLabel?.text = NSLocalizedString("PIN_CREATION_RECREATION_TITLE", comment: "Title of the 'pin creation' recreation view.")
        default:
            titleLabel?.text = NSLocalizedString("PIN_CREATION_TITLE", comment: "Title of the 'pin creation' view.")
        }

        // Explanation

        let explanationLabel = UILabel()
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = .systemFont(ofSize: 15)

        switch mode {
        case .creating, .changing:
            explanationLabel.text = NSLocalizedString("PIN_CREATION_EXPLANATION",
                                                      comment: "The explanation in the 'pin creation' view.")
        case .recreating:
            explanationLabel.text = NSLocalizedString("PIN_CREATION_RECREATION_EXPLANATION",
                                                      comment: "The re-creation explanation in the 'pin creation' view.")
        case .confirming:
            explanationLabel.text = NSLocalizedString("PIN_CREATION_CONFIRMATION_EXPLANATION",
                                                      comment: "The explanation of confirmation in the 'pin creation' view.")
        }

        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.accessibilityIdentifier = "pinCreation.explanationLabel"

        // Pin text field

        pinTextField.delegate = self
        pinTextField.textAlignment = .center
        pinTextField.textColor = Theme.primaryTextColor
        pinTextField.font = .systemFont(ofSize: 17)
        pinTextField.isSecureTextEntry = true
        pinTextField.defaultTextAttributes.updateValue(5, forKey: .kern)
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinTextField.setContentHuggingHorizontalLow()
        pinTextField.setCompressionResistanceHorizontalLow()
        pinTextField.autoSetDimension(.height, toSize: 40)
        pinTextField.accessibilityIdentifier = "pinCreation.pinTextField"

        validationWarningLabel.textColor = .ows_accentRed
        validationWarningLabel.textAlignment = .center
        validationWarningLabel.font = .systemFont(ofSize: 12)
        validationWarningLabel.accessibilityIdentifier = "pinCreation.validationWarningLabel"

        recommendationLabel.textColor = Theme.secondaryTextAndIconColor
        recommendationLabel.textAlignment = .center
        recommendationLabel.font = .systemFont(ofSize: 12)
        recommendationLabel.accessibilityIdentifier = "pinCreation.recommendationLabel"

        let pinStack = UIStackView(arrangedSubviews: [
            pinTextField,
            UIView.spacer(withHeight: 10),
            validationWarningLabel,
            recommendationLabel
        ])
        pinStack.axis = .vertical
        pinStack.alignment = .fill

        let pinStackRow = UIView()
        pinStackRow.addSubview(pinStack)
        pinStack.autoHCenterInSuperview()
        pinStack.autoPinHeightToSuperview()
        pinStack.autoSetDimension(.width, toSize: 227)
        pinStackRow.setContentHuggingVerticalHigh()
        pinStackRow.setCompressionResistanceVerticalHigh()

        pinTypeToggle.setTitleColor(.ows_signalBlue, for: .normal)
        pinTypeToggle.titleLabel?.font = .systemFont(ofSize: 15)
        pinTypeToggle.addTarget(self, action: #selector(togglePinType), for: .touchUpInside)
        pinTypeToggle.accessibilityIdentifier = "pinCreation.pinTypeToggle"
        pinTypeToggle.setCompressionResistanceVerticalHigh()
        pinTypeToggle.setContentHuggingVerticalHigh()

        let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let buttonHeight = OWSFlatButton.heightForFont(font)
        nextButton.setTitle(title: CommonStrings.nextButton, font: font, titleColor: .white)
        nextButton.setBackgroundColors(upColor: .ows_signalBlue)
        nextButton.addTarget(target: self, selector: #selector(nextPressed))
        nextButton.autoSetDimension(.height, toSize: buttonHeight)
        nextButton.accessibilityIdentifier = "pinCreation.nextButton"
        nextButton.useDefaultCornerRadius()
        let primaryButtonView = OnboardingBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        var arrangedSubviews = [
            explanationLabel,
            topSpacer,
            pinStackRow,
            bottomSpacer,
            UIView.spacer(withHeight: 10),
            pinTypeToggle,
            UIView.spacer(withHeight: 10),
            primaryButtonView
        ]

        if let topRow = topRow {
            arrangedSubviews.insert(topRow, at: 0)
        }

        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)

        // Ensure whitespace is balanced, so inputs are vertically centered.
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        updateValidationWarnings()
        updatePinType()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Don't allow interactive dismissal.
        if #available(iOS 13, *) {
            isModalInPresentation = true
        }
    }

    // MARK: - Events

    @objc func navigateBack() {
        Logger.info("")

        if case .recreating = mode {
            dismiss(animated: true, completion: nil)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc func nextPressed() {
        Logger.info("")

        tryToContinue()
    }

    private func tryToContinue() {
        Logger.info("")

        guard let pin = pinTextField.text?.ows_stripped(), pin.count >= kMin2FAv2PinLength else {
            validationState = .tooShort
            return
        }

        if case .confirming(let pinToMatch) = mode, pinToMatch != pin {
            validationState = .mismatch
            return
        }

        switch mode {
        case .creating, .changing, .recreating:
            let confirmingVC = PinSetupViewController(
                mode: .confirming(pinToMatch: pin),
                initialMode: initialMode,
                pinType: pinType,
                completionHandler: completionHandler
            )
            navigationController?.pushViewController(confirmingVC, animated: true)
        case .confirming:
            enable2FAAndContinue(withPin: pin)
        }
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        pinStrokeNormal.isHidden = validationState.isInvalid
        pinStrokeError.isHidden = !validationState.isInvalid
        validationWarningLabel.isHidden = !validationState.isInvalid
        recommendationLabel.isHidden = validationState.isInvalid

        switch validationState {
        case .tooShort:
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_TOO_SHORT_ERROR",
                                                            comment: "Label indicating that the attempted PIN is too short")
        case .mismatch:
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_MISMATCH_ERROR",
                                                            comment: "Label indicating that the attempted PIN does not match the first PIN")
        default:
            break
        }
    }

    private func updatePinType() {
        AssertIsOnMainThread()

        pinTextField.text = nil
        validationState = .valid

        let recommendationLabelText: String

        switch pinType {
        case .numeric:
            pinTypeToggle.setTitle(NSLocalizedString("PIN_CREATION_CREATE_ALPHANUMERIC",
                                                     comment: "Button asking if the user would like to create an alphanumeric PIN"), for: .normal)
            pinTextField.keyboardType = .asciiCapableNumberPad
            recommendationLabelText = NSLocalizedString("PIN_CREATION_NUMERIC_HINT",
                                                         comment: "Label indicating the user must use at least 6 digits")
        case .alphanumeric:
            pinTypeToggle.setTitle(NSLocalizedString("PIN_CREATION_CREATE_NUMERIC",
                                                     comment: "Button asking if the user would like to create an numeric PIN"), for: .normal)
            pinTextField.keyboardType = .default
            recommendationLabelText = NSLocalizedString("PIN_CREATION_ALPHANUMERIC_HINT",
                                                         comment: "Label indicating the user must use at least 6 characters")
        }

        pinTextField.reloadInputViews()

        if mode.isConfirming {
            pinTypeToggle.isHidden = true
            recommendationLabel.text = NSLocalizedString("PIN_CREATION_PIN_CONFIRMATION_HINT",
                                                         comment: "Label indication the user must confirm their PIN.")
        } else {
            pinTypeToggle.isHidden = false
            recommendationLabel.text = recommendationLabelText
        }
    }

    @objc func togglePinType() {
        switch pinType {
        case .numeric:
            pinType = .alphanumeric
        case .alphanumeric:
            pinType = .numeric
        }
    }

    private func enable2FAAndContinue(withPin pin: String) {
        Logger.debug("")

        pinTextField.resignFirstResponder()

        let progressView = ProgressView(
            loadingText: NSLocalizedString("PIN_CREATION_PIN_PROGRESS",
                                           comment: "Indicates the work we are doing while creating the user's pin")
        )
        view.addSubview(progressView)
        progressView.autoPinWidthToSuperview()
        progressView.autoVCenterInSuperview()

        progressView.startLoading {
            self.view.isUserInteractionEnabled = false
            self.nextButton.alpha = 0.5
        }

        OWS2FAManager.shared().requestEnable2FA(withPin: pin, mode: .V2, success: {
            AssertIsOnMainThread()

            // The completion handler always dismisses this view, so we don't want to animate anything.
            progressView.loadingComplete(success: true, animated: false) { [weak self] in
                guard let self = self else { return }
                self.completionHandler(self, nil)
            }

            // Clear the experience upgrade if it was pending.
            SDSDatabaseStorage.shared.asyncWrite { transaction in
                ExperienceUpgradeManager.clearExperienceUpgrade(.introducingPins, transaction: transaction.unwrapGrdbWrite)
            }
        }, failure: { error in
            AssertIsOnMainThread()

            Logger.error("Failed to enable 2FA with error: \(error)")

            // The client may have fallen out of sync with the service.
            // Try to get back to a known good state by disabling 2FA
            // whenever enabling it fails.
            OWS2FAManager.shared().disable2FA(success: nil, failure: nil)

            progressView.loadingComplete(success: false, animateAlongside: {
                self.nextButton.alpha = 1
            }) {
                self.view.isUserInteractionEnabled = true
                progressView.removeFromSuperview()

                // If this is the first time the user is trying to create a PIN, it's a blocking flow.
                // If for some reason they hit an error, notify them that we'll try again later and
                // dismiss the flow so they aren't stuck.
                if case .creating = self.initialMode {
                    OWSActionSheets.showActionSheet(
                        title: NSLocalizedString("PIN_CREATION_ERROR_TITLE",
                                                 comment: "Error title indicating that the attempt to create a PIN failed."),
                        message: NSLocalizedString("PIN_CREATION_ERROR_MESSAGE",
                                                   comment: "Error body indicating that the attempt to create a PIN failed.")
                    ) { _ in
                        self.completionHandler(self, error)
                    }
                } else {
                    OWSActionSheets.showErrorAlert(
                        message: NSLocalizedString("ENABLE_2FA_VIEW_COULD_NOT_ENABLE_2FA",
                                                   comment: "Error indicating that attempt to enable 'two-factor auth' failed.")
                    )
                }
            }
        })
    }
}

// MARK: -

extension PinSetupViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let hasPendingChanges: Bool
        if pinType == .numeric {
            ViewControllerUtils.ows2FAPINTextField(textField, shouldChangeCharactersIn: range, replacementString: string)
            hasPendingChanges = false
        } else {
            hasPendingChanges = true
        }

        // Reset the validation state to clear errors, since the user is trying again
        validationState = .valid

        // Inform our caller whether we took care of performing the change.
        return hasPendingChanges
    }
}

private class ProgressView: UIView {
    private let label = UILabel()
    private let progressAnimation = AnimationView(name: "pinCreationInProgress")
    private let errorAnimation = AnimationView(name: "pinCreationFail")
    private let successAnimation = AnimationView(name: "pinCreationSuccess")

    required init(loadingText: String) {
        super.init(frame: .zero)

        backgroundColor = Theme.backgroundColor

        let animationContainer = UIView()
        addSubview(animationContainer)
        animationContainer.autoPinWidthToSuperview()
        animationContainer.autoPinEdge(toSuperviewEdge: .top)

        progressAnimation.backgroundBehavior = .pauseAndRestore
        progressAnimation.loopMode = .playOnce
        progressAnimation.contentMode = .scaleAspectFit
        animationContainer.addSubview(progressAnimation)
        progressAnimation.autoPinEdgesToSuperviewEdges()

        errorAnimation.isHidden = true
        errorAnimation.backgroundBehavior = .pauseAndRestore
        errorAnimation.loopMode = .playOnce
        errorAnimation.contentMode = .scaleAspectFit
        animationContainer.addSubview(errorAnimation)
        errorAnimation.autoPinEdgesToSuperviewEdges()

        successAnimation.isHidden = true
        successAnimation.backgroundBehavior = .pauseAndRestore
        successAnimation.loopMode = .playOnce
        successAnimation.contentMode = .scaleAspectFit
        animationContainer.addSubview(successAnimation)
        successAnimation.autoPinEdgesToSuperviewEdges()

        label.font = .systemFont(ofSize: 17)
        label.textColor = Theme.primaryTextColor
        label.textAlignment = .center
        label.text = loadingText

        addSubview(label)
        label.autoPinWidthToSuperview(withMargin: 8)
        label.autoPinEdge(.top, to: .bottom, of: animationContainer, withOffset: 12)
        label.autoPinBottomToSuperviewMargin()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func reset() {
        progressAnimation.isHidden = false
        progressAnimation.stop()
        successAnimation.isHidden = true
        successAnimation.stop()
        errorAnimation.isHidden = true
        errorAnimation.stop()
        completedSuccessfully = nil
        completionHandler = nil
        alpha = 0
    }

    func startLoading(animateAlongside: @escaping () -> Void) {
        reset()

        progressAnimation.play { [weak self] _ in self?.startNextLoopOrFinish() }

        UIView.animate(withDuration: 0.15) {
            self.alpha = 1
            animateAlongside()
        }
    }

    func loadingComplete(success: Bool, animated: Bool = true, animateAlongside: (() -> Void)? = nil, completion: @escaping () -> Void) {
        // Marking loading complete does not immediately stop the loading indicator,
        // instead it sets this flag which waits until the animation is at the point
        // it can transition to the next state.
        completedSuccessfully = success
        completionHandler = { [weak self] in
            guard animated else {
                self?.reset()
                return completion()
            }

            UIView.animate(withDuration: 0.15, animations: {
                self?.alpha = 0
                animateAlongside?()
            }) { _ in
                self?.reset()
                completion()
            }
        }
    }

    private var completedSuccessfully: Bool?
    private var completionHandler: (() -> Void)?

    private func startNextLoopOrFinish() {
        // If we haven't yet completed, start another loop of the progress animation.
        // We'll check again when it's done.
        guard let completedSuccessfully = completedSuccessfully else {
            return progressAnimation.play { [weak self] _ in self?.startNextLoopOrFinish() }
        }

        progressAnimation.stop()
        progressAnimation.isHidden = true

        if completedSuccessfully {
            successAnimation.isHidden = false
            successAnimation.play { [weak self] _ in self?.completionHandler?() }
        } else {
            errorAnimation.isHidden = false
            errorAnimation.play { [weak self] _ in self?.completionHandler?() }
        }
    }
}
