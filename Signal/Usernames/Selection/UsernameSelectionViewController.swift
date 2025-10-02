//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import SignalServiceKit
import SignalUI

protocol UsernameSelectionDelegate: AnyObject {
    /// Called after the `UsernameSelectionViewController` dismisses after a
    /// successful username confirmation.
    func usernameSelectionDidDismissAfterConfirmation(username: String)
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
        let localUsernameManager: LocalUsernameManager
        let storageServiceManager: StorageServiceManager
    }

    enum Constants {
        /// Minimum length for a nickname, in Unicode code points.
        static let minNicknameCodepointLength: UInt32 = RemoteConfig.current.minNicknameLength

        /// Maximum length for a nickname, in Unicode code points.
        static let maxNicknameCodepointLength: UInt32 = RemoteConfig.current.maxNicknameLength

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

    private enum UsernameSelectionState: Equatable, CustomStringConvertible {
        /// The user's existing username is unchanged.
        case noChangesToExisting
        /// The user's existing username has changed, but only in letter casing.
        case caseOnlyChange(newUsername: ParsedUsername)
        /// Username state is pending. Stores an ID, to disambiguate multiple
        /// potentially-overlapping state updates.
        case pending(id: UUID)
        /// The username has been successfully reserved.
        case reservationSuccessful(
            username: ParsedUsername,
            hashedUsername: Usernames.HashedUsername
        )
        /// The username was rejected by the server during reservation.
        case reservationRejected
        /// The reservation was rejected by the server due to rate limiting.
        case reservationRateLimited
        /// The reservation failed due to a network error.
        case reservationFailedNetworkError
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
        /// The custom-set discriminator is too short, but not empty.
        case customDiscriminatorTooShort
        /// The custom-set discriminator is 00, which is not valid.
        case customDiscriminatorIs00
        /// The discriminator has been manually cleared.
        case emptyDiscriminator(nickname: String)

        var description: String {
            switch self {
            case .noChangesToExisting:
                return "noChangesToExisting"
            case .caseOnlyChange:
                return "caseOnlyChange"
            case .pending(id: _):
                return "pending"
            case .reservationSuccessful(username: _, hashedUsername: _):
                return "reservationSuccessful"
            case .reservationRejected:
                return "reservationRejected"
            case .reservationRateLimited:
                return "reservationRateLimited"
            case .reservationFailedNetworkError:
                return "reservationFailedNetworkError"
            case .reservationFailed:
                return "reservationFailed"
            case .tooShort:
                return "tooShort"
            case .tooLong:
                return "tooLong"
            case .cannotStartWithDigit:
                return "cannotStartWithDigit"
            case .invalidCharacters:
                return "invalidCharacters"
            case .customDiscriminatorTooShort:
                return "customDiscriminatorTooShort"
            case .customDiscriminatorIs00:
                return "customDiscriminatorIs00"
            case .emptyDiscriminator(nickname: _):
                return "emptyDiscriminator"
            }
        }
    }

    typealias ParsedUsername = Usernames.ParsedUsername

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

    /// If the user is attempting to recover a corrupted username.
    private var isAttemptingRecovery: Bool

    /// Injected dependencies.
    private let context: Context

    // MARK: Public members

    weak var usernameChangeDelegate: UsernameChangeDelegate?
    weak var usernameSelectionDelegate: (any UsernameSelectionDelegate)?

    // MARK: Init

    init(
        existingUsername: ParsedUsername?,
        isAttemptingRecovery: Bool,
        context: Context
    ) {
        self.existingUsername = existingUsername
        self.isAttemptingRecovery = isAttemptingRecovery
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
    private lazy var doneBarButtonItem: UIBarButtonItem = .doneButton { [weak self] in
        self?.didTapDone()
    }

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
        wrapper.textField.discriminatorView.delegate = self
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
        Theme.tableView2PresentedBackgroundColor
    }

    override func themeDidChange() {
        super.themeDidChange()

        view.backgroundColor = Theme.tableView2PresentedBackgroundColor
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

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in self?.hasUnsavedEdits }
        )

        navigationItem.rightBarButtonItem = doneBarButtonItem
    }

    private func setupViewConstraints() {
        view.addSubview(wrapperScrollView)

        wrapperScrollView.addSubview(headerView)
        wrapperScrollView.addSubview(usernameTextFieldWrapper)
        wrapperScrollView.addSubview(usernameErrorTextView)
        wrapperScrollView.addSubview(usernameFooterTextView)

        wrapperScrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrapperScrollView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            wrapperScrollView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            wrapperScrollView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            wrapperScrollView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

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
        usernameErrorTextView.autoPinWidthToSuperview()

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
        updateFooterTextViewContent()
        // If this is done synchronously with `updateUsernameTextFieldContent`,
        // there will be unwanted animations on the text field.
        DispatchQueue.main.async {
            self.updateErrorTextViewContent()
        }
    }

    /// Update the contents of navigation items for the current internal
    /// controller state.
    private func updateNavigationItems() {
        doneBarButtonItem.isEnabled = {
            switch currentUsernameState {
            case
                    .caseOnlyChange,
                    .reservationSuccessful:
                return true
            case
                    .noChangesToExisting,
                    .pending,
                    .reservationRejected,
                    .reservationRateLimited,
                    .reservationFailedNetworkError,
                    .reservationFailed,
                    .tooShort,
                    .tooLong,
                    .cannotStartWithDigit,
                    .invalidCharacters,
                    .customDiscriminatorTooShort,
                    .customDiscriminatorIs00,
                    .emptyDiscriminator:
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
            case let .caseOnlyChange(newUsername):
                return newUsername.reassembled
            case let .reservationSuccessful(username, _):
                return username.reassembled
            case
                    .pending,
                    .reservationRejected,
                    .reservationRateLimited,
                    .reservationFailedNetworkError,
                    .reservationFailed,
                    .tooShort,
                    .tooLong,
                    .cannotStartWithDigit,
                    .invalidCharacters,
                    .customDiscriminatorTooShort,
                    .customDiscriminatorIs00,
                    .emptyDiscriminator:
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
        case let .caseOnlyChange(newUsername):
            self.usernameTextFieldWrapper.textField.configure(forConfirmedUsername: newUsername)
        case .pending:
            self.usernameTextFieldWrapper.textField.configureForSomethingPending()
        case let .reservationSuccessful(username, _):
            self.usernameTextFieldWrapper.textField.configure(forConfirmedUsername: username)
        case
                .reservationRejected,
                .reservationRateLimited,
                .reservationFailedNetworkError,
                .reservationFailed,
                .tooShort,
                .tooLong,
                .cannotStartWithDigit,
                .invalidCharacters,
                .customDiscriminatorTooShort,
                .customDiscriminatorIs00,
                .emptyDiscriminator:
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
                    .caseOnlyChange,
                    .pending,
                    .reservationSuccessful:
                return nil
            case .reservationRejected:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_NOT_AVAILABLE_ERROR_MESSAGE",
                    comment: "An error message shown when the user wants to set their username to an unavailable value."
                )
            case .reservationRateLimited:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_RESERVATION_RATE_LIMITED_ERROR_MESSAGE",
                    comment: "An error message shown when the user has attempted too many username reservations."
                )
            case .reservationFailedNetworkError:
                return Usernames.RemoteMutationError.networkError.localizedDescription
            case .reservationFailed:
                return CommonStrings.somethingWentWrongTryAgainLaterError
            case .tooShort:
                return String(
                    format: OWSLocalizedString(
                        "USERNAME_SELECTION_TOO_SHORT_ERROR_MESSAGE_%d",
                        tableName: "PluralAware",
                        comment: "An error message shown when the user has typed a username that is below the minimum character limit. Embeds {{ %d the minimum character count }}."
                    ),
                    Constants.minNicknameCodepointLength
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
            case .customDiscriminatorTooShort, .emptyDiscriminator:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_INVALID_DISCRIMINATOR_ERROR_MESSAGE",
                    comment: "An error message shown when the user has typed an invalid discriminator for their username."
                )
            case .customDiscriminatorIs00:
                return OWSLocalizedString(
                    "USERNAME_SELECTION_ZERO_DISCRIMINATOR_ERROR_MESSAGE",
                    comment: "An error message shown when the user has typed '00' as their discriminator for their username."
                )
            }
        }()

        var layoutBlock: ((UITextView) -> Void)?

        if let errorText {
            usernameErrorTextView.text = errorText

            if usernameErrorTextViewZeroHeightConstraint.isActive {
                usernameErrorTextViewZeroHeightConstraint.isActive = false
                layoutBlock = { $0.layer.opacity = 1 }
            }
        } else if !usernameErrorTextViewZeroHeightConstraint.isActive {
            usernameErrorTextViewZeroHeightConstraint.isActive = true
            layoutBlock = { $0.layer.opacity = 0 }
        }

        guard let layoutBlock else {
            return
        }

        if UIAccessibility.isReduceMotionEnabled {
            layoutBlock(self.usernameErrorTextView)
            self.view.layoutIfNeeded()
        } else {
            let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)

            animator.addAnimations {
                layoutBlock(self.usernameErrorTextView)
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

        usernameFooterTextView.linkTextAttributes = [
            .foregroundColor: Theme.primaryTextColor,
        ]
        usernameFooterTextView.attributedText = content
    }
}

// MARK: - Nav bar events

private extension UsernameSelectionViewController {

    /// Called when the user taps "Done". Attempts to finalize the new chosen
    /// username.
    private func didTapDone() {
        AssertIsOnMainThread()

        let usernameState = self.currentUsernameState

        switch usernameState {
        case let .caseOnlyChange(newUsername):
            changeUsernameCaseBehindModalActivityIndicator(
                newUsername: newUsername
            )
        case let .reservationSuccessful(_, hashedUsername):
            confirmNewUsername(reservedUsername: hashedUsername)
        case
                .noChangesToExisting,
                .pending,
                .reservationRejected,
                .reservationRateLimited,
                .reservationFailedNetworkError,
                .reservationFailed,
                .tooShort,
                .tooLong,
                .cannotStartWithDigit,
                .invalidCharacters,
                .customDiscriminatorTooShort,
                .emptyDiscriminator,
                .customDiscriminatorIs00:
            owsFail("Unexpected username state: \(usernameState). Should be impossible from the UI!")
        }
    }

    private func changeUsernameCaseBehindModalActivityIndicator(
        newUsername: ParsedUsername
    ) {
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false
        ) { modal in
            UsernameLogger.shared.info("Changing username case.")

            Guarantee.wrapAsync {
                await self.context.localUsernameManager.updateVisibleCaseOfExistingUsername(newUsername: newUsername.reassembled)
            }.map(on: DispatchQueue.main) { remoteMutationResult -> Usernames.RemoteMutationResult<Void> in
                let newState = self.context.databaseStorage.read { tx in
                    return self.context.localUsernameManager.usernameState(tx: tx)
                }

                self.usernameChangeDelegate?.usernameStateDidChange(newState: newState)

                return remoteMutationResult
            }.done(on: DispatchQueue.main) { remoteMutationResult -> Void in
                switch remoteMutationResult {
                case .success:
                    UsernameLogger.shared.info("Changed username case!")

                    modal.dismiss {
                        self.dismiss(animated: true)
                    }
                case .failure(let remoteMutationError):
                    self.dismiss(
                        modalActivityIndicator: modal,
                        andPresentErrorMessage: remoteMutationError.localizedDescription
                    )
                }
            }
        }
    }

    private func confirmNewUsername(reservedUsername: Usernames.HashedUsername) {
        if existingUsername == nil, !isAttemptingRecovery {
            self.confirmReservationBehindModalActivityIndicator(
                reservedUsername: reservedUsername
            )
        } else {
            OWSActionSheets.showConfirmationAlert(
                message: OWSLocalizedString(
                    "USERNAME_SELECTION_CHANGE_USERNAME_CONFIRMATION_MESSAGE",
                    comment: "A message explaining the side effects of changing your username."
                ),
                proceedTitle: CommonStrings.continueButton,
                proceedAction: { [weak self] _ in
                    self?.confirmReservationBehindModalActivityIndicator(
                        reservedUsername: reservedUsername
                    )
                }
            )
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

            Guarantee.wrapAsync {
                await self.context.localUsernameManager.confirmUsername(reservedUsername: reservedUsername)
            }.map(on: DispatchQueue.main) { remoteMutationResult -> Usernames.RemoteMutationResult<Usernames.ConfirmationResult> in
                let newState = self.context.databaseStorage.read { tx in
                    return self.context.localUsernameManager.usernameState(tx: tx)
                }

                self.usernameChangeDelegate?.usernameStateDidChange(newState: newState)

                return remoteMutationResult
            }.done(on: DispatchQueue.main) { remoteMutationResult -> Void in
                switch remoteMutationResult {
                case .success(.success):
                    UsernameLogger.shared.info("Confirmed username!")

                    modal.dismiss {
                        self.dismiss(animated: true) {
                            self.usernameSelectionDelegate?.usernameSelectionDidDismissAfterConfirmation(username: reservedUsername.usernameString)
                        }
                    }
                case .success(.rejected):
                    UsernameLogger.shared.error("Failed to confirm the username, server rejected.")

                    self.dismiss(
                        modalActivityIndicator: modal,
                        andPresentErrorMessage: CommonStrings.somethingWentWrongError
                    )
                case .success(.rateLimited):
                    UsernameLogger.shared.error("Failed to confirm the username, rate-limited.")

                    self.dismiss(
                        modalActivityIndicator: modal,
                        andPresentErrorMessage: CommonStrings.somethingWentWrongTryAgainLaterError
                    )
                case .failure(let remoteMutationError):
                    self.dismiss(
                        modalActivityIndicator: modal,
                        andPresentErrorMessage: remoteMutationError.localizedDescription
                    )
                }
            }
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

        let nicknameFromTextField: String? = usernameTextFieldWrapper.textField.nickname

        // Only set when a discriminator was manually entered. nil indicates a
        // new discriminator should be rolled.
        var desiredDiscriminator = usernameTextFieldWrapper.textField.discriminatorView.customDiscriminator

        let hasEnteredNewCustomDiscriminator: Bool = {
            if
                let desiredDiscriminator,
                desiredDiscriminator != existingUsername?.discriminator
            {
                return true
            }

            return false
        }()

        if
            !hasEnteredNewCustomDiscriminator,
            existingUsername?.nickname == nicknameFromTextField
        {
            currentUsernameState = .noChangesToExisting
        } else if
            !hasEnteredNewCustomDiscriminator,
            let existingUsername,
            let nicknameFromTextField,
            existingUsername.nickname.lowercased() == nicknameFromTextField.lowercased()
        {
            currentUsernameState = .caseOnlyChange(
                newUsername: existingUsername.updatingNickame(newNickname: nicknameFromTextField)
            )
        } else if desiredDiscriminator == "00" {
            currentUsernameState = .customDiscriminatorIs00
        } else if let desiredNickname = nicknameFromTextField {
            if
                let discriminatorString = desiredDiscriminator,
                discriminatorString.count < 2
            {
                if discriminatorString.count > 0 {
                    currentUsernameState = .customDiscriminatorTooShort
                    return
                } else {
                    // Empty string. If it was just set to empty, save the nickname.
                    // Once the nickname changes, roll a new discriminator.
                    if case let .emptyDiscriminator(nickname: oldNickname) = currentUsernameState {
                        if oldNickname != desiredNickname {
                            // Nickname changed. Roll new discriminator
                            desiredDiscriminator = nil
                            // continue
                        }
                    } else {
                        currentUsernameState = .emptyDiscriminator(nickname: desiredNickname)
                        return
                    }
                }
            }

            typealias CandidateError = Usernames.HashedUsername.CandidateGenerationError

            do {
                let usernameCandidates = try Usernames.HashedUsername.generateCandidates(
                    forNickname: desiredNickname,
                    minNicknameLength: Constants.minNicknameCodepointLength,
                    maxNicknameLength: Constants.maxNicknameCodepointLength,
                    desiredDiscriminator: desiredDiscriminator
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

                Guarantee.after(wallInterval: Constants.tooShortDebounceTimeInterval).done(on: DispatchQueue.main) {
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

        enum ReservationResult {
            case notAttempted
            case success(Usernames.ReservationResult)
            case networkError
            case unknownError
        }

        let thisAttemptId = UUID()
        let logger = UsernameLogger.shared.suffixed(with: "Attempt ID: \(thisAttemptId)")

        self.currentUsernameState = .pending(id: thisAttemptId)
        // Delay to detect multiple rapid consecutive edits.
        Guarantee.after(wallInterval: Constants.reservationDebounceTimeInternal).then(on: DispatchQueue.main) { () -> Guarantee<ReservationResult> in
            // If this attempt is no longer current after debounce, we should
            // bail out without firing a reservation.
            guard
                case let .pending(id) = self.currentUsernameState,
                thisAttemptId == id
            else {
                return .value(.notAttempted)
            }

            logger.info("Attempting to reserve username.")

            return Guarantee.wrapAsync {
                await self.context.localUsernameManager.reserveUsername(usernameCandidates: usernameCandidates)
            }.map(on: SyncScheduler()) { remoteMutationResult -> ReservationResult in
                switch remoteMutationResult {
                case .success(let reservationResult):
                    return .success(reservationResult)
                case .failure(.networkError):
                    return .networkError
                case .failure(.otherError):
                    return .unknownError
                }
            }
        }.done(on: DispatchQueue.main) { (reservationResult: ReservationResult) -> Void in
            // If the reservation we just attempted is not current, we should
            // drop it and bail out.
            guard
                case let .pending(id) = self.currentUsernameState,
                thisAttemptId == id
            else {
                logger.info("Dropping reservation result, attempt is outdated.")
                return
            }

            switch reservationResult {
            case .notAttempted:
                return
            case let .success(.successful(username, hashedUsername)):
                logger.info("Successfully reserved nickname!")

                self.currentUsernameState = .reservationSuccessful(
                    username: username,
                    hashedUsername: hashedUsername
                )
            case .success(.rejected):
                logger.warn("Reservation rejected.")

                self.currentUsernameState = .reservationRejected
            case .success(.rateLimited):
                logger.error("Reservation rate-limited.")

                self.currentUsernameState = .reservationRateLimited
            case .networkError:
                logger.error("Reservation failed due to a network error.")

                self.currentUsernameState = .reservationFailedNetworkError
            case .unknownError:
                logger.error("Reservation failed due to an unknown error.")

                self.currentUsernameState = .reservationFailed
            }
        }
    }
}

// MARK: - DiscriminatorTextFieldDelegate

extension UsernameSelectionViewController: DiscriminatorTextFieldDelegate {
    func didManuallyChangeDiscriminator() {
        usernameTextFieldContentsDidChange()
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

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let usernameTextField = textField as? UsernameTextField else { return true }
        usernameTextField.discriminatorView.becomeFirstResponder()
        return true
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

        presentLearnMoreActionSheet()

        return false
    }

    /// Present an action sheet to the user with a detailed explanation of the
    /// username discriminator.
    private func presentLearnMoreActionSheet() {
        let title = OWSLocalizedString(
            "USERNAME_SELECTION_LEARN_MORE_ACTION_SHEET_TITLE",
            comment: "The title of a sheet that pops up when the user taps \"Learn More\" in text that explains how usernames work. The sheet will present a more detailed explanation of the username's numeric suffix."
        )

        let message = OWSLocalizedString(
            "USERNAME_SELECTION_LEARN_MORE_ACTION_SHEET_MESSAGE",
            comment: "The message of a sheet that pops up when the user taps \"Learn More\" in text that explains how usernames work. This message help explain that the automatically-generated numeric suffix of their username helps keep their username private, to avoid them being contacted by people by whom they don't want to be contacted."
        )

        OWSActionSheets.showActionSheet(
            title: title,
            message: message
        )
    }
}
