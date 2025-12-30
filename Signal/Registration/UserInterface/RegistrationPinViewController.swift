//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalServiceKit
import SignalUI

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
    case serverError
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
            remainingAttempts: UInt?,
        )
    }

    let operation: RegistrationPinOperation
    let error: RegistrationPinValidationError?
    let contactSupportMode: ContactSupportActionSheet.EmailFilter.RegistrationPINMode

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
    func submitWithCreateNewPinInstead()

    func exitRegistration()

    func enterRecoveryKey()
}

// MARK: - RegistrationPinViewController

class RegistrationPinViewController: OWSViewController {
    init(
        state: RegistrationPinState,
        presenter: RegistrationPinPresenter,
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

        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    // MARK: Internal state

    private(set) var state: RegistrationPinState {
        didSet { configureUI() }
    }

    private weak var presenter: RegistrationPinPresenter?

    private var pinCharacterSet: RegistrationPinCharacterSet {
        didSet { configureUI() }
    }

    private var pin: String { pinTextField.text ?? "" }

    private var canSubmit: Bool { pin.count >= kMin2FAv2PinLength }

    private var previouslyWarnedAboutAttemptCount: UInt?

    func updateState(_ state: RegistrationPinState) {
        self.state = state
    }

    // MARK: Rendering

    private lazy var moreButton: ContextMenuButton = {
        let result = ContextMenuButton(empty: ())
        result.setImage(Theme.iconImage(.buttonMore), for: .normal)
        if #unavailable(iOS 26) {
            result.tintColor = .Signal.accent
        }
        result.autoSetDimensions(to: .square(40))
        return result
    }()

    private lazy var moreBarButton = UIBarButtonItem(
        customView: moreButton,
        accessibilityIdentifier: "registration.pin.disablePinButton",
    )

    private lazy var backButton: UIButton = {
        let result = UIButton()
        result.setTemplateImage(
            UIImage(imageLiteralResourceName: "NavBarBack"),
            tintColor: Theme.accentBlueColor,
        )
        result.autoSetDimensions(to: CGSize(square: 40))
        result.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        return result
    }()

    private lazy var backBarButton = UIBarButtonItem(
        customView: backButton,
        accessibilityIdentifier: "registration.pin.backButton",
    )

    private var stackView: UIStackView!

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: {
            switch state.operation {
            case .creatingNewPin:
                return OWSLocalizedString(
                    "REGISTRATION_PIN_CREATE_TITLE",
                    comment: "During registration, users are asked to create a PIN code. This is the title on the screen where this happens.",
                )
            case .confirmingNewPin:
                return OWSLocalizedString(
                    "REGISTRATION_PIN_CONFIRM_TITLE",
                    comment: "During registration, users are asked to create a PIN code. They'll be taken to a screen to confirm their PIN, much like confirming a password. This is the title on the screen where this happens.",
                )
            case .enteringExistingPin:
                return OWSLocalizedString(
                    "REGISTRATION_PIN_ENTER_EXISTING_TITLE",
                    comment: "During re-registration, users may be asked to re-enter their PIN code. This is the title on the screen where this happens.",
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
                            comment: "During registration, users are asked to create a PIN code. This is the subtitle on the screen where this happens. A \"learn more\" link will be added to the end of this string.",
                        ),
                        CommonStrings.learnMore.styled(
                            with: StringStyle.Part.link(URL.Support.pin),
                        ),
                    ]
                case .confirmingNewPin:
                    return [OWSLocalizedString(
                        "REGISTRATION_PIN_CONFIRM_SUBTITLE",
                        comment: "During registration, users are asked to create a PIN code. They'll be taken to a screen to confirm their PIN, much like confirming a password. This is the title on the screen where this happens.",
                    )]
                case .enteringExistingPin:
                    return [OWSLocalizedString(
                        "REGISTRATION_PIN_ENTER_EXISTING_SUBTITLE",
                        comment: "During re-registration, users may be asked to re-enter their PIN code. This is the subtitle on the screen where this happens. A \"learn more\" link will be added to the end of this string.",
                    )]
                }
            }(),
            separator: " ",
        )
        result.font = .dynamicTypeBody
        result.textColor = .Signal.secondaryLabel
        result.textAlignment = .center
        result.delegate = self
        result.accessibilityIdentifier = "registration.pin.explanationLabel"
        return result
    }()

    private lazy var pinTextField: UITextField = {
        let result = UITextField()

        let font = UIFont.systemFont(ofSize: 22)
        result.font = font
        result.autoSetDimension(.height, toSize: (font.lineHeight + 2 * 12.0).rounded())
        result.textAlignment = .center
        result.textColor = .Signal.label
        result.tintColor = .Signal.label // caret color
        result.textContentType = .password
        result.isSecureTextEntry = true
        result.backgroundColor = .Signal.secondaryBackground
        result.defaultTextAttributes.updateValue(5, forKey: .kern)
        result.accessibilityIdentifier = "registration.pin.pinTextField"
        result.delegate = self
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            result.cornerConfiguration = .capsule()
        } else {
            result.layer.cornerRadius = 10
        }
#else
        result.layer.cornerRadius = 10
#endif

        return result
    }()

    private lazy var pinValidationLabel: UILabel = {
        let result = UILabel()
        result.textAlignment = .center
        result.font = .dynamicTypeSubheadlineClamped
        return result
    }()

    private lazy var needHelpWithExistingPinButton: UIButton = {
        let button = UIButton(
            configuration: .mediumBorderless(title: OWSLocalizedString(
                "ONBOARDING_2FA_FORGOT_PIN_LINK",
                comment: "Label for the 'forgot 2FA PIN' link in the 'onboarding 2FA' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.showExistingPinEntryHelpUI()
            },
        )
        button.enableMultilineLabel()
        button.accessibilityIdentifier = "registration.pin.needHelpButton"
        return button
    }()

    private lazy var togglePinCharacterSetButton: UIButton = {
        let button = UIButton(
            configuration: .mediumBorderless(title: OWSLocalizedString(
                "ONBOARDING_2FA_FORGOT_PIN_LINK",
                comment: "Label for the 'forgot 2FA PIN' link in the 'onboarding 2FA' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.togglePinCharacterSet()
            },
        )
        button.enableMultilineLabel()
        button.accessibilityIdentifier = "registration.pin.togglePinCharacterSetButton"
        return button
    }()

    private lazy var togglePinCharacterSetButtonContainer = togglePinCharacterSetButton.enclosedInVerticalStackView(isFullWidthButton: false)

    private func exitAction() -> UIAction? {
        let exitTitle: String
        switch state.exitConfiguration {
        case .noExitAllowed:
            return nil
        case .exitReRegistration:
            exitTitle = OWSLocalizedString(
                "EXIT_REREGISTRATION",
                comment: "Button to exit re-registration, shown in context menu.",
            )
        case .exitChangeNumber:
            exitTitle = OWSLocalizedString(
                "EXIT_CHANGE_NUMBER",
                comment: "Button to exit change number, shown in context menu.",
            )
        }
        return UIAction(
            title: exitTitle,
            handler: { [weak self] _ in
                self?.presenter?.exitRegistration()
            },
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background
        navigationItem.rightBarButtonItem = {
            let barButtonItem = UIBarButtonItem(
                title: CommonStrings.nextButton,
                style: .done,
                target: self,
                action: #selector(didTapNext),
                accessibilityIdentifier: "registration.pin.nextButton",
            )
            barButtonItem.tintColor = .Signal.accent
            return barButtonItem
        }()

        self.stackView = addStaticContentStackView(
            arrangedSubviews: [titleLabel, explanationView, pinTextField],
            isScrollable: true,
            shouldAvoidKeyboard: true,
        )
        stackView.setCustomSpacing(24, after: explanationView)

        pinTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        configureUI()
    }

    private var isViewAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !UIDevice.current.isIPhone5OrShorter {
            // Small devices may obscure parts of the UI behind the keyboard, especially with larger
            // font sizes.
            pinTextField.becomeFirstResponder()
        }

        isViewAppeared = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        isViewAppeared = false
    }

    private func configureUI() {
        switch state.operation {
        case .creatingNewPin:
            configureUIForCreatingNewPin()
        case .confirmingNewPin:
            configureUIForConfirmingNewPin()
        case let .enteringExistingPin(skippability, remainingAttempts):
            configureUIForEnteringExistingPin(skippability: skippability, remainingAttempts: remainingAttempts)
        }

        navigationItem.rightBarButtonItem?.isEnabled = canSubmit

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
    }

    private func configureUIForCreatingNewPin() {
        navigationItem.leftBarButtonItem = moreBarButton

        moreButton.setActions(actions: [
            UIAction(
                title: OWSLocalizedString(
                    "PIN_CREATION_LEARN_MORE",
                    comment: "Learn more action on the pin creation view",
                ),
                handler: { [weak self] _ in
                    self?.showCreatingNewPinLearnMoreUI()
                },
            ),
            UIAction(
                title: OWSLocalizedString(
                    "PIN_CREATION_SKIP",
                    comment: "Skip action on the pin creation view",
                ),
                handler: { [weak self] _ in
                    self?.showSkipCreatingNewPinUI()
                },
            ),
            exitAction(),
        ].compacted())

        switch pinCharacterSet {
        case .digitsOnly:
            pinValidationLabel.text = OWSLocalizedString(
                "PIN_CREATION_NUMERIC_HINT",
                comment: "Label indicating the user must use at least 4 digits",
            )
            togglePinCharacterSetButton.configuration?.title = OWSLocalizedString(
                "PIN_CREATION_CREATE_ALPHANUMERIC",
                comment: "Button asking if the user would like to create an alphanumeric PIN",
            )
        case .alphanumeric:
            pinValidationLabel.text = OWSLocalizedString(
                "PIN_CREATION_ALPHANUMERIC_HINT",
                comment: "Label indicating the user must use at least 4 characters",
            )
            togglePinCharacterSetButton.configuration?.title = OWSLocalizedString(
                "PIN_CREATION_CREATE_NUMERIC",
                comment: "Button asking if the user would like to create an numeric PIN",
            )
        }
        pinValidationLabel.textColor = .Signal.secondaryLabel

        replaceViewsAfterTextField(with: [
            pinValidationLabel,
            UIView.vStretchingSpacer(minHeight: 24),
            togglePinCharacterSetButtonContainer,
        ])
    }

    private func configureUIForConfirmingNewPin() {
        navigationItem.leftBarButtonItem = backBarButton

        replaceViewsAfterTextField(with: [UIView.vStretchingSpacer()])
    }

    private func configureUIForEnteringExistingPin(
        skippability: RegistrationPinState.Skippability,
        remainingAttempts: UInt?,
    ) {
        navigationItem.leftBarButtonItem = moreBarButton
        var actions = [UIMenuElement]()

        if skippability.canSkip {
            actions.append(UIAction(
                title: OWSLocalizedString(
                    "PIN_ENTER_EXISTING_SKIP",
                    comment: "If the user is re-registering, they need to enter their PIN to restore all their data. In some cases, they can skip this entry and lose some data. This text is shown on a button that lets them begin to do this.",
                ),
                handler: { [weak self] _ in
                    self?.didRequestToSkipEnteringExistingPin()
                },
            ))
        }

        actions.append(
            UIAction(
                title: OWSLocalizedString(
                    "PIN_ENTER_EXISTING_USE_RECOVERY_KEY",
                    comment: "If the user is re-registering, they need to enter their PIN to restore all their data. If they don't remember their PIN, they may remember their Recovery Key which can be used instead of a PIN.",
                ),
                handler: { [weak self] _ in
                    self?.presenter?.enterRecoveryKey()
                },
            ),
        )

        if let exitAction = exitAction() {
            actions.append(exitAction)
        }

        moreButton.setActions(actions: actions)

        showAttemptWarningIfNecessary(
            remainingAttempts: remainingAttempts,
            warnAt: skippability.canSkip ? [3, 1] : [5, 3, 1],
            canSkip: skippability.canSkip,
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
                    comment: "Label indicating that the 2fa pin is invalid in the 'onboarding 2fa' view, and you only have one more attempt",
                )
            default:
                pinValidationLabel.text = OWSLocalizedString(
                    "ONBOARDING_2FA_INVALID_PIN",
                    comment: "Label indicating that the 2fa pin is invalid in the 'onboarding 2fa' view.",
                )
            }
            newViewsAtTheBottom.append(pinValidationLabel)
        case .serverError:
            pinValidationLabel.text = OWSLocalizedString(
                "SOMETHING_WENT_WRONG_TRY_AGAIN_LATER_ERROR",
                comment: "An error message generically indicating that something went wrong, and that the user should try again later.",
            )
            newViewsAtTheBottom.append(pinValidationLabel)
        }
        pinValidationLabel.textColor = .ows_accentRed

        switch pinCharacterSet {
        case .digitsOnly:
            togglePinCharacterSetButton.configuration?.title = OWSLocalizedString(
                "ONBOARDING_2FA_ENTER_ALPHANUMERIC",
                comment: "Button asking if the user would like to enter an alphanumeric PIN",
            )
        case .alphanumeric:
            togglePinCharacterSetButton.configuration?.title = OWSLocalizedString(
                "ONBOARDING_2FA_ENTER_NUMERIC",
                comment: "Button asking if the user would like to enter an numeric PIN",
            )
        }

        newViewsAtTheBottom.append(contentsOf: [
            needHelpWithExistingPinButton,
            UIView.vStretchingSpacer(),
            togglePinCharacterSetButtonContainer,
        ])
        replaceViewsAfterTextField(with: newViewsAtTheBottom)
    }

    private func showAttemptWarningIfNecessary(
        remainingAttempts: UInt?,
        warnAt: Set<UInt>,
        canSkip: Bool,
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
                comment: "Alert title explaining what happens if you forget your 'two-factor auth pin'.",
            )
        }

        let message: NSAttributedString = {
            let attemptRemainingFormat = OWSLocalizedString(
                "REREGISTER_INVALID_PIN_ATTEMPT_COUNT_%d",
                tableName: "PluralAware",
                comment: "If the user is re-registering, they may need to enter their PIN to restore all their data. If they enter the incorrect PIN, they may be warned that they only have a certain number of attempts remaining. That warning will tell the user how many attempts they have in bold text. This is that bold text, which is inserted into the larger string.",
            )
            let attemptRemainingString = String.localizedStringWithFormat(
                attemptRemainingFormat,
                remainingAttempts,
            )

            let format: String
            if canSkip {
                format = OWSLocalizedString(
                    "REREGISTER_INVALID_PIN_WARNING_SKIPPABLE_FORMAT",
                    comment: "If the user is re-registering, they may need to enter their PIN to restore all their data. If they enter the incorrect PIN, they will be shown a warning. In some cases (such as for this string), the user has the option to skip PIN entry and will lose some data. Embeds {{ number of attempts }}, such as \"3 attempts\".",
                )
            } else {
                format = OWSLocalizedString(
                    "REREGISTER_INVALID_PIN_WARNING_UNSKIPPABLE_FORMAT",
                    comment: "If the user is re-registering, they may need to enter their PIN to restore all their data. If they enter the incorrect PIN, they will be shown a warning. Embeds {{ number of attempts }}, such as \"3 attempts\".",
                )
            }

            return NSAttributedString.make(
                fromFormat: format,
                attributedFormatArgs: [.string(
                    attemptRemainingString,
                    attributes: [.font: ActionSheetController.messageLabelFont.semibold()],
                )],
                defaultAttributes: [.font: ActionSheetController.messageLabelFont],
            )
        }()

        OWSActionSheets.showActionSheet(title: title, message: message)
    }

    private func replaceViewsAfterTextField(with views: [UIView]) {
        stackView.removeArrangedSubviewsAfter(pinTextField)
        stackView.addArrangedSubviews(views)
    }

    // MARK: Sheets

    private func showCreatingNewPinLearnMoreUI() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "PIN_CREATION_LEARN_MORE_TITLE",
                comment: "Users can create PINs to restore their account data later. They can learn more about this on a sheet. This is the title on that sheet.",
            ),
            message: OWSLocalizedString(
                "PIN_CREATION_LEARN_MORE_TEXT",
                comment: "Users can create PINs to restore their account data later. They can learn more about this on a sheet. This is the text on that sheet.",
            ),
        )

        actionSheet.addAction(.init(title: CommonStrings.learnMore) { [weak self] _ in
            guard let self else { return }
            self.present(SFSafariViewController(url: URL.Support.pin), animated: true)
        })

        actionSheet.addAction(.init(title: CommonStrings.okayButton))

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    private func showExistingPinEntryHelpUI() {
        let message: String
        switch state.operation {
        case .creatingNewPin, .confirmingNewPin:
            owsFail("Invalid state. This method should not be called")
        case let .enteringExistingPin(skippability, _):
            switch skippability {
            case .unskippable:
                message = OWSLocalizedString(
                    "REGISTER_2FA_FORGOT_SVR_PIN_ALERT_MESSAGE",
                    comment: "Alert body for a forgotten SVR (V2) PIN",
                )
            case .canSkip:
                message = OWSLocalizedString(
                    "REGISTER_2FA_FORGOT_SVR_PIN_WITHOUT_REGLOCK_ALERT_MESSAGE",
                    comment: "Alert body for a forgotten SVR (V2) PIN when the user doesn't have reglock and they cannot necessarily create a new PIN",
                )
            case .canSkipAndCreateNew:
                message = OWSLocalizedString(
                    "REGISTER_2FA_FORGOT_SVR_PIN_WITHOUT_REGLOCK_AND_CAN_CREATE_NEW_PIN_ALERT_MESSAGE",
                    comment: "Alert body for a forgotten SVR (V2) PIN when the user doesn't have reglock and they can create a new PIN",
                )
            }
        }

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "REGISTER_2FA_FORGOT_PIN_ALERT_TITLE",
                comment: "Alert title explaining what happens if you forget your 'two-factor auth pin'.",
            ),
            message: message,
        )

        switch state.operation {
        case .creatingNewPin, .confirmingNewPin:
            owsFail("Invalid state. This method should not be called")
        case let .enteringExistingPin(skippability, _):
            switch skippability {
            case .unskippable:
                break
            case .canSkip:
                let skipButtonTitle = OWSLocalizedString(
                    "PIN_ENTER_EXISTING_SKIP",
                    comment: "If the user is re-registering, they need to enter their PIN to restore all their data. In some cases, they can skip this entry and lose some data. This text is shown on a button that lets them begin to do this.",
                )
                actionSheet.addAction(.init(title: skipButtonTitle, style: .destructive) { [weak self] _ in
                    self?.presenter?.submitWithSkippedPin()
                })
            case .canSkipAndCreateNew:
                let skipButtonTitle = OWSLocalizedString(
                    "ONBOARDING_2FA_SKIP_AND_CREATE_NEW_PIN",
                    comment: "Label for the 'skip and create new pin' button when reglock is disabled during onboarding.",
                )
                actionSheet.addAction(.init(title: skipButtonTitle, style: .destructive) { [weak self] _ in
                    self?.presenter?.submitWithCreateNewPinInstead()
                })
            }
        }

        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "ONBOARDING_2FA_SKIP_AND_USE_RECOVERY_KEY",
                comment: "Label for action to use Recovery Key instead of PIN for registration.",
            ),
        ) { [weak self] _ in
            self?.presenter?.enterRecoveryKey()
        })

        actionSheet.addAction(.init(title: CommonStrings.contactSupport) { [weak self] _ in
            guard let self else { return }
            ContactSupportActionSheet.present(
                emailFilter: .registrationPINMode(state.contactSupportMode),
                logDumper: .fromGlobals(),
                fromViewController: self,
            )
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    private func showSkipCreatingNewPinUI() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_TITLE",
                comment: "Title of the 'pin disable' action sheet.",
            ),
            message: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_MESSAGE",
                comment: "Message of the 'pin disable' action sheet.",
            ),
        )

        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "PIN_CREATION_DISABLE_CONFIRMATION_ACTION",
                comment: "Action of the 'pin disable' action sheet.",
            ),
            style: .destructive,
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

    private func togglePinCharacterSet() {
        Logger.info("")

        switch pinCharacterSet {
        case .digitsOnly: pinCharacterSet = .alphanumeric
        case .alphanumeric: pinCharacterSet = .digitsOnly
        }

        pinTextField.text = ""

        configureUI()
    }

    private func didRequestToSkipEnteringExistingPin() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "ONBOARDING_2FA_SKIP_PIN_ENTRY_TITLE",
                comment: "Title for the skip pin entry action sheet during onboarding.",
            ),
            message: NSAttributedString.composed(
                of: [
                    OWSLocalizedString(
                        "ONBOARDING_2FA_SKIP_PIN_ENTRY_MESSAGE",
                        comment: "Explanation for the skip pin entry action sheet during onboarding.",
                    ),
                    CommonStrings.learnMore.styled(with: .link(URL.Support.pin)),
                ],
                baseStyle: ActionSheetController.messageBaseStyle,
                separator: " ",
            ),
        )

        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "ONBOARDING_2FA_SKIP_AND_CREATE_NEW_PIN",
                comment: "Label for the 'skip and create new pin' button when reglock is disabled during onboarding.",
            ),
            style: .destructive,
        ) { [weak self] _ in
            self?.presenter?.submitWithCreateNewPinInstead()
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
                    pinToConfirm: pin,
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
                comment: "Label indicating that the attempted PIN is too weak",
            ),
            message: OWSLocalizedString(
                "PIN_CREATION_WEAK_ERROR_MESSAGE",
                comment: "If your attempted PIN is too weak, you'll see an error message. This is the text on the error dialog.",
            ),
        )

        actionSheet.addAction(.init(title: CommonStrings.okayButton))

        presentActionSheet(actionSheet)
    }

    private func showMismatchedPinUi() {
        let actionSheet = ActionSheetController(
            message: OWSLocalizedString(
                "PIN_CREATION_MISMATCH_ERROR",
                comment: "Label indicating that the attempted PIN does not match the first PIN",
            ),
        )

        actionSheet.addAction(.init(title: CommonStrings.okayButton))

        presentActionSheet(actionSheet)
    }

    @objc
    private func textFieldDidChange(_ textField: UITextField) {
        configureUI()
    }
}

// MARK: - UITextViewDelegate

extension RegistrationPinViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction,
    ) -> Bool {
        if textView == explanationView {
            switch state.operation {
            case .creatingNewPin:
                showCreatingNewPinLearnMoreUI()
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
        replacementString: String,
    ) -> Bool {
        let result: Bool
        switch pinCharacterSet {
        case .digitsOnly:
            TextFieldFormatting.ows2FAPINTextField(
                textField,
                changeCharactersIn: range,
                replacementString: replacementString,
            )
            result = false
            configureUI()
        case .alphanumeric:
            // render() will happen in textFieldDidChange, after the textField has
            // updated input. This makes sure buttons appear correctly.
            result = true
        }

        return result
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        Logger.info("")

        if canSubmit { submit() }

        return false
    }
}
