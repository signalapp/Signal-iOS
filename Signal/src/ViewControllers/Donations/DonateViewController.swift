//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import PassKit
import SignalServiceKit
import SignalUI

class DonateViewController: OWSViewController, OWSNavigationChildController {
    private static func canMakeNewDonations(
        forDonateMode donateMode: DonateMode,
    ) -> Bool {
        DonationUtilities.canDonate(
            inMode: donateMode.asDonationMode,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
    }

    static let cornerRadius: CGFloat = 18
    static var bubbleBackgroundColor: CGColor { DonationViewsUtil.bubbleBackgroundColor.cgColor }
    static var selectedColor: CGColor { UIColor.Signal.accent.cgColor }

    var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    var navbarBackgroundColorOverride: UIColor? { .clear }

    private static func commonStack() -> UIStackView {
        let result = UIStackView()
        result.axis = .vertical
        result.alignment = .fill
        result.spacing = 20
        return result
    }

    // MARK: - Initialization

    var state: State {
        didSet {
            Logger.info("[Donations] DonateViewController state changed to \(state.debugDescription)")
            render(oldState: oldValue)
        }
    }

    enum FinishResult {
        case completedDonation(
            donateSheet: DonateViewController,
            receiptCredentialSuccessMode: DonationReceiptCredentialResultStore.Mode,
        )

        case monthlySubscriptionCancelled(
            donateSheet: DonateViewController,
            toastText: String,
        )
    }

    let onFinished: (FinishResult) -> Void

    private var scrollToOneTimeContinueButtonWhenKeyboardAppears = false

    init(
        preferredDonateMode: DonateMode,
        onFinished: @escaping (FinishResult) -> Void,
    ) {
        if Self.canMakeNewDonations(forDonateMode: preferredDonateMode) {
            self.state = .init(donateMode: preferredDonateMode)
        } else {
            self.state = .init(donateMode: .monthly)
        }
        self.onFinished = onFinished

        super.init()
    }

    // MARK: - View callbacks

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground

        let isPresentedStandalone = navigationController?.viewControllers.first == self
        if isPresentedStandalone {
            navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        }

        OWSTableViewController2.removeBackButtonText(viewController: self)

        render(oldState: nil)
        Task {
            await loadAndUpdateState()
        }

        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.autoPinHeightToSuperview()

        let margin: CGFloat = 20
        stackView.layoutMargins = .init(top: 0, leading: margin, bottom: margin, trailing: margin)
        stackView.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didKeyboardShow),
            name: UIResponder.keyboardDidShowNotification,
            object: nil,
        )
    }

    // MARK: - Events

    @objc
    private func didDonateModeChange() {
        let rawValue = donateModePickerView.selectedSegmentIndex
        guard let newValue = DonateMode(rawValue: rawValue) else {
            owsFail("[Donations] Unexpected donate mode")
        }
        state = state.selectDonateMode(newValue)
    }

    private func addAnimationView(anchor: UIView, name: String) {
        if UIAccessibility.isReduceMotionEnabled { return }

        let animationView = LottieAnimationView(name: name)
        animationView.loopMode = .playOnce
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .forceFinish
        animationView.isUserInteractionEnabled = false
        stackView.addSubview(animationView)
        animationView.autoPinEdge(.bottom, to: .top, of: anchor, withOffset: 30)
        animationView.autoPinEdge(.leading, to: .leading, of: anchor)
        animationView.autoMatch(.width, to: .width, of: anchor)
        animationView.play { _ in
            animationView.removeFromSuperview()
        }
    }

    private func didSelectOneTimeAmount(
        amount: FiatMoney,
        animationAnchor: UIView,
        animationName: String,
    ) {
        state = state.selectOneTimeAmount(.selectedPreset(amount: amount))
        addAnimationView(anchor: animationAnchor, name: animationName)
    }

    @objc
    private func didKeyboardShow() {
        if scrollToOneTimeContinueButtonWhenKeyboardAppears {
            scrollView.scrollIntoView(subview: oneTimeContinueButton)
            scrollToOneTimeContinueButtonWhenKeyboardAppears = false
        }
    }

    @objc
    private func didTapOneTimeCustomAmountTextField() {
        guard let oneTime = state.oneTime else {
            owsFail("[Donations] Expected one-time state but it was not loaded")
        }

        switch oneTime.selectedAmount {
        case .nothingSelected, .selectedPreset:
            state = state.selectOneTimeAmount(.choseCustomAmount(
                amount: FiatMoney(currencyCode: oneTime.selectedCurrencyCode, value: 0),
            ))
        case .choseCustomAmount:
            break
        }

        oneTimeCustomAmountTextField.becomeFirstResponder()
        scrollToOneTimeContinueButtonWhenKeyboardAppears = true
    }

    @objc
    private func didTapMonthlySubscriptionLevelView(_ sender: UIGestureRecognizer) {
        guard let view = sender.view as? MonthlySubscriptionLevelView else {
            owsFail("[Donations] Tapped something other than a monthly subscription level view")
        }
        state = state.selectSubscriptionLevel(view.subscriptionLevel)
        addAnimationView(anchor: view, name: view.animationName)
    }

    private func startApplePay(
        with amount: FiatMoney,
        donateMode: DonateMode,
    ) {
        let paymentRequest = DonationUtilities.newPaymentRequest(
            for: amount,
            isRecurring: {
                switch donateMode {
                case .oneTime: return false
                case .monthly: return true
                }
            }(),
        )
        let paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        paymentController.delegate = self
        paymentController.present { presented in
            if !presented {
                // This can happen under normal conditions if the user double-taps the button,
                // but may also indicate a problem.
                Logger.warn("[Donations] Failed to present payment controller")
            }
        }
    }

    private func startManualPaymentDetails(
        with amount: FiatMoney,
        badge: ProfileBadge?,
        donateMode: DonateMode,
        donationPaymentMethod: DonationPaymentMethod,
        viewControllerPaymentMethod: DonationPaymentDetailsViewController.PaymentMethod,
    ) {
        guard let navigationController else {
            owsFail("[Donations] Cannot open credit/debit card screen if we're not in a navigation controller")
        }

        guard let badge else {
            owsFail("[Donations] Missing badge")
        }

        let cardDonationMode: DonationPaymentDetailsViewController.DonationMode
        let receiptCredentialSuccessMode: DonationReceiptCredentialResultStore.Mode
        switch donateMode {
        case .oneTime:
            cardDonationMode = .oneTime
            receiptCredentialSuccessMode = .oneTimeBoost
        case .monthly:
            guard
                let monthly = state.monthly,
                let subscriptionLevel = monthly.selectedSubscriptionLevel
            else {
                owsFail("[Donations] Cannot update monthly donation. This should be prevented in the UI")
            }
            cardDonationMode = .monthly(
                subscriptionLevel: subscriptionLevel,
                subscriberID: monthly.subscriberID,
                currentSubscription: monthly.currentSubscription,
                currentSubscriptionLevel: monthly.currentSubscriptionLevel,
            )
            receiptCredentialSuccessMode = .recurringSubscriptionInitiation
        }

        let vc = DonationPaymentDetailsViewController(
            donationAmount: amount,
            donationMode: cardDonationMode,
            paymentMethod: viewControllerPaymentMethod,
        ) { [weak self] error in
            guard let self else { return }
            if let error {
                self.didFailDonation(
                    error: error,
                    mode: donateMode,
                    badge: badge,
                    paymentMethod: donationPaymentMethod,
                )
            } else {
                self.didCompleteDonation(
                    receiptCredentialSuccessMode: receiptCredentialSuccessMode,
                )
            }
        }

        navigationController.pushViewController(vc, animated: true)
    }

    private func startPaypal(
        with amount: FiatMoney,
        badge: ProfileBadge?,
        donateMode: DonateMode,
    ) {
        guard let badge else {
            owsFail("[Donations] Missing badge!")
        }

        switch donateMode {
        case .oneTime:
            startPaypalBoost(with: amount, badge: badge)
        case .monthly:
            startPaypalSubscription(with: amount, badge: badge)
        }
    }

    private func startSEPA(
        with amount: FiatMoney,
        badge: ProfileBadge?,
        donateMode: DonateMode,
    ) {
        if
            case .oneTime = donateMode,
            let maximumAmount = state.oneTime?.maximumAmountViaSepa,
            DonationUtilities.isBoostAmountTooLarge(amount, maximumAmount: maximumAmount)
        {
            // SEPA has a maximum amount above which we know payment will fail.
            // Rather than putting the user through the UI only to fail, we'll
            // show an error and give up early.
            presentAmountTooLargeForSepaSheet(maximumAmount: maximumAmount)
            return
        }

        let mandateViewController = BankTransferMandateViewController(bankTransferType: .sepa) { [weak self] mandate in
            guard let self else { return }
            self.dismiss(animated: true) {
                self.startManualPaymentDetails(
                    with: amount,
                    badge: badge,
                    donateMode: donateMode,
                    donationPaymentMethod: .sepa,
                    viewControllerPaymentMethod: .sepa(mandate: mandate),
                )
            }
        }
        let navigationController = OWSNavigationController(rootViewController: mandateViewController)
        self.presentFormSheet(navigationController, animated: true)
    }

    private func presentAmountTooLargeForSepaSheet(maximumAmount: FiatMoney) {
        let messageFormat = OWSLocalizedString(
            "DONATE_SCREEN_ERROR_MESSAGE_FORMAT_BANK_TRANSFER_AMOUNT_TOO_LARGE",
            comment: "Message for an alert shown when the user tries to donate via bank transfer, but the amount they want to donate is too large. Embeds {{ the maximum allowed donation amount }}.",
        )

        let actionSheetController = ActionSheetController(
            title: OWSLocalizedString(
                "DONATE_SCREEN_ERROR_TITLE_BANK_TRANSFER_AMOUNT_TOO_LARGE",
                comment: "Title for an alert shown when the user tries to donate via bank transfer, but the amount they want to donate is too large.",
            ),
            message: String(
                format: messageFormat,
                CurrencyFormatter.format(money: maximumAmount),
            ),
        )
        actionSheetController.addAction(OWSActionSheets.okayAction)

        presentActionSheet(actionSheetController)
    }

    private func startIDEAL(
        with amount: FiatMoney,
        badge: ProfileBadge?,
        donateMode: DonateMode,
    ) {
        // For iDEAL, monthly donations are backed by SEPA transaction, so only
        // show the mandate UI for this case.
        switch donateMode {
        case .monthly:
            let mandateViewController = BankTransferMandateViewController(bankTransferType: .sepa) { [weak self] mandate in
                guard let self else { return }
                self.dismiss(animated: true) {
                    self.startManualPaymentDetails(
                        with: amount,
                        badge: badge,
                        donateMode: donateMode,
                        donationPaymentMethod: .ideal,
                        viewControllerPaymentMethod: .ideal(paymentType: .recurring(mandate: mandate)),
                    )
                }
            }
            let navigationController = OWSNavigationController(rootViewController: mandateViewController)
            self.presentFormSheet(navigationController, animated: true)
        case .oneTime:
            self.startManualPaymentDetails(
                with: amount,
                badge: badge,
                donateMode: donateMode,
                donationPaymentMethod: .ideal,
                viewControllerPaymentMethod: .ideal(paymentType: .oneTime),
            )
        }
    }

    private func presentChoosePaymentMethodSheet(
        amount: FiatMoney,
        badge: ProfileBadge,
        donateMode: DonateMode,
        supportedPaymentMethods: Set<DonationPaymentMethod>,
    ) {
        oneTimeCustomAmountTextField.resignFirstResponder()

        let sheet = DonateChoosePaymentMethodSheet(
            amount: amount,
            badge: badge,
            donationMode: donateMode.forChoosePaymentMethodSheet,
            supportedPaymentMethods: supportedPaymentMethods,
        ) { [weak self] sheet, paymentMethod in
            sheet.dismiss(animated: true) { [weak self] in
                guard let self else { return }

                switch paymentMethod {
                case .applePay:
                    self.startApplePay(with: amount, donateMode: donateMode)
                case .creditOrDebitCard:
                    self.startManualPaymentDetails(
                        with: amount,
                        badge: badge,
                        donateMode: donateMode,
                        donationPaymentMethod: paymentMethod,
                        viewControllerPaymentMethod: .card,
                    )
                case .paypal:
                    self.startPaypal(
                        with: amount,
                        badge: badge,
                        donateMode: donateMode,
                    )
                case .sepa:
                    self.startSEPA(
                        with: amount,
                        badge: badge,
                        donateMode: donateMode,
                    )
                case .ideal:
                    self.startIDEAL(
                        with: amount,
                        badge: badge,
                        donateMode: donateMode,
                    )
                }
            }
        }

        present(sheet, animated: true)
    }

    private func didTapToContinueOneTimeDonation() {
        guard let oneTime = state.oneTime else {
            owsFail("[Donations] Expected the one-time state to be loaded. This should be impossible in the UI")
        }

        switch oneTime.paymentRequest {
        case let .alreadyHasPaymentProcessing(paymentMethod):
            let title: String
            let message: String

            switch paymentMethod {
            case .applePay, .creditOrDebitCard, .paypal:
                title = OWSLocalizedString(
                    "DONATE_SCREEN_ERROR_TITLE_YOU_HAVE_A_PAYMENT_PROCESSING",
                    comment: "Title for an alert presented when the user tries to make a donation, but already has a donation that is currently processing via non-bank payment.",
                )
                message = OWSLocalizedString(
                    "DONATE_SCREEN_ERROR_MESSAGE_PLEASE_WAIT_BEFORE_MAKING_ANOTHER_DONATION",
                    comment: "Message in an alert presented when the user tries to make a donation, but already has a donation that is currently processing via non-bank payment.",
                )
            case .sepa, .ideal:
                title = OWSLocalizedString(
                    "DONATE_SCREEN_ERROR_TITLE_BANK_PAYMENT_YOU_HAVE_A_DONATION_PENDING",
                    comment: "Title for an alert presented when the user tries to make a donation, but already has a donation that is currently processing via bank payment.",
                )
                message = OWSLocalizedString(
                    "DONATE_SCREEN_ERROR_MESSAGE_BANK_PAYMENT_PLEASE_WAIT_BEFORE_MAKING_ANOTHER_DONATION",
                    comment: "Message in an alert presented when the user tries to make a donation, but already has a donation that is currently processing via bank payment.",
                )
            }

            showError(title: title, message)
        case .noAmountSelected:
            showError(OWSLocalizedString(
                "DONATE_SCREEN_ERROR_NO_AMOUNT_SELECTED",
                comment: "If the user tries to donate to Signal but no amount is selected, this error message is shown.",
            ))
        case let .amountIsTooSmall(minimumAmount):
            let format = OWSLocalizedString(
                "DONATE_SCREEN_ERROR_SELECT_A_LARGER_AMOUNT_FORMAT",
                comment: "If the user tries to donate to Signal but they've entered an amount that's too small, this error message is shown. Embeds {{currency string}}, such as \"$5\".",
            )
            let currencyString = CurrencyFormatter.format(money: minimumAmount)
            showError(String(format: format, currencyString))
        case .awaitingIDEALAuthorization:
            // Not pending, but awaiting approval
            let title = OWSLocalizedString(
                "DONATE_SCREEN_ERROR_TITLE_YOU_HAVE_A_PAYMENT_PROCESSING",
                comment: "Title for an alert presented when the user tries to make a donation, but already has a donation that is currently processing via non-bank payment.",
            )
            let message = OWSLocalizedString(
                "DONATE_SCREEN_ERROR_MESSAGE_APPROVE_IDEAL_DONATION_BEFORE_MAKING_ANOTHER_DONATION",
                comment: "Message in an alert presented when the user tries to make a donation, but already has an iDEAL donation that is currently awaiting approval.",
            )
            showError(title: title, message)
        case let .canContinue(amount, supportedPaymentMethods):
            presentChoosePaymentMethodSheet(
                amount: amount,
                badge: oneTime.profileBadge,
                donateMode: .oneTime,
                supportedPaymentMethods: supportedPaymentMethods,
            )
        }
    }

    private func didTapToStartNewMonthlyDonation() {
        guard let monthlyPaymentRequest = state.monthly?.paymentRequest else {
            owsFail("[Donations] Cannot start monthly donation. This should be prevented in the UI")
        }

        presentChoosePaymentMethodSheet(
            amount: monthlyPaymentRequest.amount,
            badge: monthlyPaymentRequest.profileBadge,
            donateMode: .monthly,
            supportedPaymentMethods: monthlyPaymentRequest.supportedPaymentMethods,
        )
    }

    private func didConfirmMonthlyDonationUpdate() {
        guard
            let monthly = state.monthly,
            let monthlyPaymentRequest = monthly.paymentRequest,
            let subscriberID = monthly.subscriberID,
            let selectedSubscriptionLevel = monthly.selectedSubscriptionLevel
        else {
            owsFail("[Donations] Cannot update monthly donation. This should be prevented in the UI")
        }

        if
            let currentSubscription = monthly.currentSubscription,
            currentSubscription.chargeFailure == nil
        {
            Task {
                do {
                    try await DonationViewsUtil.wrapInProgressView(
                        from: self,
                        operation: {
                            let subscription = try await DonationSubscriptionManager.updateSubscriptionLevel(
                                for: subscriberID,
                                to: selectedSubscriptionLevel,
                                currencyCode: monthly.selectedCurrencyCode,
                            )

                            guard let donationPaymentProcessor = subscription.donationPaymentProcessor else {
                                throw OWSAssertionError("Missing donation payment processor while updating monthly donation!")
                            }

                            try await DonationViewsUtil.waitForRedemption(paymentMethod: subscription.donationPaymentMethod) {
                                // Treat updates like new subscriptions
                                try await DonationSubscriptionManager.requestAndRedeemReceipt(
                                    subscriberId: subscriberID,
                                    subscriptionLevel: selectedSubscriptionLevel.level,
                                    priorSubscriptionLevel: subscription.level,
                                    paymentProcessor: donationPaymentProcessor,
                                    paymentMethod: subscription.donationPaymentMethod,
                                    isNewSubscription: true,
                                )
                            }
                        },
                    )
                    self.didCompleteDonation(
                        receiptCredentialSuccessMode: .recurringSubscriptionInitiation,
                    )
                } catch {
                    self.didFailDonation(
                        error: error,
                        mode: .monthly,
                        badge: selectedSubscriptionLevel.badge,
                        paymentMethod: monthly.previousMonthlySubscriptionPaymentMethod,
                    )
                }
            }
        } else {
            Logger.warn("[Donations] Updating a subscription that is missing, or in a known error state. Treating this like a new subscription.")
            presentChoosePaymentMethodSheet(
                amount: monthlyPaymentRequest.amount,
                badge: monthlyPaymentRequest.profileBadge,
                donateMode: .monthly,
                supportedPaymentMethods: monthlyPaymentRequest.supportedPaymentMethods,
            )
        }
    }

    private func didTapToUpdateMonthlyDonation() {
        guard let monthlyPaymentRequest = state.monthly?.paymentRequest else {
            owsFail("[Donations] Cannot update monthly donation. This should be prevented in the UI")
        }

        let currencyString = CurrencyFormatter.format(money: monthlyPaymentRequest.amount)
        let title = OWSLocalizedString(
            "SUSTAINER_VIEW_UPDATE_SUBSCRIPTION_CONFIRMATION_TITLE",
            comment: "Update Subscription? Action sheet title",
        )
        let message = String(
            format: OWSLocalizedString(
                "SUSTAINER_VIEW_UPDATE_SUBSCRIPTION_CONFIRMATION_MESSAGE",
                comment: "Update Subscription? Action sheet message, embeds {{Price}}",
            ),
            currencyString,
        )
        let notNow = OWSLocalizedString(
            "SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW",
            comment: "Sustainer view Not Now Action sheet button",
        )

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(.init(
            title: CommonStrings.continueButton,
            style: .default,
            handler: { [weak self] _ in
                self?.didConfirmMonthlyDonationUpdate()
            },
        ))
        actionSheet.addAction(.init(
            title: notNow,
            style: .cancel,
            handler: nil,
        ))

        self.presentActionSheet(actionSheet)
    }

    private func didTapToCancelSubscription() {
        let title = OWSLocalizedString(
            "SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_TITLE",
            comment: "Confirm Cancellation? Action sheet title",
        )
        let message = OWSLocalizedString(
            "SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_MESSAGE",
            comment: "Confirm Cancellation? Action sheet message",
        )
        let confirm = OWSLocalizedString(
            "SUSTAINER_VIEW_CANCEL_SUBSCRIPTION_CONFIRMATION_CONFIRM",
            comment: "Confirm Cancellation? Action sheet confirm button",
        )
        let notNow = OWSLocalizedString(
            "SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW",
            comment: "Sustainer view Not Now Action sheet button",
        )
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: confirm,
            style: .default,
            handler: { [weak self] _ in
                self?.didConfirmSubscriptionCancelation()
            },
        ))
        actionSheet.addAction(ActionSheetAction(
            title: notNow,
            style: .cancel,
            handler: nil,
        ))
        presentActionSheet(actionSheet)
    }

    private func didConfirmSubscriptionCancelation() {
        guard let subscriberID = state.monthly?.subscriberID else {
            owsFail("[Donations] No subscriber ID to cancel")
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            asyncBlock: { modal in
                do {
                    try await DonationSubscriptionManager.cancelSubscription(for: subscriberID)
                    modal.dismiss { [weak self] in
                        guard let self else { return }
                        self.onFinished(.monthlySubscriptionCancelled(
                            donateSheet: self,
                            toastText: OWSLocalizedString(
                                "SUSTAINER_VIEW_SUBSCRIPTION_CANCELLED",
                                comment: "Toast indicating that the subscription has been cancelled",
                            ),
                        ))
                    }
                } catch {
                    modal.dismiss()
                    owsFailDebug("[Donations] Failed to cancel subscription \(error)")
                }
            },
        )
    }

    private func showError(title: String? = nil, _ message: String) {
        let actionSheet = ActionSheetController(
            title: title,
            message: message,
        )

        actionSheet.addAction(.init(
            title: CommonStrings.okayButton,
            style: .cancel,
            handler: nil,
        ))

        presentActionSheet(actionSheet)
    }

    func didCompleteDonation(
        receiptCredentialSuccessMode: DonationReceiptCredentialResultStore.Mode,
    ) {
        onFinished(.completedDonation(
            donateSheet: self,
            receiptCredentialSuccessMode: receiptCredentialSuccessMode,
        ))
    }

    func didCancelDonation() {
        // A cancel should not be considered "finishing" donation, since the
        // user may want to try again.
        Logger.info("User canceled donation!")
    }

    func didFailDonation(
        error: Error,
        mode: DonateMode,
        badge: ProfileBadge,
        paymentMethod: DonationPaymentMethod?,
    ) {
        if
            let donationJobError = error as? DonationJobError,
            case .timeout = donationJobError
        {
            // If this was a timeout error, we know a payment is in progress.
            // Consequently, we want to reload our own state so we reflect that
            // in-progress payment; for example, while a donation is pending we
            // won't allow the user to start another of the same type.
            //
            // Then, we'll show the error.

            navigationController?.popToViewController(self, animated: true) {
                Task { [weak self] in
                    await self?.loadAndUpdateState()
                    guard let self else { return }
                    DonationViewsUtil.presentErrorSheet(
                        from: self,
                        error: error,
                        mode: mode,
                        badge: badge,
                        paymentMethod: paymentMethod,
                    )
                }
            }
        } else {
            DonationViewsUtil.presentErrorSheet(
                from: self,
                error: error,
                mode: mode,
                badge: badge,
                paymentMethod: paymentMethod,
            )
        }
    }

    // MARK: - Loading data

    private func loadAndUpdateState() async {
        if case .loading = state.loadState {
            return
        }
        state = state.loading()
        state = await loadState(currentState: state)
    }

    /// Try to load the data we need and put it into a new state.
    ///
    /// Requests one-time and monthly badges and preset amounts from the
    /// service, prepares badge assets, and loads local state as appropriate.
    private func loadState(currentState: State) async -> State {
        typealias DonationConfiguration = DonationSubscriptionConfiguration

        let (
            subscriberID,
            previousSubscriberCurrencyCode,
            previousSubscriberPaymentMethod,
            oneTimeBoostReceiptCredentialRequestError,
            recurringSubscriptionReceiptCredentialRequestError,
            pendingIDEALOneTimeDonation,
            pendingIDEALSubscription,
        ) = SSKEnvironment.shared.databaseStorageRef.read {
            (
                DonationSubscriptionManager.getSubscriberID(transaction: $0),
                DonationSubscriptionManager.getSubscriberCurrencyCode(transaction: $0),
                DonationSubscriptionManager.getMostRecentSubscriptionPaymentMethod(transaction: $0),
                DependenciesBridge.shared.donationReceiptCredentialResultStore
                    .getRequestError(errorMode: .oneTimeBoost, tx: $0),
                DependenciesBridge.shared.donationReceiptCredentialResultStore
                    .getRequestErrorForAnyRecurringSubscription(tx: $0),
                DependenciesBridge.shared.externalPendingIDEALDonationStore.getPendingOneTimeDonation(tx: $0),
                DependenciesBridge.shared.externalPendingIDEALDonationStore.getPendingSubscription(tx: $0),
            )
        }

        // Start fetching the donation configuration.
        async let donationConfiguration = { () async throws -> DonationConfiguration in
            let donationConfiguration = try await DonationSubscriptionManager.fetchDonationConfiguration()

            let boostBadge = donationConfiguration.boost.badge
            let subscriptionBadges = donationConfiguration.subscription.levels.map { $0.badge }

            try await withThrowingTaskGroup { taskGroup in
                for badge in [boostBadge] + subscriptionBadges {
                    taskGroup.addTask {
                        try await SSKEnvironment.shared.profileManagerRef.badgeStore.populateAssetsOnBadge(badge)
                    }
                }
                try await taskGroup.waitForAll()
            }

            return donationConfiguration
        }()

        // Start loading the current subscription.
        async let currentSubscription = DonationViewsUtil.loadCurrentSubscription(subscriberID: subscriberID)

        do {
            return currentState.loaded(
                oneTimeConfig: try await donationConfiguration.boost,
                monthlyConfig: try await donationConfiguration.subscription,
                paymentMethodsConfig: try await donationConfiguration.paymentMethods,
                currentMonthlySubscription: try await currentSubscription,
                subscriberID: subscriberID,
                previousMonthlySubscriptionCurrencyCode: previousSubscriberCurrencyCode,
                previousMonthlySubscriptionPaymentMethod: previousSubscriberPaymentMethod,
                oneTimeBoostReceiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError,
                recurringSubscriptionReceiptCredentialRequestError: recurringSubscriptionReceiptCredentialRequestError,
                pendingIDEALOneTimeDonation: pendingIDEALOneTimeDonation,
                pendingIDEALSubscription: pendingIDEALSubscription,
                locale: Locale.current,
                localNumber: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber,
            )
        } catch {
            Logger.warn("[Donations] \(error)")
            owsFailDebugUnlessNetworkFailure(error)
            return currentState.loadFailed()
        }
    }

    // MARK: - Top-level rendering

    private let scrollView = UIScrollView()

    private let stackView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.alignment = .fill
        result.spacing = 24
        return result
    }()

    private func render(oldState: State?) {
        renderHeroView(oldState: oldState)
        renderBodyView(oldState: oldState)

        if oldState == nil {
            stackView.removeAllSubviews()
            stackView.addArrangedSubviews([heroView, bodyView])
        }
    }

    // MARK: - Hero

    private lazy var avatarView: ConversationAvatarView = DonationViewsUtil.avatarView()

    private lazy var heroView: DonationHeroView = {
        let result = DonationHeroView(avatarView: avatarView)
        result.delegate = self
        return result
    }()

    private func renderHeroView(oldState: State?) {
        let selectedProfileBadge = state.selectedProfileBadge
        let shouldUpdateAvatar: Bool = (
            oldState == nil ||
                oldState?.selectedProfileBadge != selectedProfileBadge,
        )
        guard shouldUpdateAvatar else { return }

        SSKEnvironment.shared.databaseStorageRef.read { [weak self] transaction in
            self?.avatarView.update(transaction) { config in
                guard let address = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aciAddress else {
                    return
                }
                config.dataSource = .address(address)
                config.addBadgeIfApplicable = true
                config.fallbackBadge = selectedProfileBadge
            }
        }
    }

    // MARK: - Body

    private lazy var bodyView: UIStackView = Self.commonStack()

    private func renderBodyView(oldState: State?) {
        switch state.loadState {
        case .initializing, .loading, .loadFailed:
            // TODO: We should show a different state if the loading failed.
            renderLoadingBody(oldState: oldState)
        case let .loaded(oneTime, monthly):
            renderLoadedBody(
                oldState: oldState,
                donateMode: state.donateMode,
                oneTime: oneTime,
                monthly: monthly,
            )
        }
    }

    private func renderLoadingBody(oldState: State?) {
        let wasPreviouslyLoading: Bool = {
            guard let oldState else { return false }
            switch oldState.loadState {
            case .initializing, .loading, .loadFailed:
                return true
            case .loaded:
                return false
            }
        }()
        if wasPreviouslyLoading { return }

        bodyView.removeAllSubviews()

        let spinner = loadingSpinnerView()
        bodyView.addArrangedSubview(spinner)
    }

    private func renderLoadedBody(
        oldState: State?,
        donateMode: DonateMode,
        oneTime: State.OneTimeState,
        monthly: State.MonthlyState,
    ) {
        switch donateMode {
        case .oneTime:
            renderCurrencyPickerView(
                oldState: oldState,
                selectedCurrencyCode: oneTime.selectedCurrencyCode,
            )
            renderOneTime(oldState: oldState, oneTime: oneTime)
        case .monthly:
            renderCurrencyPickerView(
                oldState: oldState,
                selectedCurrencyCode: monthly.selectedCurrencyCode,
            )
            renderMonthly(oldState: oldState, monthly: monthly)
        }

        renderDonateModePickerView()

        let wasLoaded: Bool = {
            switch oldState?.loadState {
            case .loaded: return true
            default: return false
            }
        }()
        if !wasLoaded || oldState?.donateMode != state.donateMode {
            var subviews: [UIView] = [currencyPickerContainerView]

            if Self.canMakeNewDonations(forDonateMode: state.donateMode) {
                subviews.append(donateModePickerView)
            }

            switch donateMode {
            case .oneTime:
                subviews.append(oneTimeView)
            case .monthly:
                subviews.append(monthlyView)
            }

            bodyView.removeAllSubviews()
            bodyView.addArrangedSubviews(subviews)

            bodyView.setCustomSpacing(18, after: currencyPickerContainerView)

            // Switching modes causes animations to lose their anchors,
            // so we remove them.
            for subview in stackView.subviews {
                if subview is LottieAnimationView {
                    subview.removeFromSuperview()
                }
            }
        }
    }

    // MARK: - Loading spinner

    private func loadingSpinnerView() -> UIView {
        let result = UIActivityIndicatorView(style: .medium)
        result.startAnimating()
        return result
    }

    // MARK: - Currency picker

    private var currencyPickerContainerView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.alignment = .center
        result.isLayoutMarginsRelativeArrangement = true
        result.directionalLayoutMargins.bottom = 16
        return result
    }()

    private func renderCurrencyPickerView(
        oldState: State?,
        selectedCurrencyCode: Currency.Code,
    ) {
        if
            oldState?.donateMode == state.donateMode,
            oldState?.selectedCurrencyCode == selectedCurrencyCode
        {
            return
        }

        let button = DonationCurrencyPickerButton(
            currentCurrencyCode: selectedCurrencyCode,
            hasLabel: false,
        ) { [weak self] in
            guard let self else { return }

            let vc = CurrencyPickerViewController(
                dataSource: StripeCurrencyPickerDataSource(
                    currentCurrencyCode: selectedCurrencyCode,
                    supportedCurrencyCodes: self.state.supportedCurrencyCodes,
                ),
            ) { [weak self] currencyCode in
                guard let self else { return }
                self.state = self.state.selectCurrencyCode(currencyCode)
            }

            self.oneTimeCustomAmountTextField.resignFirstResponder()

            self.navigationController?.pushViewController(vc, animated: true)
        }

        currencyPickerContainerView.removeAllSubviews()
        currencyPickerContainerView.addArrangedSubview(button)
    }

    // MARK: - Donation mode picker

    private lazy var donateModePickerView: UISegmentedControl = {
        let picker = UISegmentedControl()
        picker.insertSegment(
            withTitle: OWSLocalizedString(
                "DONATE_SCREEN_ONE_TIME_CHOICE",
                comment: "On the donation screen, you can choose between one-time and monthly donations. This is the text on the picker for one-time donations.",
            ),
            at: DonateMode.oneTime.rawValue,
            animated: false,
        )
        picker.insertSegment(
            withTitle: OWSLocalizedString(
                "DONATE_SCREEN_MONTHLY_CHOICE",
                comment: "On the donation screen, you can choose between one-time and monthly donations. This is the text on the picker for one-time donations.",
            ),
            at: DonateMode.monthly.rawValue,
            animated: false,
        )
        picker.addTarget(self, action: #selector(didDonateModeChange), for: .valueChanged)
        return picker
    }()

    private func renderDonateModePickerView() {
        donateModePickerView.selectedSegmentIndex = state.donateMode.rawValue
    }

    // MARK: - One-time

    private struct OneTimePresetButton {
        let amount: FiatMoney
        let view: UIButton
    }

    private var oneTimePresetButtons = [OneTimePresetButton]()

    private lazy var oneTimePresetsView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.distribution = .fillEqually
        result.spacing = 20
        return result
    }()

    private lazy var oneTimeCustomAmountTextField: OneTimeDonationCustomAmountTextField = {
        guard let currencyCode = state.oneTime?.selectedCurrencyCode else {
            owsFail("[Donations] In the one-time view without a currency code")
        }

        let field = OneTimeDonationCustomAmountTextField(currencyCode: currencyCode)
        field.font = .dynamicTypeBodyClamped
        field.placeholder = OWSLocalizedString(
            "BOOST_VIEW_CUSTOM_AMOUNT_PLACEHOLDER",
            comment: "Default text for the custom amount field of the boost view.",
        )
        field.textColor = .Signal.label
        field.delegate = self
        field.accessibilityIdentifier = UIView.accessibilityIdentifier(
            in: self,
            name: "custom_amount_text_field",
        )

        field.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth
#if compiler(>=6.2)
        if #available(iOS 26, *) {
            field.cornerConfiguration = .capsule()
        } else {
            field.layer.cornerRadius = Self.cornerRadius
        }
#else
        field.layer.cornerRadius = Self.cornerRadius
#endif

        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(didTapOneTimeCustomAmountTextField),
        )
        field.addGestureRecognizer(tap)

        return field
    }()

    private lazy var oneTimeContinueButton = UIButton(
        configuration: .largePrimary(title: CommonStrings.continueButton),
        primaryAction: UIAction { [weak self] _ in
            self?.didTapToContinueOneTimeDonation()
        },
    )

    private lazy var oneTimeView: UIStackView = Self.commonStack()

    private func renderOneTime(oldState: State?, oneTime: State.OneTimeState) {
        renderOneTimePresetsView(oldState: oldState, oneTime: oneTime)
        renderOneTimeCustomAmountTextField(oneTime: oneTime)
        renderOneTimeContinueButton(oneTime: oneTime)

        switch oldState?.loadedDonateMode {
        case .oneTime:
            break
        default:
            oneTimeView.removeAllSubviews()
            oneTimeView.addArrangedSubviews([
                oneTimePresetsView,
                oneTimeCustomAmountTextField,
                oneTimeContinueButton.enclosedInVerticalStackView(isFullWidthButton: true),
            ])
        }
    }

    private func initialRenderOfOneTimePresetRows(preset: DonationUtilities.Preset) {
        oneTimePresetsView.removeAllSubviews()

        var oneTimePresetButtons = [OneTimePresetButton]()

        for (rowIndex, amounts) in preset.amounts.chunked(by: 3).enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = UIDevice.current.isIPhone5OrShorter ? 8 : 14

            let font = UIFont.regularFont(ofSize: UIDevice.current.isIPhone5OrShorter ? 18 : 20)
            for (colIndex, amount) in amounts.enumerated() {
                let button = UIButton(configuration: .bordered())
                button.addAction(
                    UIAction { [weak self] _ in
                        let animationNames = [
                            "boost_smile",
                            "boost_clap",
                            "boost_heart_eyes",
                            "boost_fire",
                            "boost_shock",
                            "boost_rockets",
                        ]
                        let animationIndex = (rowIndex * 3) + colIndex
                        self?.didSelectOneTimeAmount(
                            amount: amount,
                            animationAnchor: button,
                            animationName: animationNames[safe: animationIndex] ?? "boost_fire",
                        )
                    },
                    for: .primaryActionTriggered,
                )
                button.configuration?.title = CurrencyFormatter.format(money: amount)
                button.configuration?.titleTextAttributesTransformer = .defaultFont(font)
                button.configuration?.baseForegroundColor = .Signal.label
                button.configuration?.baseBackgroundColor = .Signal.secondaryGroupedBackground
                button.autoSetDimension(.height, toSize: DonationViewsUtil.amountFieldMinHeight, relation: .greaterThanOrEqual)
                button.enableMultilineLabel()
                button.clipsToBounds = true
                button.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth
#if compiler(>=6.2)
                if #available(iOS 26, *) {
                    button.cornerConfiguration = .capsule()
                } else {
                    button.layer.cornerRadius = Self.cornerRadius
                }
#else
                button.layer.cornerRadius = Self.cornerRadius
#endif

                row.addArrangedSubview(button)

                oneTimePresetButtons.append(.init(amount: amount, view: button))
            }

            oneTimePresetsView.addArrangedSubview(row)
        }

        self.oneTimePresetButtons = oneTimePresetButtons
    }

    private func renderOneTimePresetsView(oldState: State?, oneTime: State.OneTimeState) {
        if oldState?.loadedDonateMode != .oneTime || oldState?.oneTime?.selectedCurrencyCode != oneTime.selectedCurrencyCode {
            guard let preset = oneTime.selectedPreset else {
                owsFail("[Donations] It should be impossible to select a currency code without a preset")
            }
            initialRenderOfOneTimePresetRows(preset: preset)
        }

        let selectedPresetAmount: FiatMoney?
        switch oneTime.selectedAmount {
        case .nothingSelected, .choseCustomAmount:
            selectedPresetAmount = nil
        case let .selectedPreset(amount):
            selectedPresetAmount = amount
        }

        for button in oneTimePresetButtons {
            let selected = button.amount == selectedPresetAmount
            button.view.layer.borderColor = selected ? Self.selectedColor : Self.bubbleBackgroundColor
        }
    }

    private func renderOneTimeCustomAmountTextField(oneTime: State.OneTimeState) {
        switch oneTime.selectedAmount {
        case .nothingSelected, .selectedPreset:
            oneTimeCustomAmountTextField.text = nil
            oneTimeCustomAmountTextField.resignFirstResponder()
            oneTimeCustomAmountTextField.layer.borderColor = Self.bubbleBackgroundColor
        case let .choseCustomAmount(amount):
            oneTimeCustomAmountTextField.setCurrencyCode(amount.currencyCode)
            oneTimeCustomAmountTextField.layer.borderColor = Self.selectedColor
            scrollView.scrollIntoView(subview: oneTimeCustomAmountTextField)
        }
    }

    private func renderOneTimeContinueButton(oneTime: State.OneTimeState) {
        oneTimeContinueButton.isEnabled = {
            switch oneTime.selectedAmount {
            case .nothingSelected:
                return false
            case .selectedPreset:
                return true
            case let .choseCustomAmount(amount):
                return amount.value > 0
            }
        }()
    }

    // MARK: - Monthly

    private var monthlySubscriptionLevelViews = [MonthlySubscriptionLevelView]()

    private lazy var monthlySubscriptionLevelsView: UIStackView = {
        let result = Self.commonStack()
        result.spacing = 10
        return result
    }()

    private lazy var monthlyButtonsView = UIStackView.verticalButtonStack(buttons: [])

    private lazy var monthlyView: UIStackView = Self.commonStack()

    private func renderMonthly(oldState: State?, monthly: State.MonthlyState) {
        renderMonthlySubscriptionLevelsView(oldState: state, monthly: monthly)
        renderMonthlyButtonsView(monthly: monthly)

        switch oldState?.loadedDonateMode {
        case .monthly:
            break
        default:
            monthlyView.removeAllSubviews()
            monthlyView.addArrangedSubviews([
                monthlySubscriptionLevelsView,
                monthlyButtonsView,
            ])
        }
    }

    private func initialRenderOfMonthlySubscriptionLevelViews(monthly: State.MonthlyState) {
        monthlySubscriptionLevelsView.removeAllSubviews()

        let animationNames = ["boost_fire", "boost_shock", "boost_rockets"]
        monthlySubscriptionLevelViews = monthly.subscriptionLevels
            .enumerated()
            .map { index, subscriptionLevel in
                MonthlySubscriptionLevelView(
                    subscriptionLevel: subscriptionLevel,
                    animationName: animationNames[safe: index] ?? "boost_fire",
                )
            }

        for view in monthlySubscriptionLevelViews {
            let tap = UITapGestureRecognizer(
                target: self,
                action: #selector(didTapMonthlySubscriptionLevelView),
            )
            view.addGestureRecognizer(tap)
            monthlySubscriptionLevelsView.addArrangedSubview(view)
        }
    }

    private func renderMonthlySubscriptionLevelsView(oldState: State?, monthly: State.MonthlyState) {
        let renderedSubscriptionLevels = monthlySubscriptionLevelViews.map(\.subscriptionLevel)
        if oldState?.monthly?.subscriptionLevels != renderedSubscriptionLevels {
            initialRenderOfMonthlySubscriptionLevelViews(monthly: monthly)
        }

        for subscriptionLevelView in monthlySubscriptionLevelViews {
            subscriptionLevelView.render(
                currencyCode: monthly.selectedCurrencyCode,
                currentSubscription: monthly.currentSubscription,
                selectedSubscriptionLevel: monthly.selectedSubscriptionLevel,
            )
        }
    }

    private func renderMonthlyButtonsView(monthly: State.MonthlyState) {
        monthlyButtonsView.removeAllSubviews()
        monthlyButtonsView.addArrangedSubviews(buttonsForMonthlyView(monthly: monthly))
    }

    private func buttonsForMonthlyView(monthly: State.MonthlyState) -> [UIButton] {
        func isDifferentSubscriptionLevelSelected(_ currentSubscription: Subscription?) -> Bool {
            guard let currentSubscription else { return false }

            if currentSubscription.amount.currencyCode != monthly.selectedCurrencyCode {
                return true
            }

            if
                let selectedSubscriptionLevel = monthly.selectedSubscriptionLevel,
                currentSubscription.level != selectedSubscriptionLevel.level
            {
                return true
            }

            return false
        }

        func doomedContinueButton(errorAlertTitle: String, errorAlertMessage: String, isEnabled: Bool) -> UIButton {
            let doomedContinueButton = UIButton(
                configuration: .largePrimary(title: CommonStrings.continueButton),
                primaryAction: UIAction { [weak self] _ in
                    self?.showError(title: errorAlertTitle, errorAlertMessage)
                },
            )
            doomedContinueButton.isEnabled = isEnabled

            return doomedContinueButton
        }

        func cancelSubscriptionButton(block: @escaping () -> Void) -> UIButton {
            return UIButton(
                configuration: .largeSecondary(title: OWSLocalizedString(
                    "SUSTAINER_VIEW_CANCEL_SUBSCRIPTION",
                    comment: "Sustainer view Cancel Subscription button title",
                )),
                primaryAction: UIAction { _ in
                    block()
                },
            )
        }

        if monthly.pendingIDEALSubscription != nil {
            let title = OWSLocalizedString(
                "DONATE_SCREEN_ERROR_TITLE_BANK_PAYMENT_AWAITING_AUTHORIZATION",
                comment: "Title for an alert presented when the user tries to make a donation, but already has a donation that is currently awaiting authorization.",
            )

            let message = OWSLocalizedString(
                "DONATE_SCREEN_ERROR_MESSAGE_BANK_PAYMENT_AWAITING_AUTHORIZATION",
                comment: "Message in an alert presented when the user tries to update their recurring donation, but already has a recurring donation that is currently awaiting authorization.",
            )

            return [
                doomedContinueButton(
                    errorAlertTitle: title,
                    errorAlertMessage: message,
                    isEnabled: true,
                ),
            ]
        } else if
            let currentSubscription = monthly.currentSubscription,
            let paymentMethodIfPaymentProcessing = monthly.paymentMethodIfPaymentProcessing
        {
            let title: String
            let message: String

            switch paymentMethodIfPaymentProcessing {
            case .applePay, .creditOrDebitCard, .paypal:
                title = OWSLocalizedString(
                    "DONATE_SCREEN_ERROR_TITLE_YOU_HAVE_A_PAYMENT_PROCESSING",
                    comment: "Title for an alert presented when the user tries to make a donation, but already has a donation that is currently processing via non-bank payment.",
                )
                message = OWSLocalizedString(
                    "DONATE_SCREEN_ERROR_MESSAGE_PLEASE_WAIT_BEFORE_UPDATING_YOUR_SUBSCRIPTION",
                    comment: "Message in an alert presented when the user tries to update their recurring donation, but already has a recurring donation that is currently processing via non-bank payment.",
                )
            case .sepa, .ideal:
                title = OWSLocalizedString(
                    "DONATE_SCREEN_ERROR_TITLE_BANK_PAYMENT_YOU_HAVE_A_DONATION_PENDING",
                    comment: "Title for an alert presented when the user tries to make a donation, but already has a donation that is currently processing via bank payment.",
                )
                message = OWSLocalizedString(
                    "DONATE_SCREEN_ERROR_MESSAGE_BANK_PAYMENT_PLEASE_WAIT_BEFORE_UPDATING_YOUR_SUBSCRIPTION",
                    comment: "Message in an alert presented when the user tries to update their recurring donation, but already has a recurring donation that is currently processing via bank payment.",
                )
            }

            let continueButton = doomedContinueButton(
                errorAlertTitle: title,
                errorAlertMessage: message,
                isEnabled: isDifferentSubscriptionLevelSelected(monthly.currentSubscription),
            )
            let cancelButton = cancelSubscriptionButton { [weak self] in
                guard let self else { return }

                switch currentSubscription.status {
                case .active:
                    OWSActionSheets.showConfirmationAlert(
                        title: OWSLocalizedString(
                            "DONATE_SCREEN_CANCEL_SUBSCRIPTION_PENDING_DONATION_WARNING_TITLE",
                            comment: "Title for an action sheet shown when the user tries to cancel their donation subscription, but they have a pending donation.",
                        ),
                        message: OWSLocalizedString(
                            "DONATE_SCREEN_CANCEL_SUBSCRIPTION_PENDING_DONATION_WARNING_MESSAGE",
                            comment: "Message for an action sheet shown when the user tries to cancel their donation subscription, but they have a pending donation.",
                        ),
                        proceedTitle: CommonStrings.continueButton,
                        proceedAction: { [weak self] _ in
                            guard let self else { return }
                            didTapToCancelSubscription()
                        },
                    )
                case .pastDue:
                    /// If the user's subscription is `.pastDue`, it means a renewal
                    /// payment failed and the payment processor is auto-retrying
                    /// the renewal payment. Give the user a chance to bail out by
                    /// canceling their subscription, which will stop the retries.
                    didTapToCancelSubscription()
                case .canceled, .unrecognized:
                    /// It's not clear how this happened, but something is wrong
                    /// and we should let users clear their local state.
                    owsFailDebug("Have a payment processing, but have unexpected subscription status \(currentSubscription.status)")
                    didTapToCancelSubscription()
                }
            }

            return [continueButton, cancelButton]
        } else if let currentSubscription = monthly.currentSubscription {
            let cancelButton = cancelSubscriptionButton { [weak self] in
                self?.didTapToCancelSubscription()
            }

            if
                currentSubscription.active,
                Self.canMakeNewDonations(forDonateMode: .monthly)
            {
                let updateTitle = OWSLocalizedString(
                    "DONATE_SCREEN_UPDATE_MONTHLY_SUBSCRIPTION_BUTTON",
                    comment: "On the donation screen, if you already have a subscription, you'll see a button to update your subscription. This is the text on that button.",
                )
                let updateButton = UIButton(
                    configuration: .largePrimary(title: updateTitle),
                    primaryAction: UIAction { [weak self] _ in
                        self?.didTapToUpdateMonthlyDonation()
                    },
                )
                updateButton.isEnabled = isDifferentSubscriptionLevelSelected(currentSubscription)

                return [updateButton, cancelButton]
            } else {
                return [cancelButton]
            }
        } else {
            let continueButton = UIButton(
                configuration: .largePrimary(title: CommonStrings.continueButton),
                primaryAction: UIAction { [weak self] _ in
                    self?.didTapToStartNewMonthlyDonation()
                },
            )
            return [continueButton]
        }
    }
}

// MARK: - Donation hero delegate

extension DonateViewController: DonationHeroViewDelegate {
    func present(readMoreSheet: DonationReadMoreSheetViewController) {
        present(readMoreSheet, animated: true)
    }
}

// MARK: - One-Time donation custom amount field delegate

extension DonateViewController: OneTimeDonationCustomAmountTextFieldDelegate {
    func oneTimeDonationCustomAmountTextFieldStateDidChange(_ textField: OneTimeDonationCustomAmountTextField) {
        self.state = self.state.selectOneTimeAmount(.choseCustomAmount(amount: textField.amount))
    }
}

// MARK: - UIScrollView

private extension UIScrollView {
    /// Scroll a subview into view.
    ///
    /// Only meant for use on this screen. Your mileage may vary if used elsewhere.
    func scrollIntoView(subview: UIView) {
        guard let superview = subview.superview else { return }

        let currentVisibleTop = contentOffset.y
        let currentVisibleBottom = currentVisibleTop + bounds.height

        let subviewTop = superview.convert(subview.frame.topLeft, to: self).y
        let subviewBottom = superview.convert(subview.frame.bottomLeft, to: self).y

        let newY: CGFloat
        if subviewTop < currentVisibleTop {
            newY = subviewTop
        } else if subviewBottom > currentVisibleBottom {
            newY = subviewBottom - bounds.height
        } else {
            return
        }

        setContentOffset(.init(x: contentOffset.x, y: newY), animated: true)
    }
}
