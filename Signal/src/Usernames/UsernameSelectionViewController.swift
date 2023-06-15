//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import SignalMessaging
import SignalUI

protocol UsernameSelectionDelegate: AnyObject {
    func usernameDidChange(to newValue: String?)
}

/// Provides UX allowing a user to select or delete a username for their
/// account.
///
/// Usernames consist of a user-chosen "nickname" and a programmatically-
/// generated numeric "discriminator", which are then concatenated.
class UsernameSelectionViewController: OWSViewController, OWSNavigationChildController {

    /// A wrapper for injected dependencies.
    struct Context {
        let networkManager: NetworkManager
        let databaseStorage: SDSDatabaseStorage
        let usernameLookupManager: UsernameLookupManager
        let schedulers: Schedulers
        let storageServiceManager: StorageServiceManager
    }

    enum Constants {
        /// Minimum length for a nickname, in Unicode code points.
        static let minNicknameCodepointLength: UInt32 = RemoteConfig.minNicknameLength

        /// Maximum length for a nickname, in Unicode code points.
        static let maxNicknameCodepointLength: UInt32 = RemoteConfig.maxNicknameLength

        /// Amount of time to wait after the username text field is edited
        /// before kicking off a reservation attempt.
        static let reservationDebounceTimeInternal: TimeInterval = 0.5

        /// Amount of time to wait after the username text field is edited with
        /// a too-short value before showing the corresponding error.
        static let tooShortDebounceTimeInterval: TimeInterval = 1

        /// Size of the header view's icon.
        static let headerViewIconSize: CGFloat = 64

        /// A well-known URL associated with a "learn more" string in the
        /// explanation footer. Can be any value - we will intercept this
        /// locally rather than actually open it.
        static let learnMoreLink: URL = URL(string: "sgnl://username-selection-learn-more")!
    }

    /// A logger for username-selection-related events.
    private class UsernameLogger: PrefixedLogger {
        static let shared: UsernameLogger = .init()

        private init() {
            super.init(prefix: "[Username Selection]")
        }
    }

    private enum UsernameSelectionState: Equatable {
        /// The user's existing username is unchanged.
        case noChangesToExisting
        /// Username state is pending. Stores an ID, to disambiguate multiple
        /// potentially-overlapping state updates.
        case pending(id: UUID)
        /// The username has been successfully reserved.
        case reservationSuccessful(reservation: API.SuccessfulReservation)
        /// The username was rejected by the server during reservation.
        case reservationRejected
        /// The reservation failed, for an unknown reason.
        case reservationFailed
        /// The username is too short.
        case tooShort
        /// The username is too long.
        case tooLong
        /// The username's first character is a digit.
        case cannotStartWithDigit
        /// The username contains invalid characters.
        case invalidCharacters
    }

    typealias ParsedUsername = Usernames.ParsedUsername
    typealias API = Usernames.API

    // MARK: Private members

    /// Backing value for ``currentUsernameState``. Do not access directly!
    private var _currentUsernameState: UsernameSelectionState = .noChangesToExisting {
        didSet {
            guard oldValue != _currentUsernameState else {
                return
            }

            updateContent()
        }
    }

    /// Represents the current state of username selection. Must only be
    /// accessed on the main thread.
    private var currentUsernameState: UsernameSelectionState {
        get {
            AssertIsOnMainThread()
            return _currentUsernameState
        }
        set {
            AssertIsOnMainThread()
            _currentUsernameState = newValue
        }
    }

    /// A pre-existing username this controller was seeded with.
    private let existingUsername: ParsedUsername?

    /// The local user's ACI.
    private let localAci: ServiceId

    /// Injected dependencies.
    private let context: Context

    private lazy var apiManager: Usernames.API = {
        .init(
            networkManager: context.networkManager,
            schedulers: context.schedulers
        )
    }()

    // MARK: Public members

    weak var usernameSelectionDelegate: UsernameSelectionDelegate?

    // MARK: Init

    init(
        existingUsername: ParsedUsername?,
        localAci: ServiceId,
        context: Context
    ) {
        self.existingUsername = existingUsername
        self.localAci = localAci
        self.context = context

        super.init()
    }

    // MARK: Getters

    /// Whether the user has edited the username to a value other than what we
    /// started with.
    private var hasUnsavedEdits: Bool {
        if case .noChangesToExisting = currentUsernameState {
            return false
        }

        return true
    }

    // MARK: Views

    /// Navbar button for finishing this view.
    private lazy var doneBarButtonItem: UIBarButtonItem = {
        UIBarButtonItem(
            title: CommonStrings.doneButton,
            style: .done,
            target: self,
            action: #selector(didTapDone),
            accessibilityIdentifier: "done_button"
        )
    }()

    private lazy var wrapperScrollView = UIScrollView()

    private lazy var headerView: HeaderView = {
        let view = HeaderView(withIconSize: Constants.headerViewIconSize)

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    /// Manages editing of the nickname and presents additional visual state
    /// such as the current discriminator.
    private lazy var usernameTextFieldWrapper: UsernameTextFieldWrapper = {
        let wrapper = UsernameTextFieldWrapper(username: existingUsername)

        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.textField.delegate = self
        wrapper.textField.addTarget(self, action: #selector(usernameTextFieldContentsDidChange), for: .editingChanged)

        return wrapper
    }()

    private lazy var usernameErrorTextView: UITextView = {
        let textView = LinkingTextView()

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainerInset = UIEdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16)
        textView.textColor = .ows_accentRed

        return textView
    }()

    private lazy var usernameErrorTextViewZeroHeightConstraint: NSLayoutConstraint = {
        return usernameErrorTextView.heightAnchor.constraint(equalToConstant: 0)
    }()

    private lazy var usernameFooterTextView: UITextView = {
        let textView = LinkingTextView()

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainerInset = UIEdgeInsets(top: 12, leading: 16, bottom: 24, trailing: 16)
        textView.delegate = self

        return textView
    }()

    // MARK: View lifecycle

    var navbarBackgroundColorOverride: UIColor? {
        Theme.tableView2BackgroundColor
    }

    override func themeDidChange() {
        super.themeDidChange()

        view.backgroundColor = Theme.tableView2BackgroundColor
        owsNavigationController?.updateNavbarAppearance()

        headerView.setColorsForCurrentTheme()
        usernameTextFieldWrapper.setColorsForCurrentTheme()

        usernameFooterTextView.textColor = Theme.secondaryTextAndIconColor
    }

    override func contentSizeCategoryDidChange() {
        headerView.updateFontsForCurrentPreferredContentSize()
        usernameTextFieldWrapper.updateFontsForCurrentPreferredContentSize()

        usernameErrorTextView.font = .dynamicTypeCaption1Clamped
        usernameFooterTextView.font = .dynamicTypeCaption1Clamped
    }

    /// Only allow gesture-based dismissal when there have been no edits.
    override var isModalInPresentation: Bool {
        get { hasUnsavedEdits }
        set {}
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavBar()
        setupViewConstraints()
        setupErrorText()

        themeDidChange()
        contentSizeCategoryDidChange()
        updateContent()
    }

    private func setupNavBar() {
        title = OWSLocalizedString(
            "USERNAME_SELECTION_TITLE",
            comment: "The title for the username selection view."
        )

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        navigationItem.rightBarButtonItem = doneBarButtonItem
    }

    private func setupViewConstraints() {
        view.addSubview(wrapperScrollView)

        wrapperScrollView.addSubview(headerView)
        wrapperScrollView.addSubview(usernameTextFieldWrapper)
        wrapperScrollView.addSubview(usernameErrorTextView)
        wrapperScrollView.addSubview(usernameFooterTextView)

        wrapperScrollView.autoPinTopToSuperviewMargin()
        wrapperScrollView.autoPinLeadingToSuperviewMargin()
        wrapperScrollView.autoPinTrailingToSuperviewMargin()
        wrapperScrollView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)

        let contentLayoutGuide = wrapperScrollView.contentLayoutGuide

        contentLayoutGuide.widthAnchor.constraint(
            equalTo: wrapperScrollView.widthAnchor
        ).isActive = true

        func constrainHorizontal(_ view: UIView) {
            view.leadingAnchor.constraint(
                equalTo: contentLayoutGuide.leadingAnchor
            ).isActive = true

            view.trailingAnchor.constraint(
                equalTo: contentLayoutGuide.trailingAnchor
            ).isActive = true
        }

        constrainHorizontal(headerView)
        constrainHorizontal(usernameTextFieldWrapper)
        constrainHorizontal(usernameFooterTextView)

        headerView.topAnchor.constraint(
            equalTo: contentLayoutGuide.topAnchor
        ).isActive = true

        headerView.autoPinEdge(.bottom, to: .top, of: usernameTextFieldWrapper)

        usernameTextFieldWrapper.autoPinEdge(.bottom, to: .top, of: usernameErrorTextView)

        usernameErrorTextView.autoPinEdge(.bottom, to: .top, of: usernameFooterTextView)

        usernameFooterTextView.bottomAnchor.constraint(
            equalTo: contentLayoutGuide.bottomAnchor
        ).isActive = true
    }

    private func setupErrorText() {
        usernameErrorTextView.layer.opacity = 0
        usernameErrorTextViewZeroHeightConstraint.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        usernameTextFieldWrapper.textField.becomeFirstResponder()
    }
}

// MARK: - Dynamic contents

private extension UsernameSelectionViewController {

    func updateContent() {
        updateNavigationItems()
        updateHeaderViewContent()
        updateUsernameTextFieldContent()
        updateErrorTextViewContent()
        updateFooterTextViewContent()
    }

    /// Update the contents of navigation items for the current internal
    /// controller state.
    private func updateNavigationItems() {
        doneBarButtonItem.isEnabled = {
            switch currentUsernameState {
            case
                    .reservationSuccessful:
                return true
            case
                    .noChangesToExisting,
                    .pending,
                    .reservationRejected,
                    .reservationFailed,
                    .tooShort,
                    .tooLong,
                    .cannotStartWithDigit,
                    .invalidCharacters:
                return false
            }
        }()
    }

    /// Update the contents of the header view for the current internal
    /// controller state.
    private func updateHeaderViewContent() {
        // If we are able to finalize a username (i.e., have a
        // reservation or deletion primed), we should display it.
        let usernameDisplayText: String? = {
            switch self.currentUsernameState {
            case .noChangesToExisting:
                if let existingUsername = self.existingUsername {
                    return existingUsername.reassembled
                }

                return OWSLocalizedString(
                    "USERNAME_SELECTION_HEADER_TEXT_FOR_PLACEHOLDER",
                    comment: "When the user has entered text into a text field for setting their username, a header displays the username text. This string is shown in the header when the text field is empty."
                )
            case let .reservationSuccessful(reservation):
                return reservation.username.reassembled
            case
                    .pending,
                    .reservationRejected,
                    .reservationFailed,
                    .tooShort,
                    .tooLong,
                    .cannotStartWithDigit,
                    .invalidCharacters:
                return nil
            }
        }()

        if let usernameDisplayText {
            self.headerView.setUsernameText(to: usernameDisplayText)
        }
    }

    /// Update the contents of the username text field for the current internal
    /// controller state.
    private func updateUsernameTextFieldContent() {
        switch self.currentUsernameState {
        case .noChangesToExisting:
            self.usernameTextFieldWrapper.textField.configure(forConfirmedUsername: self.existingUsername)
        case .pending:
            self.usernameTextFieldWrapper.textField.configureForSomethingPending()
        case let .reservationSuccessful(reservation):
            self.usernameTextFieldWrapper.textField.configure(forConfirmedUsername: reservation.username)
        case
                .reservationRejected,
                .reservationFailed,
                .tooShort,
                .tooLong,
                .cannotStartWithDigit,
                .invalidCharacters:
            self.usernameTextFieldWrapper.textField.configureForError()
        }
    }

    /// Update the contents of the error text view for the current internal
    /// controller state.
    private func updateErrorTextViewContent() {
        let errorText: String? = {
            switch currentUsernameState {
            case
                    .noChangesToExisting,
                    .pending,
                    .reservationSuccessful:
                return nil
            case .reservationRejected:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_NOT_AVAILABLE_ERROR_MESSAGE",
                    comment: "An error message shown when the user wants to set their username to an unavailable value."
                )
            case .reservationFailed:
                return CommonStrings.somethingWentWrongTryAgainLaterError
            case .tooShort:
                return String(
                    format: OWSLocalizedString(
                        "USERNAME_SELECTION_TOO_SHORT_ERROR_MESSAGE",
                        comment: "An error message shown when the user has typed a username that is below the minimum character limit. Embeds {{ %1$@ the minimum character count }}."
                    ),
                    OWSFormat.formatUInt32(Constants.minNicknameCodepointLength)
                )
            case .tooLong:
                owsFail("This should be impossible from the UI, as we limit the text field length.")
            case .cannotStartWithDigit:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_CANNOT_START_WITH_DIGIT_ERROR_MESSAGE",
                    comment: "An error message shown when the user has typed a username that starts with a digit, which is invalid."
                )
            case .invalidCharacters:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_INVALID_CHARACTERS_ERROR_MESSAGE",
                    comment: "An error message shown when the user has typed a username that has invalid characters. The character ranges \"a-z\", \"0-9\", \"_\" should not be translated, as they are literal."
                )
            }
        }()

        var animatedLayoutBlock: ((UITextView) -> Void)?

        if let errorText {
            usernameErrorTextView.text = errorText

            if usernameErrorTextViewZeroHeightConstraint.isActive {
                usernameErrorTextViewZeroHeightConstraint.isActive = false
                animatedLayoutBlock = { $0.layer.opacity = 1 }
            }
        } else if !usernameErrorTextViewZeroHeightConstraint.isActive {
            usernameErrorTextViewZeroHeightConstraint.isActive = true
            animatedLayoutBlock = { $0.layer.opacity = 0 }
        }

        if let animatedLayoutBlock {
            let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)

            animator.addAnimations {
                animatedLayoutBlock(self.usernameErrorTextView)
                self.view.layoutIfNeeded()
            }

            animator.startAnimation()
        }
    }

    /// Update the contents of the footer text view for the current internal
    /// controller state.
    private func updateFooterTextViewContent() {
        let content = NSAttributedString.make(
            fromFormat: OWSLocalizedString(
                "USERNAME_SELECTION_EXPLANATION_FOOTER_FORMAT",
                comment: "Footer text below a text field in which users type their desired username, which explains how usernames work. Embeds a {{ \"learn more\" link. }}."
            ),
            attributedFormatArgs: [
                .string(
                    CommonStrings.learnMore,
                    attributes: [.link: Constants.learnMoreLink]
                )
            ]
        ).styled(
            with: .font(.dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor)
        )

        usernameFooterTextView.attributedText = content
    }
}

// MARK: - Nav bar events

private extension UsernameSelectionViewController {
    /// Called when the user cancels editing. Dismisses the view, discarding
    /// unsaved changes.
    @objc
    private func didTapCancel() {
        guard hasUnsavedEdits else {
            dismiss(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true)
        })
    }

    /// Called when the user taps "Done". Attempts to finalize the new chosen
    /// username.
    @objc
    private func didTapDone() {
        let usernameState = self.currentUsernameState

        switch usernameState {
        case let .reservationSuccessful(reservation):
            self.confirmReservationBehindModalActivityIndicator(
                reservedUsername: reservation.hashedUsername
            )
        case
                .noChangesToExisting,
                .pending,
                .reservationRejected,
                .reservationFailed,
                .tooShort,
                .tooLong,
                .cannotStartWithDigit,
                .invalidCharacters:
            owsFail("Unexpected username state: \(usernameState). Should be impossible from the UI!")
        }
    }

    /// Confirm the given reservation, with an activity indicator blocking the
    /// UI.
    private func confirmReservationBehindModalActivityIndicator(
        reservedUsername: Usernames.HashedUsername
    ) {
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false
        ) { modal in
            UsernameLogger.shared.info("Confirming username.")

            firstly { () -> Promise<API.ConfirmationResult> in
                self.apiManager.attemptToConfirm(reservedUsername: reservedUsername)
            }.done(on: self.context.schedulers.main) { result -> Void in
                switch result {
                case let .success(confirmedUsername):
                    UsernameLogger.shared.info("Confirmed username!")

                    self.persistNewUsernameValueAndDismiss(
                        usernameValue: confirmedUsername,
                        presentedModalActivityIndicator: modal
                    )
                case .rejected:
                    UsernameLogger.shared.error("Failed to confirm the username, server rejected.")

                    self.dismiss(
                        modalActivityIndicator: modal,
                        andPresentErrorMessage: CommonStrings.somethingWentWrongError
                    )
                case .rateLimited:
                    UsernameLogger.shared.error("Failed to confirm the username, rate-limited.")

                    self.dismiss(
                        modalActivityIndicator: modal,
                        andPresentErrorMessage: CommonStrings.somethingWentWrongTryAgainLaterError
                    )
                }
            }.catch(on: self.context.schedulers.main) { error in
                UsernameLogger.shared.error("Error while confirming username: \(error)")

                self.dismiss(
                    modalActivityIndicator: modal,
                    andPresentErrorMessage: CommonStrings.somethingWentWrongTryAgainLaterError
                )
            }
        }
    }

    /// Persist the given username value, dismiss the given activity indicator,
    /// then dismiss the current view.
    /// - Parameter usernameValue
    /// A new username value.
    /// - Parameter presentedModalActivityIndicator
    /// A currently-presented modal activity indicator to be dismissed.
    private func persistNewUsernameValueAndDismiss(
        usernameValue: String,
        presentedModalActivityIndicator modal: ModalActivityIndicatorViewController
    ) {
        context.databaseStorage.write { transaction in
            context.usernameLookupManager.saveUsername(
                usernameValue,
                forAci: localAci,
                transaction: transaction.asV2Write
            )
        }

        // We back up the username in StorageService, so trigger a backup now.
        context.storageServiceManager.recordPendingLocalAccountUpdates()

        usernameSelectionDelegate?.usernameDidChange(to: usernameValue)

        modal.dismiss {
            self.dismiss(animated: true)
        }
    }

    /// Dismiss the given activity indicator and then present an error message
    /// action sheet.
    private func dismiss(
        modalActivityIndicator modal: ModalActivityIndicatorViewController,
        andPresentErrorMessage errorMessage: String
    ) {
        modal.dismiss {
            OWSActionSheets.showErrorAlert(message: errorMessage)
        }
    }
}

// MARK: - Text field events

private extension UsernameSelectionViewController {
    /// Called when the contents of the username text field have changed, and
    /// sets local state as appropriate. If the username is believed to be
    /// valid, kicks off a reservation attempt.
    @objc
    private func usernameTextFieldContentsDidChange() {
        AssertIsOnMainThread()

        UsernameLogger.shared.debug("Username text field contents changed...")

        let nicknameFromTextField: String? = usernameTextFieldWrapper.textField.normalizedNickname

        if existingUsername?.nickname == nicknameFromTextField {
            currentUsernameState = .noChangesToExisting
        } else if let desiredNickname = nicknameFromTextField {
            typealias CandidateError = Usernames.HashedUsername.CandidateGenerationError

            do {
                let usernameCandidates = try Usernames.HashedUsername.generateCandidates(
                    forNickname: desiredNickname,
                    minNicknameLength: Constants.minNicknameCodepointLength,
                    maxNicknameLength: Constants.maxNicknameCodepointLength
                )

                attemptReservationAndUpdateValidationState(
                    forUsernameCandidates: usernameCandidates
                )
            } catch CandidateError.nicknameCannotStartWithDigit {
                currentUsernameState = .cannotStartWithDigit
            } catch CandidateError.nicknameContainsInvalidCharacters {
                currentUsernameState = .invalidCharacters
            } catch CandidateError.nicknameTooLong {
                currentUsernameState = .tooLong
            } catch CandidateError.nicknameTooShort {
                // Wait a beat before showing a "too short" error, in case the
                // user is going to enter more text that renders the error
                // irrelevant.

                let debounceId = UUID()
                currentUsernameState = .pending(id: debounceId)

                firstly(on: context.schedulers.sync) { () -> Guarantee<Void> in
                    return Guarantee.after(wallInterval: Constants.tooShortDebounceTimeInterval)
                }.done(on: context.schedulers.main) {
                    if
                        case let .pending(id) = self.currentUsernameState,
                        debounceId == id
                    {
                        self.currentUsernameState = .tooShort
                    }
                }
            } catch CandidateError.nicknameCannotBeEmpty {
                owsFail("We should never get here with an empty username string. Did something upstream break?")
            } catch let error {
                owsFailBeta("Unexpected error while generating candidate usernames! Did something upstream change? \(error)")
                currentUsernameState = .reservationFailed
            }
        } else {
            // We have an existing username, but no entered nickname.
            currentUsernameState = .tooShort
        }
    }

    /// Attempts to reserve the given nickname, and updates ``validationState``
    /// as appropriate.
    ///
    /// The desired nickname might change while prior reservation attempts are
    /// in-flight. In order to disambiguate between reservation attempts, we
    /// track an "attempt ID" that represents the current reservation attempt.
    /// If a reservation completes successfully but the current attempt ID does
    /// not match the ID with which the reservation was initiated, we discard
    /// the result (as we have moved on to another desired nickname).
    private func attemptReservationAndUpdateValidationState(
        forUsernameCandidates usernameCandidates: Usernames.HashedUsername.GeneratedCandidates
    ) {
        AssertIsOnMainThread()

        struct ReservationNotAttemptedError: Error {
            let attemptId: UUID
        }

        firstly { () -> Guarantee<UUID> in
            let attemptId = UUID()

            currentUsernameState = .pending(id: attemptId)

            // Delay to detect multiple rapid consecutive edits.
            return Guarantee
                .after(wallInterval: Constants.reservationDebounceTimeInternal)
                .map(on: self.context.schedulers.main) { attemptId }
        }.then(on: self.context.schedulers.main) { thisAttemptId throws -> Promise<API.ReservationResult> in
            // If this attempt is no longer current after debounce, we should
            // bail out without firing a reservation.
            guard
                case let .pending(id) = self.currentUsernameState,
                thisAttemptId == id
            else {
                throw ReservationNotAttemptedError(attemptId: thisAttemptId)
            }

            UsernameLogger.shared.info("Attempting to reserve username. Attempt ID: \(thisAttemptId)")

            return self.apiManager.attemptToReserve(
                fromUsernameCandidates: usernameCandidates,
                attemptId: thisAttemptId
            )
        }.done(on: self.context.schedulers.main) { [weak self] reservationResult -> Void in
            guard let self else { return }

            // If the reservation we just attempted is not current, we should
            // drop it and bail out.
            guard
                case let .pending(id) = self.currentUsernameState,
                reservationResult.attemptId == id
            else {
                UsernameLogger.shared.info("Dropping reservation result, attempt is outdated. Attempt ID: \(reservationResult.attemptId)")
                return
            }

            switch reservationResult.state {
            case let .successful(reservation):
                UsernameLogger.shared.info("Successfully reserved nickname! Attempt ID: \(id)")

                self.currentUsernameState = .reservationSuccessful(reservation: reservation)
            case .rejected:
                UsernameLogger.shared.warn("Reservation rejected. Attempt ID: \(id)")

                self.currentUsernameState = .reservationRejected
            case .rateLimited:
                UsernameLogger.shared.error("Reservation rate-limited. Attempt ID: \(id)")

                // Hides the rate-limited error, but not incorrect.
                self.currentUsernameState = .reservationFailed
            }
        }.catch(on: self.context.schedulers.main) { [weak self] error in
            guard let self else { return }

            if error is ReservationNotAttemptedError {
                return
            }

            self.currentUsernameState = .reservationFailed

            if let error = error as? API.ReservationError {
                UsernameLogger.shared.error("Reservation failed with error \(error.underlying). Attempt ID: \(error.attemptId)")
            } else {
                owsFailDebug("Reservation failed with unexpected error \(error)!")
            }
        }
    }
}

// MARK: - UITextFieldDelegate

extension UsernameSelectionViewController: UITextFieldDelegate {
    /// Called when user action would result in changed contents in the text
    /// field.
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        return TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: string,
            maxUnicodeScalarCount: Int(Constants.maxNicknameCodepointLength)
        )
    }
}

// MARK: - UITextViewDelegate and Learn More

extension UsernameSelectionViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        guard url == Constants.learnMoreLink else {
            owsFail("Unexpected URL in text view!")
        }

        UsernameLogger.shared.debug("Tapped the Learn More link.")
        presentLearnMoreActionSheet()

        return false
    }

    /// Present an action sheet to the user with a detailed explanation of the
    /// username discriminator.
    private func presentLearnMoreActionSheet() {
        let title = OWSLocalizedString(
            "USERNAME_SELECTION_LEARN_MORE_ACTION_SHEET_TITLE",
            value: "What is this number?",
            comment: "The title of a sheet that pops up when the user taps \"Learn More\" in text that explains how usernames work. The sheet will present a more detailed explanation of the username's numeric suffix."
        )

        let message = OWSLocalizedString(
            "USERNAME_SELECTION_LEARN_MORE_ACTION_SHEET_MESSAGE",
            value: "These digits help keep your username private so you can avoid unwanted messages. Share your username with only the people and groups you’d like to chat with. If you change usernames you’ll get a new set of digits.",
            comment: "The message of a sheet that pops up when the user taps \"Learn More\" in text that explains how usernames work. This message help explain that the automatically-generated numeric suffix of their username helps keep their username private, to avoid them being contacted by people by whom they don't want to be contacted."
        )

        OWSActionSheets.showActionSheet(
            title: title,
            message: message
        )
    }
}

// MARK: - Recompute table view item heights

private extension OWSTableViewController2 {
    /// Recompute heights in-place for all table items, headers, and footers.
    func recomputeItemHeightsWithoutReloadingData() {
        AssertIsOnMainThread()

        UIView.performWithoutAnimation {
            // Calling `.beginUpdates()` triggers a height computation for all
            // items in the table view.

            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }
}
