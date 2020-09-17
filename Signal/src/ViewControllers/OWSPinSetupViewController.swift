//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit
import Lottie
import PromiseKit
import SafariServices

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
        case weak

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

    private let enableRegistrationLock: Bool

    init(
        mode: Mode,
        initialMode: Mode? = nil,
        pinType: KeyBackupService.PinType = .numeric,
        enableRegistrationLock: Bool = OWS2FAManager.shared().isRegistrationLockEnabled,
        completionHandler: @escaping (PinSetupViewController, Error?) -> Void
    ) {
        assert(TSAccountManager.shared().isRegisteredPrimaryDevice)
        self.mode = mode
        self.initialMode = initialMode ?? mode
        self.pinType = pinType
        self.enableRegistrationLock = enableRegistrationLock
        self.completionHandler = completionHandler
        super.init()

        if case .confirming = self.initialMode {
            owsFailDebug("pin setup flow should never start in the confirming state")
        }
    }

    @objc
    class func creatingRegistrationLock(completionHandler: @escaping (PinSetupViewController, Error?) -> Void) -> PinSetupViewController {
        return .init(mode: .creating, enableRegistrationLock: true, completionHandler: completionHandler)
    }

    @objc
    class func creating(completionHandler: @escaping (PinSetupViewController, Error?) -> Void) -> PinSetupViewController {
        return .init(mode: .creating, completionHandler: completionHandler)
    }

    @objc
    class func changing(completionHandler: @escaping (PinSetupViewController, Error?) -> Void) -> PinSetupViewController {
        return .init(mode: .changing, completionHandler: completionHandler)
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

        let confirmationTitle = NSLocalizedString("PIN_CREATION_CONFIRM_TITLE", comment: "Title of the 'pin creation' confirmation view.")

        // We have a nav bar and use the nav bar back button + title
        if initialMode.isChanging {
            topRow = nil
            titleLabel = nil

            title = mode.isConfirming
                ? confirmationTitle
                : NSLocalizedString("PIN_CREATION_CHANGING_TITLE", comment: "Title of the 'pin creation' recreation view.")

        // We have no nav bar and build our own back button + title label
        } else {
            // Back button

            let backButton = UIButton()
            let topButtonImage = CurrentAppContext().isRTL ? #imageLiteral(resourceName: "NavBarBackRTL") : #imageLiteral(resourceName: "NavBarBack")

            backButton.setTemplateImage(topButtonImage, tintColor: Theme.secondaryTextAndIconColor)
            backButton.autoSetDimensions(to: CGSize(square: 40))
            backButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)

            // More button

            let trailingView: UIView
            if mode.isConfirming {
                trailingView = UIView.spacer(withWidth: 40)
            } else {
                let moreButton = UIButton()
                moreButton.setTemplateImageName("more-horiz-24", tintColor: Theme.primaryIconColor)
                moreButton.autoSetDimensions(to: CGSize(square: 40))
                moreButton.addTarget(self, action: #selector(didTapMoreButton), for: .touchUpInside)

                trailingView = moreButton
            }

            // Title

            let label = UILabel()
            label.textColor = Theme.primaryTextColor
            label.font = .systemFont(ofSize: 26, weight: .semibold)
            label.textAlignment = .center

            titleLabel = label

            let arrangedSubviews: [UIView]

            // If we're in creating mode AND we're the rootViewController, don't allow going back
            if case .creating = mode, navigationController?.viewControllers.first == self {
                arrangedSubviews = [UIView.spacer(withWidth: 40), label, trailingView]
            } else {
                arrangedSubviews = [backButton, label, trailingView]
            }

            let row = UIStackView(arrangedSubviews: arrangedSubviews)
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0)
            topRow = row
        }

        if mode.isConfirming {
            titleLabel?.text = confirmationTitle
        } else {
            switch initialMode {
            case .recreating:
                titleLabel?.text = NSLocalizedString("PIN_CREATION_RECREATION_TITLE", comment: "Title of the 'pin creation' recreation view.")
            default:
                titleLabel?.text = NSLocalizedString("PIN_CREATION_TITLE", comment: "Title of the 'pin creation' view.")
            }
        }

        // Explanation

        let explanationLabel = LinkingTextView()
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.font = .systemFont(ofSize: 15)

        let explanationText: String

        switch mode {
        case .creating:
            explanationText = NSLocalizedString("PIN_CREATION_EXPLANATION",
                                                comment: "The explanation in the 'pin creation' view.")
        case .recreating, .changing:
            explanationText = NSLocalizedString("PIN_CREATION_RECREATION_EXPLANATION",
                                                comment: "The re-creation explanation in the 'pin creation' view.")
        case .confirming:
            explanationText = NSLocalizedString("PIN_CREATION_CONFIRMATION_EXPLANATION",
                                                comment: "The explanation of confirmation in the 'pin creation' view.")
        }

        if mode.isConfirming {
            explanationLabel.text = explanationText
        } else {
            let attributedString = NSMutableAttributedString(
                string: explanationText,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15),
                    .foregroundColor: Theme.secondaryTextAndIconColor
                ]
            )
            attributedString.append("  ")
            attributedString.append(CommonStrings.learnMore,
                                    attributes: [
                                        .link: URL(string: "https://support.signal.org/hc/articles/360007059792")!,
                                        .font: UIFont.systemFont(ofSize: 15)
                ]
            )
            explanationLabel.attributedText = attributedString
            explanationLabel.isUserInteractionEnabled = true
        }

        explanationLabel.textAlignment = .center
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

        pinTypeToggle.setTitleColor(Theme.accentBlueColor, for: .normal)
        pinTypeToggle.titleLabel?.font = .systemFont(ofSize: 15)
        pinTypeToggle.addTarget(self, action: #selector(togglePinType), for: .touchUpInside)
        pinTypeToggle.accessibilityIdentifier = "pinCreation.pinTypeToggle"
        pinTypeToggle.setCompressionResistanceVerticalHigh()
        pinTypeToggle.setContentHuggingVerticalHigh()

        let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let buttonHeight = OWSFlatButton.heightForFont(font)
        nextButton.setTitle(title: CommonStrings.nextButton, font: font, titleColor: .white)
        nextButton.setBackgroundColors(upColor: .ows_accentBlue)
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

    @objc
    func didTapMoreButton(_ sender: UIButton) {
        let actionSheet = ActionSheetController()
        actionSheet.addAction(OWSActionSheets.cancelAction)

        let learnMoreAction = ActionSheetAction(
            title: NSLocalizedString(
                "PIN_CREATION_LEARN_MORE",
                comment: "Learn more action on the pin creation view"
            )
        ) { [weak self] _ in
            guard let self = self else { return }
            let vc = SFSafariViewController(url: URL(string: "https://support.signal.org/hc/articles/360007059792")!)
            self.present(vc, animated: true, completion: nil)
        }
        actionSheet.addAction(learnMoreAction)

        let skipAction = ActionSheetAction(
            title: NSLocalizedString(
                "PIN_CREATION_SKIP",
                comment: "Skip action on the pin creation view"
            )
        ) { [weak self] _ in
            guard let self = self else { return }
            Self.disablePinWithConfirmation(fromViewController: self).done { [weak self] pinDisabled in
                guard pinDisabled, let self = self else { return }
                self.completionHandler(self, nil)
            }.catch { [weak self] error in
                guard let self = self else { return }
                OWSActionSheets.showActionSheet(
                    title: NSLocalizedString("PIN_DISABLE_ERROR_TITLE",
                                             comment: "Error title indicating that the attempt to disable a PIN failed."),
                    message: NSLocalizedString("PIN_DISABLE_ERROR_MESSAGE",
                                               comment: "Error body indicating that the attempt to disable a PIN failed.")
                ) { _ in
                    self.completionHandler(self, error)
                }
            }
        }
        actionSheet.addAction(skipAction)

        presentActionSheet(actionSheet)
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

        if isWeakPin(pin) {
            validationState = .weak
            return
        }

        switch mode {
        case .creating, .changing, .recreating:
            let confirmingVC = PinSetupViewController(
                mode: .confirming(pinToMatch: pin),
                initialMode: initialMode,
                pinType: pinType,
                enableRegistrationLock: enableRegistrationLock,
                completionHandler: completionHandler
            )
            navigationController?.pushViewController(confirmingVC, animated: true)
        case .confirming:
            enable2FAAndContinue(withPin: pin)
        }
    }

    private func isWeakPin(_ pin: String) -> Bool {
        let normalizedPin = KeyBackupService.normalizePin(pin)

        // We only check numeric pins for weakness
        guard normalizedPin.digitsOnly() == normalizedPin else { return false }

        var allTheSame = true
        var forwardSequential = true
        var reverseSequential = true

        var previousWholeNumberValue: Int?
        for character in normalizedPin {
            guard let current = character.wholeNumberValue else {
                owsFailDebug("numeric pin unexpectedly contatined non-numeric characters")
                break
            }

            defer { previousWholeNumberValue = current }
            guard let previous = previousWholeNumberValue else { continue }

            if previous != current { allTheSame = false }
            if previous + 1 != current { forwardSequential = false }
            if previous - 1 != current { reverseSequential = false }

            if !allTheSame && !forwardSequential && !reverseSequential { break }
        }

        return allTheSame || forwardSequential || reverseSequential
    }

    private func updateValidationWarnings() {
        AssertIsOnMainThread()

        pinStrokeNormal.isHidden = validationState.isInvalid
        pinStrokeError.isHidden = !validationState.isInvalid
        validationWarningLabel.isHidden = !validationState.isInvalid
        recommendationLabel.isHidden = validationState.isInvalid

        switch validationState {
        case .tooShort:
            switch pinType {
            case .numeric:
                validationWarningLabel.text = NSLocalizedString("PIN_CREATION_NUMERIC_HINT",
                                                                comment: "Label indicating the user must use at least 4 digits")
            case .alphanumeric:
                validationWarningLabel.text = NSLocalizedString("PIN_CREATION_ALPHANUMERIC_HINT",
                                                                comment: "Label indicating the user must use at least 4 characters")
            }
        case .mismatch:
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_MISMATCH_ERROR",
                                                            comment: "Label indicating that the attempted PIN does not match the first PIN")
        case .weak:
            validationWarningLabel.text = NSLocalizedString("PIN_CREATION_WEAK_ERROR",
                                                            comment: "Label indicating that the attempted PIN is too weak")
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
                                                         comment: "Label indicating the user must use at least 4 digits")
        case .alphanumeric:
            pinTypeToggle.setTitle(NSLocalizedString("PIN_CREATION_CREATE_NUMERIC",
                                                     comment: "Button asking if the user would like to create an numeric PIN"), for: .normal)
            pinTextField.keyboardType = .default
            recommendationLabelText = NSLocalizedString("PIN_CREATION_ALPHANUMERIC_HINT",
                                                         comment: "Label indicating the user must use at least 4 characters")
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

        let progressView = PinProgressView(
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

        OWS2FAManager.shared().requestEnable2FA(withPin: pin, mode: .V2).then { () -> Promise<Void> in
            if self.enableRegistrationLock {
                return OWS2FAManager.shared().enableRegistrationLockV2()
            } else {
                return Promise.value(())
            }
        }.done {
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
        }.catch { error in
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
        }
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

extension PinSetupViewController {
    public class func disablePinWithConfirmation(fromViewController: UIViewController) -> Promise<Bool> {
        guard !OWS2FAManager.shared().isRegistrationLockV2Enabled else {
            return showRegistrationLockConfirmation(fromViewController: fromViewController)
        }

        let (promise, resolver) = Promise<Bool>.pending()

        let actionSheet = ActionSheetController(
            title: NSLocalizedString("PIN_CREATION_DISABLE_CONFIRMATION_TITLE",
                                     comment: "Title of the 'pin disable' action sheet."),
            message: NSLocalizedString("PIN_CREATION_DISABLE_CONFIRMATION_MESSAGE",
                                       comment: "Message of the 'pin disable' action sheet.")
        )

        let cancelAction = ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            resolver.fulfill(false)
        }
        actionSheet.addAction(cancelAction)

        let disableAction = ActionSheetAction(
            title: NSLocalizedString("PIN_CREATION_DISABLE_CONFIRMATION_ACTION",
                                     comment: "Action of the 'pin disable' action sheet."),
            style: .destructive
        ) { _ in
            ModalActivityIndicatorViewController.present(
                fromViewController: fromViewController,
                canCancel: false
            ) { modal in
                SDSDatabaseStorage.shared.asyncWrite { transaction in
                    KeyBackupService.useDeviceLocalMasterKey(transaction: transaction)

                    transaction.addAsyncCompletion {
                        modal.dismiss { resolver.fulfill(true) }
                    }
                }
            }
        }
        actionSheet.addAction(disableAction)

        fromViewController.presentActionSheet(actionSheet)

        return promise
    }

    private class func showRegistrationLockConfirmation(fromViewController: UIViewController) -> Promise<Bool> {
        let (promise, resolver) = Promise<Bool>.pending()

        let actionSheet = ActionSheetController(
            title: NSLocalizedString("PIN_CREATION_REGLOCK_CONFIRMATION_TITLE",
                                     comment: "Title of the 'pin disable' reglock action sheet."),
            message: NSLocalizedString("PIN_CREATION_REGLOCK_CONFIRMATION_MESSAGE",
                                       comment: "Message of the 'pin disable' reglock action sheet.")
        )

        let cancelAction = ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            resolver.fulfill(false)
        }
        actionSheet.addAction(cancelAction)

        let disableAction = ActionSheetAction(
            title: NSLocalizedString("PIN_CREATION_REGLOCK_CONFIRMATION_ACTION",
                                     comment: "Action of the 'pin disable' reglock action sheet."),
            style: .destructive
        ) { _ in
            ModalActivityIndicatorViewController.present(
                fromViewController: fromViewController,
                canCancel: false
            ) { modal in
                OWS2FAManager.shared().disableRegistrationLockV2().then {
                    Promise { resolver in
                        modal.dismiss { resolver.fulfill(()) }
                    }
                }.then { () -> Promise<Bool> in
                    disablePinWithConfirmation(fromViewController: fromViewController)
                }.done { success in
                    resolver.fulfill(success)
                }.catch { error in
                    modal.dismiss { resolver.reject(error) }
                }
            }
        }
        actionSheet.addAction(disableAction)

        fromViewController.presentActionSheet(actionSheet)

        return promise
    }
}

class PinProgressView: UIView {
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

        guard animated else {
            reset()
            return completion()
        }

        completionHandler = { [weak self] in
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

        guard !progressAnimation.isHidden else { return }

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
