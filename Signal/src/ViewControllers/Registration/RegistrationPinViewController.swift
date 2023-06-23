//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalUI
import SignalMessaging

public enum RegistrationPinCharacterSet {
    case digitsOnly
    case alphanumeric
}

/// A blob provided when confirming the PIN, which should be passed
/// back in to the confirm step controller.
/// Fields should not be inspected outside of this class.
public struct RegistrationPinConfirmationBlob: Equatable {
    fileprivate let characterSet: RegistrationPinCharacterSet
    fileprivate let pinToConfirm: String

    #if TESTABLE_BUILD
    public static func stub() -> Self {
        return RegistrationPinConfirmationBlob(characterSet: .digitsOnly, pinToConfirm: "1234")
    }
    #endif
}

public enum RegistrationPinValidationError: Equatable {
    case wrongPin(wrongPin: String)
}

// MARK: - RegistrationPinState

public struct RegistrationPinState: Equatable {
    public enum Skippability: Equatable {
        /// The user cannot skip PIN entry due to reglock.
        case unskippable
        /// The user can skip PIN entry for now but may require the PIN
        /// later for registration lock and thus may not be able to create a new one.
        case canSkip
        /// The user can skip PIN entry and will be able to create a new PIN.
        case canSkipAndCreateNew

        public var canSkip: Bool {
            switch self {
            case .unskippable: return false
            case .canSkip, .canSkipAndCreateNew: return true
            }
        }
    }

    public enum RegistrationPinOperation: Equatable {
        case creatingNewPin
        case confirmingNewPin(RegistrationPinConfirmationBlob)
        case enteringExistingPin(
            skippability: Skippability,
            /// The number of PIN attempts that the user has. If `nil`, the count is unknown.
            remainingAttempts: UInt?
        )
    }

    let operation: RegistrationPinOperation
    let error: RegistrationPinValidationError?
    let contactSupportMode: ContactSupportRegistrationPINMode

    public enum ExitConfiguration: Equatable {
        case noExitAllowed
        case exitReRegistration
        case exitChangeNumber
    }

    let exitConfiguration: ExitConfiguration
}

// MARK: - RegistrationPinPresenter

protocol RegistrationPinPresenter: AnyObject {
    func cancelPinConfirmation()

    /// Should ask for the pin confirmation next with the provided blob.
    func askUserToConfirmPin(_ blob: RegistrationPinConfirmationBlob)

    func submitPinCode(_ code: String)
    func submitWithSkippedPin()

    func exitRegistration()
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

        self.pinCharacterSet = {
            switch state.operation {
            case .creatingNewPin, .enteringExistingPin:
                return .digitsOnly
            case .confirmingNewPin(let blob):
                return blob.characterSet
            }
        }()

        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: Internal state

    public private(set) var state: RegistrationPinState {
        didSet { render() }
    }

    private weak var presenter: RegistrationPinPresenter?

    private var pinCharacterSet: RegistrationPinCharacterSet {
        didSet { render() }
    }

    private var pin: String { pinTextField.text ?? "" }

    private var canSubmit: Bool { pin.count >= kMin2FAv2PinLength }

    private var previouslyWarnedAboutAttemptCount: UInt?

    public func updateState(_ state: RegistrationPinState) {
        self.state = state
    }

    // MARK: Rendering

    private lazy var moreButton: ContextMenuButton = {
        let result = ContextMenuButton()
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

    private lazy var stackView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.distribution = .fill
        result.spacing = 12
        result.setCustomSpacing(24, after: explanationView)
        result.layoutMargins = .init(top: 0, leading: 0, bottom: 16, trailing: 0)
        result.isLayoutMarginsRelativeArrangement = true
        return result
    }()

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
        result.attributedText = NSAttributedString.composed(
            of: {
                switch state.operation {
                case .creatingNewPin:
                    return [
                        OWSLocalizedString(
                            "REGISTRATION_PIN_CREATE_SUBTITLE",
                            comment: "During registration, users are asked to create a PIN code. This is the subtitle on the screen where this happens. A \"learn more\" link will be added to the end of this string."
                        ),
                        CommonStrings.learnMore.styled(
                            with: StringStyle.Part.link(learnMoreAboutPinsURL)
                        )
                    ]
                case .confirmingNewPin:
                    return [OWSLocalizedString(
                        "REGISTRATION_PIN_CONFIRM_SUBTITLE",
                        comment: "During registration, users are asked to create a PIN code. They'll be taken to a screen to confirm their PIN, much like confirming a password. This is the title on the screen where this happens."
                    )]
                case .enteringExistingPin:
                    return [OWSLocalizedString(
                        "REGISTRATION_PIN_ENTER_EXISTING_SUBTITLE",
                        comment: "During re-registration, users may be asked to re-enter their PIN code. This is the subtitle on the screen where this happens. A \"learn more\" link will be added to the end of this string."
                    )]
                }
            }(),
            separator: " "
        )
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
        result.font = .dynamicTypeCaption1Clamped
        return result
    }()

    private lazy var needHelpWithExistingPinButton: OWSFlatButton = {
        let result = Self.flatButton()
        result.setTitle(title: OWSLocalizedString(
            "ONBOARDING_2FA_FORGOT_PIN_LINK",
            comment: "Label for the 'forgot 2FA PIN' link in the 'onboarding 2FA' view."
        ))
        result.addTarget(target: self, selector: #selector(showExistingPinEntryHelpUi))
        result.accessibilityIdentifier = "registration.pin.needHelpButton"
        return result
    }()

    private lazy var togglePinCharacterSetButton: OWSFlatButton = {
        let result = Self.flatButton()
        result.addTarget(target: self, selector: #selector(togglePinCharacterSet))
        result.accessibilityIdentifier = "registration.pin.togglePinCharacterSetButton"
        return result
    }()

    private static func flatButton() -> OWSFlatButton {
        let result = OWSFlatButton()
        result.setTitle(font: .dynamicTypeSubheadlineClamped)
        result.setBackgroundColors(upColor: .clear)
        result.enableMultilineLabel()
        result.button.clipsToBounds = true
        result.button.layer.cornerRadius = 8
        result.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 8)
        return result
    }

    private func exitAction() -> ContextMenuAction? {
        let exitTitle: String
        switch state.exitConfiguration {
        case .noExitAllowed:
            return nil
        case .exitReRegistration:
            exitTitle = OWSLocalizedString(
                "EXIT_REREGISTRATION",
                comment: "Button to exit re-registration, shown in context menu."
            )
        case .exitChangeNumber:
            exitTitle = OWSLocalizedString(
                "EXIT_CHANGE_NUMBER",
                comment: "Button to exit change number, shown in context menu."
            )
        }
        return .init(
            title: exitTitle,
            handler: { [weak self] _ in
                self?.presenter?.exitRegistration()
            }
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        initialRender()
    }

    private var isViewAppeared = false

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !UIDevice.current.isIPhone5OrShorter {
            // Small devices may obscure parts of the UI behind the keyboard, especially with larger
            // font sizes.
            pinTextField.becomeFirstResponder()
        }

        isViewAppeared = true

        render()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if moreButton.isShowingContextMenu {
            moreButton.dismissContextMenu(animated: animated)
        }

        isViewAppeared = false
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        navigationItem.setHidesBackButton(true, animated: false)

        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.autoPinWidthToSuperviewMargins()
        scrollView.autoPinEdge(.top, to: .top, of: keyboardLayoutGuideViewSafeArea)
        scrollView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor).isActive = true

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(explanationView)
        stackView.addArrangedSubview(pinTextField)

        render()
    }

    private func render() {
        switch state.operation {
        case .creatingNewPin:
            renderForCreatingNewPin()
        case .confirmingNewPin:
            renderForConfirmingNewPin()
        case let .enteringExistingPin(skippability, remainingAttempts):
            renderForEnteringExistingPin(skippability: skippability, remainingAttempts: remainingAttempts)
        }

        navigationItem.rightBarButtonItem = canSubmit ? nextBarButton : nil

        let previousKeyboardType = pinTextField.keyboardType
        switch pinCharacterSet {
        case .digitsOnly:
            pinTextField.keyboardType = .numberPad
        case .alphanumeric:
            pinTextField.keyboardType = .default
        }
        if previousKeyboardType != pinTextField.keyboardType {
            pinTextField.reloadInputViews()
        }

        view.backgroundColor = Theme.backgroundColor
        moreButton.setImage(Theme.iconImage(.buttonMore), for: .normal)
        moreButton.tintColor = Theme.accentBlueColor
        backButton.setTemplateImage(
            UIImage(imageLiteralResourceName: "NavBarBack"),
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
        togglePinCharacterSetButton.setTitleColor(Theme.accentBlueColor)
    }

    private func renderForCreatingNewPin() {
        navigationItem.leftBarButtonItem = moreBarButton
        moreButton.contextMenu = ContextMenu([
            .init(
                title: OWSLocalizedString(
                    "PIN_CREATION_LEARN_MORE",
                    comment: "Learn more action on the pin creation view"
                ),
                handler: { [weak self] _ in
                    self?.showCreatingNewPinLearnMoreUi()
                }
            ),
            .init(
                title: OWSLocalizedString(
                    "PIN_CREATION_SKIP",
                    comment: "Skip action on the pin creation view"
                ),
                handler: { [weak self] _ in
                    self?.showSkipCreatingNewPinUi()
                }
            ),
            exitAction()
        ].compacted())

        switch pinCharacterSet {
        case .digitsOnly:
            pinValidationLabel.text = OWSLocalizedString(
                "PIN_CREATION_NUMERIC_HINT",
                comment: "Label indicating the user must use at least 4 digits"
            )
            togglePinCharacterSetButton.setTitle(title: OWSLocalizedString(
                "PIN_CREATION_CREATE_ALPHANUMERIC",
                comment: "Button asking if the user would like to create an alphanumeric PIN"
            ))
        case .alphanumeric:
            pinValidationLabel.text = OWSLocalizedString(
                "PIN_CREATION_ALPHANUMERIC_HINT",
                comment: "Label indicating the user must use at least 4 characters"
            )
            togglePinCharacterSetButton.setTitle(title: OWSLocalizedString(
                "PIN_CREATION_CREATE_NUMERIC",
                comment: "Button asking if the user would like to create an numeric PIN"
            ))
        }
        pinValidationLabel.textColor = .colorForRegistrationExplanationLabel

        replaceViewsAfterTextField(with: [
            pinValidationLabel,
            UIView.vStretchingSpacer(),
            togglePinCharacterSetButton
        ])
    }

    private func renderForConfirmingNewPin() {
        navigationItem.leftBarButtonItem = backBarButton

        replaceViewsAfterTextField(with: [UIView.vStretchingSpacer()])
    }

    private func renderForEnteringExistingPin(
        skippability: RegistrationPinState.Skippability,
        remainingAttempts: UInt?
    ) {
        if skippability.canSkip {
            navigationItem.leftBarButtonItem = moreBarButton
            moreButton.contextMenu = ContextMenu([
                .init(
                    title: OWSLocalizedString(
                        "PIN_ENTER_EXISTING_SKIP",
                        comment: "If the user is re-registering, they need to enter their PIN to restore all their data. In some cases, they can skip this entry and lose some data. This text is shown on a button that lets them begin to do this."
                    ),
                    handler: { [weak self] _ in
                        self?.didRequestToSkipEnteringExistingPin()
                    }
                ),
                exitAction()
            ].compacted())
        } else {
            navigationItem.leftBarButtonItem = nil
        }

        showAttemptWarningIfNecessary(
            remainingAttempts: remainingAttempts,
            warnAt: skippability.canSkip ? [3, 1] : [5, 3, 1],
            canSkip: skippability.canSkip
        )

        var newViewsAtTheBottom: [UIView] = []

        switch state.error {
        case nil:
            break
        case .wrongPin:
            switch remainingAttempts {
            case 1:
                pinValidationLabel.text = OWSLocalizedString(
                    "ONBOARDING_2FA_INVALID_PIN_LAST_ATTEMPT",
                    comment: "Label indicating that the 2fa pin is invalid in the 'onboarding 2fa' view, and you only have one more attempt"
                )
            default:
                pinValidationLabel.text = OWSLocalizedString(
                    "ONBOARDING_2FA_INVALID_PIN",
                    comment: "Label indicating that the 2fa pin is invalid in the 'onboarding 2fa' view."
                )
            }
            newViewsAtTheBottom.append(pinValidationLabel)
        }
        pinValidationLabel.textColor = .ows_accentRed

        needHelpWithExistingPinButton.setTitleColor(Theme.accentBlueColor)

        switch pinCharacterSet {
        case .digitsOnly:
            togglePinCharacterSetButton.setTitle(title: OWSLocalizedString(
                "ONBOARDING_2FA_ENTER_ALPHANUMERIC",
                comment: "Button asking if the user would like to enter an alphanumeric PIN"
            ))
        case .alphanumeric:
            togglePinCharacterSetButton.setTitle(title: OWSLocalizedString(
                "ONBOARDING_2FA_ENTER_NUMERIC",
                comment: "Button asking if the user would like to enter an numeric PIN"
            ))
        }

        replaceViewsAfterTextField(with: [
            pinValidationLabel,
            needHelpWithExistingPinButton,
            UIView.vStretchingSpacer(),
            togglePinCharacterSetButton
        ])
    }

    private func showAttemptWarningIfNecessary(
        remainingAttempts: UInt?,
        warnAt: Set<UInt>,
        canSkip: Bool
    ) {
        guard
            isViewAppeared,
            let remainingAttempts,
            warnAt.contains(remainingAttempts),
            remainingAttempts < (previouslyWarnedAboutAttemptCount ?? UInt.max)
        else { return }

        defer {
            previouslyWarnedAboutAttemptCount = remainingAttempts
        }

        let title: String?
        if state.error == nil {
            // It's unlikely, but we could hit this case if we return to this screen without
            // recently guessing a PIN. We don't want to show an "incorrect PIN" title because you
            // didn't just enter one, but we do still want to tell the user that they don't have
            // many guesses left.
            title = nil
        } else {
            title = OWSLocalizedString(
                "REGISTER_2FA_INVALID_PIN_ALERT_TITLE",
                comment: "Alert title explaining what happens if you forget your 'two-factor auth pin'."
            )
        }

        let message: NSAttributedString = {
            let attemptRemainingFormat = OWSLocalizedString(
                "REREGISTER_INVALID_PIN_ATTEMPT_COUNT_%d",
                tableName: "PluralAware",
                comment: "If the user is re-registering, they may need to enter their PIN to restore all their data. If they enter the incorrect PIN, they may be warned that they only have a certain number of attempts remaining. That warning will tell the user how many attempts they have in bold text. This is that bold text, which is inserted into the larger string."
            )
            let attemptRemainingString = String.localizedStringWithFormat(
                attemptRemainingFormat,
                remainingAttempts
            )

            let format: String
            if canSkip {
                format = OWSLocalizedString(
                    "REREGISTER_INVALID_PIN_WARNING_SKIPPABLE_FORMAT",
                    comment: "If the user is re-registering, they may need to enter their PIN to restore all their data. If they enter the incorrect PIN, they will be shown a warning. In some cases (such as for this string), the user has the option to skip PIN entry and will lose some data. Embeds {{ number of attempts }}, such as \"3 attempts\"."
                )
            } else {
                format = OWSLocalizedString(
                    "REREGISTER_INVALID_PIN_WARNING_UNSKIPPABLE_FORMAT",
                    comment: "If the user is re-registering, they may need to enter their PIN to restore all their data. If they enter the incorrect PIN, they will be shown a warning. Embeds {{ number of attempts }}, such as \"3 attempts\"."
                )
            }

            return NSAttributedString.make(
                fromFormat: format,
                attributedFormatArgs: [.string(
                    attemptRemainingString,
                    attributes: [.font: ActionSheetController.messageLabelFont.semibold()]
                )],
                defaultAttributes: [.font: ActionSheetController.messageLabelFont]
            )
        }()

        OWSActionSheets.showActionSheet(title: title, message: message)
    }

    private func replaceViewsAfterTextField(with views: [UIView]) {
        stackView.removeArrangedSubviewsAfter(pinTextField)
        stackView.addArrangedSubviews(views)
    }

    // MARK: Sheets

    private func showCreatingNewPinLearnMoreUi() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "PIN_CREATION_LEARN_MORE_TITLE",
                comment: "Users can create PINs to restore their account data later. They can learn more about this on a sheet. This is the title on that sheet."
            ),
            message: OWSLocalizedString(
                "PIN_CREATION_LEARN_MORE_TEXT",
                comment: "Users can create PINs to restore their account data later. They can learn more about this on a sheet. This is the text on that sheet."
            )
        )

        actionSheet.addAction(.init(title: CommonStrings.learnMore) { [weak self] _ in
            guard let self else { return }
            self.present(SFSafariViewController(url: self.learnMoreAboutPinsURL), animated: true)
        })

        actionSheet.addAction(.init(title: CommonStrings.okayButton))

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    @objc
    private func showExistingPinEntryHelpUi() {
        let message: String
        let skipButtonTitle: String?
        switch state.operation {
        case .creatingNewPin, .confirmingNewPin:
            owsFail("Invalid state. This method should not be called")
        case let .enteringExistingPin(skippability, _):
            switch skippability {
            case .unskippable:
                message = OWSLocalizedString(
                    "REGISTER_2FA_FORGOT_SVR_PIN_ALERT_MESSAGE",
                    comment: "Alert body for a forgotten SVR (V2) PIN"
                )
                skipButtonTitle = nil
            case .canSkip:
                message = OWSLocalizedString(
                    "REGISTER_2FA_FORGOT_SVR_PIN_WITHOUT_REGLOCK_ALERT_MESSAGE",
                    comment: "Alert body for a forgotten SVR (V2) PIN when the user doesn't have reglock and they cannot necessarily create a new PIN"
                )
                skipButtonTitle = OWSLocalizedString(
                    "PIN_ENTER_EXISTING_SKIP",
                    comment: "If the user is re-registering, they need to enter their PIN to restore all their data. In some cases, they can skip this entry and lose some data. This text is shown on a button that lets them begin to do this."
                )
            case .canSkipAndCreateNew:
                message = OWSLocalizedString(
                    "REGISTER_2FA_FORGOT_SVR_PIN_WITHOUT_REGLOCK_AND_CAN_CREATE_NEW_PIN_ALERT_MESSAGE",
                    comment: "Alert body for a forgotten SVR (V2) PIN when the user doesn't have reglock and they can create a new PIN"
                )
                skipButtonTitle = OWSLocalizedString(
                    "ONBOARDING_2FA_SKIP_AND_CREATE_NEW_PIN",
                    comment: "Label for the 'skip and create new pin' button when reglock is disabled during onboarding."
                )
            }
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "REGISTER_2FA_FORGOT_PIN_ALERT_TITLE",
                comment: "Alert title explaining what happens if you forget your 'two-factor auth pin'."
            ),
            message: message
        )

        if let skipButtonTitle {
            actionSheet.addAction(.init(title: skipButtonTitle, style: .destructive) { [weak self] _ in
                self?.presenter?.submitWithSkippedPin()
            })
        }

        actionSheet.addAction(.init(title: CommonStrings.contactSupport) { [weak self] _ in
            guard let self else { return }
            ContactSupportAlert.showForRegistrationPINMode(self.state.contactSupportMode, from: self)
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    private func showSkipCreatingNewPinUi() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_TITLE",
                comment: "Title of the 'pin disable' action sheet."
            ),
            message: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_MESSAGE",
                comment: "Message of the 'pin disable' action sheet."
            )
        )

        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_ACTION",
                comment: "Action of the 'pin disable' action sheet."
            ),
            style: .destructive
        ) { [weak self] _ in
            self?.presenter?.submitWithSkippedPin()
        })

        actionSheet.addAction(.init(title: CommonStrings.cancelButton, style: .cancel))

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
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

    private func didRequestToSkipEnteringExistingPin() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "ONBOARDING_2FA_SKIP_PIN_ENTRY_TITLE",
                comment: "Title for the skip pin entry action sheet during onboarding."
            ),
            message: NSAttributedString.composed(
                of: [
                    OWSLocalizedString(
                        "ONBOARDING_2FA_SKIP_PIN_ENTRY_MESSAGE",
                        comment: "Explanation for the skip pin entry action sheet during onboarding."
                    ),
                    CommonStrings.learnMore.styled(with: .link(learnMoreAboutPinsURL))
                ],
                baseStyle: ActionSheetController.messageBaseStyle,
                separator: " "
            )
        )

        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "ONBOARDING_2FA_SKIP_AND_CREATE_NEW_PIN",
                comment: "Label for the 'skip and create new pin' button when reglock is disabled during onboarding."
            ),
            style: .destructive
        ) { [weak self] _ in
            self?.presenter?.submitWithSkippedPin()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    private func submit() {
        Logger.info("")

        switch state.operation {
        case .creatingNewPin:
            if OWS2FAManager.isWeakPin(pin) {
                showWeakPinErrorUi()
            } else {
                presenter?.askUserToConfirmPin(RegistrationPinConfirmationBlob(
                    characterSet: pinCharacterSet,
                    pinToConfirm: pin
                ))
            }
        case let .confirmingNewPin(blob):
            if pin == blob.pinToConfirm {
                presenter?.submitPinCode(blob.pinToConfirm)
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
            switch state.operation {
            case .creatingNewPin:
                showCreatingNewPinLearnMoreUi()
            case .confirmingNewPin, .enteringExistingPin:
                owsFailBeta("There shouldn't be links during these operations")
            }
        }
        return false
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
            TextFieldFormatting.ows2FAPINTextField(
                textField,
                changeCharactersIn: range,
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
