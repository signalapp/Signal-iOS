//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalUI
import SignalMessaging

enum RegistrationPinCharacterSet {
    case digitsOnly
    case alphanumeric
}

// MARK: - RegistrationPinState

struct RegistrationPinState {
    enum RegistrationPinOperation {
        case creatingNewPin
        case confirmingNewPin(
            pinCharacterSet: RegistrationPinCharacterSet,
            pinToConfirm: String
        )
        case enteringExistingPin(canSkip: Bool)
    }

    let operation: RegistrationPinOperation
}

// MARK: - RegistrationPinPresenter

protocol RegistrationPinPresenter: AnyObject {
    func cancelPinConfirmation()

    func askUserToConfirmPin(
        pinCharacterSet: RegistrationPinCharacterSet,
        pinToConfirm: String
    )

    func submitPinCode(_ code: String)
    func submitWithSkippedPin()
}

// MARK: - RegistrationPinViewController

class RegistrationPinViewController: OWSViewController {
    private var learnMoreAboutPinsURL: URL { URL(string: "https://support.signal.org/hc/articles/360007059792")! }

    public init(
        state: RegistrationPinState,
        presenter: RegistrationPinPresenter
    ) {
        self.state = state
        self.presenter = presenter

        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: Internal state

    private let state: RegistrationPinState

    private weak var presenter: RegistrationPinPresenter?

    private var pinCharacterSet = RegistrationPinCharacterSet.digitsOnly {
        didSet { render() }
    }

    private var pin: String { pinTextField.text ?? "" }

    private var canSubmit: Bool { pin.count >= kMin2FAv2PinLength }

    // MARK: Rendering

    private lazy var moreButton: UIButton = {
        let result = ContextMenuButton(contextMenu: .init([
            .init(
                title: OWSLocalizedString(
                    "PIN_CREATION_LEARN_MORE",
                    comment: "Learn more action on the pin creation view"
                ),
                handler: { [weak self] _ in
                    self?.showLearnMoreUi()
                }
            ),
            .init(
                title: OWSLocalizedString(
                    "PIN_CREATION_SKIP",
                    comment: "Skip action on the pin creation view"
                ),
                handler: { _ in
                    // TODO[Registration] Let users disable PINs
                }
            )
        ]))
        result.showsContextMenuAsPrimaryAction = true
        result.autoSetDimensions(to: .square(40))
        return result
    }()

    private lazy var moreBarButton = UIBarButtonItem(
        customView: moreButton,
        accessibilityIdentifier: "registration.pin.disablePinButton"
    )

    private lazy var backButton: UIButton = {
        let result = UIButton()
        result.autoSetDimensions(to: CGSize(square: 40))
        result.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        return result
    }()

    private lazy var backBarButton = UIBarButtonItem(
        customView: backButton,
        accessibilityIdentifier: "registration.pin.backButton"
    )

    private lazy var nextBarButton = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapNext),
        accessibilityIdentifier: "registration.pin.nextButton"
    )

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: {
            switch state.operation {
            case .creatingNewPin:
                return OWSLocalizedString(
                    "REGISTRATION_PIN_CREATE_TITLE",
                    comment: "During registration, users are asked to create a PIN code. This is the title on the screen where this happens."
                )
            case .confirmingNewPin:
                return OWSLocalizedString(
                    "REGISTRATION_PIN_CONFIRM_TITLE",
                    comment: "During registration, users are asked to create a PIN code. They'll be taken to a screen to confirm their PIN, much like confirming a password. This is the title on the screen where this happens."
                )
            case .enteringExistingPin:
                return OWSLocalizedString(
                    "REGISTRATION_PIN_ENTER_EXISTING_TITLE",
                    comment: "During re-registration, users may be asked to re-enter their PIN code. This is the title on the screen where this happens."
                )
            }
        }())
        result.accessibilityIdentifier = "registration.pin.titleLabel"
        return result
    }()

    private lazy var explanationView: LinkingTextView = {
        let result = LinkingTextView()
        result.attributedText = .composed(of: [
            {
                switch state.operation {
                case .creatingNewPin:
                    return OWSLocalizedString(
                        "REGISTRATION_PIN_CREATE_SUBTITLE",
                        comment: "During registration, users are asked to create a PIN code. This is the subtitle on the screen where this happens. A \"learn more\" link will be added to the end of this string."
                    )
                case .confirmingNewPin:
                    return OWSLocalizedString(
                        "REGISTRATION_PIN_CONFIRM_SUBTITLE",
                        comment: "During registration, users are asked to create a PIN code. They'll be taken to a screen to confirm their PIN, much like confirming a password. This is the title on the screen where this happens."
                    )
                case .enteringExistingPin:
                    return OWSLocalizedString(
                        "REGISTRATION_PIN_ENTER_EXISTING_SUBTITLE",
                        comment: "During re-registration, users may be asked to re-enter their PIN code. This is the subtitle on the screen where this happens. A \"learn more\" link will be added to the end of this string."
                    )
                }
            }(),
            " ",
            CommonStrings.learnMore.styled(with: StringStyle.Part.link(learnMoreAboutPinsURL))
        ])
        result.font = .fontForRegistrationExplanationLabel
        result.textAlignment = .center
        result.delegate = self
        result.accessibilityIdentifier = "registration.pin.explanationLabel"
        return result
    }()

    private lazy var pinTextField: UITextField = {
        let result = UITextField()

        let font = UIFont.systemFont(ofSize: 22)
        result.font = font
        result.autoSetDimension(.height, toSize: font.lineHeight + 2 * 8.0)
        result.textAlignment = .center

        result.layer.cornerRadius = 10

        result.textContentType = .password
        result.isSecureTextEntry = true
        result.defaultTextAttributes.updateValue(5, forKey: .kern)
        result.accessibilityIdentifier = "registration.pin.pinTextField"

        result.delegate = self

        return result
    }()

    private lazy var pinValidationLabel: UILabel = {
        let result = UILabel()
        result.textAlignment = .center
        result.font = .ows_dynamicTypeCaption1Clamped
        return result
    }()

    private lazy var togglePinCharacterSetButton: OWSFlatButton = {
        let result = OWSFlatButton()
        result.setTitle(font: .ows_dynamicTypeSubheadlineClamped)
        result.setBackgroundColors(upColor: .clear)

        result.enableMultilineLabel()
        result.button.clipsToBounds = true
        result.button.layer.cornerRadius = 8
        result.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 8)

        result.addTarget(target: self, selector: #selector(togglePinCharacterSet))
        result.accessibilityIdentifier = "registration.pin.togglePinCharacterSetButton"
        return result
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()
        initialRender()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !UIDevice.current.isIPhone5OrShorter {
            // Small devices may obscure parts of the UI behind the keyboard, especially with larger
            // font sizes.
            pinTextField.becomeFirstResponder()
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.autoPinWidthToSuperviewMargins()
        scrollView.autoPinEdge(toSuperviewEdge: .top)
        scrollView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 12
        stackView.setCustomSpacing(24, after: explanationView)
        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.autoPinHeightToSuperview()

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(explanationView)
        stackView.addArrangedSubview(pinTextField)

        switch state.operation {
        case .creatingNewPin:
            stackView.addArrangedSubview(pinValidationLabel)
            stackView.addArrangedSubview(UIView.vStretchingSpacer())
            stackView.addArrangedSubview(togglePinCharacterSetButton)
        case .confirmingNewPin:
            stackView.setCustomSpacing(24, after: explanationView)
            stackView.addArrangedSubview(UIView.vStretchingSpacer())
        case .enteringExistingPin:
            stackView.addArrangedSubview(UIView.vStretchingSpacer())
            stackView.addArrangedSubview(togglePinCharacterSetButton)
        }

        render()
    }

    private func render() {
        switch state.operation {
        case .creatingNewPin:
            navigationItem.setHidesBackButton(true, animated: false)
            navigationItem.leftBarButtonItem = moreBarButton
        case .confirmingNewPin:
            navigationItem.setHidesBackButton(false, animated: false)
            navigationItem.leftBarButtonItem = backBarButton
        case .enteringExistingPin:
            navigationItem.setHidesBackButton(true, animated: false)
            navigationItem.leftBarButtonItem = nil
        }

        navigationItem.rightBarButtonItem = canSubmit ? nextBarButton : nil

        switch pinCharacterSet {
        case .digitsOnly:
            pinValidationLabel.text = OWSLocalizedString(
                "PIN_CREATION_NUMERIC_HINT",
                comment: "Label indicating the user must use at least 4 digits"
            )
        case .alphanumeric:
            pinValidationLabel.text = OWSLocalizedString(
                "PIN_CREATION_ALPHANUMERIC_HINT",
                comment: "Label indicating the user must use at least 4 characters"
            )
        }

        let previousKeyboardType = pinTextField.keyboardType
        switch pinCharacterSet {
        case .digitsOnly:
            pinTextField.keyboardType = .numberPad
            togglePinCharacterSetButton.setTitle(title: OWSLocalizedString(
                "PIN_CREATION_CREATE_ALPHANUMERIC",
                comment: "Button asking if the user would like to create an alphanumeric PIN"
            ))
        case .alphanumeric:
            pinTextField.keyboardType = .default
            togglePinCharacterSetButton.setTitle(title: OWSLocalizedString(
                "PIN_CREATION_CREATE_NUMERIC",
                comment: "Button asking if the user would like to create an numeric PIN"
            ))
        }
        if previousKeyboardType != pinTextField.keyboardType {
            pinTextField.reloadInputViews()
        }

        view.backgroundColor = Theme.backgroundColor
        moreButton.setImage(Theme.iconImage(.more24), for: .normal)
        moreButton.tintColor = Theme.accentBlueColor
        backButton.setTemplateImage(
            UIImage(named: CurrentAppContext().isRTL ? "NavBarBackRTL" : "NavBarBack"),
            tintColor: Theme.accentBlueColor
        )
        nextBarButton.tintColor = Theme.accentBlueColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationView.textColor = .colorForRegistrationExplanationLabel
        explanationView.linkTextAttributes = [
            .foregroundColor: Theme.accentBlueColor,
            .underlineColor: UIColor.clear
        ]
        pinTextField.textColor = Theme.primaryTextColor
        pinTextField.backgroundColor = Theme.secondaryBackgroundColor
        pinTextField.keyboardAppearance = Theme.keyboardAppearance
        pinValidationLabel.textColor = .colorForRegistrationExplanationLabel
        togglePinCharacterSetButton.setTitleColor(Theme.accentBlueColor)
    }

    // MARK: Events

    @objc
    private func didTapBack() {
        Logger.info("")

        presenter?.cancelPinConfirmation()
    }

    @objc
    private func didTapNext() {
        Logger.info("")

        guard canSubmit else { return }

        submit()
    }

    @objc
    private func togglePinCharacterSet() {
        Logger.info("")

        switch pinCharacterSet {
        case .digitsOnly: pinCharacterSet = .alphanumeric
        case .alphanumeric: pinCharacterSet = .digitsOnly
        }

        pinTextField.text = ""

        render()
    }

    private func submit() {
        Logger.info("")

        switch state.operation {
        case .creatingNewPin:
            if OWS2FAManager.isWeakPin(pin) {
                showWeakPinErrorUi()
            } else {
                presenter?.askUserToConfirmPin(
                    pinCharacterSet: pinCharacterSet,
                    pinToConfirm: pin
                )
            }
        case let .confirmingNewPin(_, pinToConfirm):
            if pin == pinToConfirm {
                presenter?.submitPinCode(pin)
            } else {
                showMismatchedPinUi()
            }
        case .enteringExistingPin:
            presenter?.submitPinCode(pin)
        }
    }

    private func showWeakPinErrorUi() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "PIN_CREATION_WEAK_ERROR",
                comment: "Label indicating that the attempted PIN is too weak"
            ),
            message: OWSLocalizedString(
                "PIN_CREATION_WEAK_ERROR_MESSAGE",
                comment: "If your attempted PIN is too weak, you'll see an error message. This is the text on the error dialog."
            )
        )

        actionSheet.addAction(.init(title: CommonStrings.okayButton))

        presentActionSheet(actionSheet)
    }

    private func showMismatchedPinUi() {
        let actionSheet = ActionSheetController(
            message: OWSLocalizedString(
                "PIN_CREATION_MISMATCH_ERROR",
                comment: "Label indicating that the attempted PIN does not match the first PIN"
            )
        )

        actionSheet.addAction(.init(title: CommonStrings.okayButton))

        presentActionSheet(actionSheet)
    }
}

// MARK: - UITextViewDelegate

extension RegistrationPinViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if textView == explanationView {
            showLearnMoreUi()
        }
        return false
    }

    private func showLearnMoreUi() {
        present(SFSafariViewController(url: learnMoreAboutPinsURL), animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension RegistrationPinViewController: UITextFieldDelegate {
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString: String
    ) -> Bool {
        let result: Bool
        switch pinCharacterSet {
        case .digitsOnly:
            ViewControllerUtils.ows2FAPINTextField(
                textField,
                shouldChangeCharactersIn: range,
                replacementString: replacementString
            )
            result = false
        case .alphanumeric:
            result = true
        }

        render()

        return result
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        Logger.info("")

        if canSubmit { submit() }

        return false
    }
}
