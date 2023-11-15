//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SafariServices

import SignalServiceKit
import SignalMessaging
import SignalUI

private enum MySupportErrorState {
    case paymentProcessing(paymentMethod: DonationPaymentMethod?)

    case previouslyActiveSubscriptionLapsed(
        chargeFailureCode: String?,
        paymentMethod: DonationPaymentMethod?
    )

    case paymentFailed(
        chargeFailureCode: String?,
        paymentMethod: DonationPaymentMethod?
    )

    var tableCellSubtitle: String {
        switch self {
        case .paymentProcessing(paymentMethod: .sepa):
            return OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_TABLE_CELL_SUBTITLE_BANK_PAYMENT_PROCESSING",
                comment: "A label describing a donation payment that was made via bank transfer, which is still processing and has not completed."
            )
        case .paymentProcessing:
            return OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_TABLE_CELL_SUBTITLE_NON_BANK_PAYMENT_PROCESSING",
                comment: "A label describing a donation payment that was made by a method other than bank transfer (such as by credit card), which is still processing and has not completed."
            )
        case .previouslyActiveSubscriptionLapsed:
            return OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_TABLE_CELL_SUBTITLE_SUBSCRIPTION_LAPSED",
                comment: "A label describing a recurring monthly donation that used to be active, but has now been canceled because it failed to renew."
            )
        case .paymentFailed:
            return OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_TABLE_CELL_SUBTITLE_PAYMENT_FAILED",
                comment: "A label describing a donation payment that has failed to process."
            )
        }
    }

    var shouldShowErrorIcon: Bool {
        switch self {
        case .previouslyActiveSubscriptionLapsed, .paymentFailed: return true
        case .paymentProcessing: return false
        }
    }
}

extension DonationSettingsViewController {
    private var logger: PrefixedLogger { PrefixedLogger(prefix: "[DSVC]") }

    func mySupportSection(
        subscriptionStatus: State.SubscriptionStatus,
        profileBadgeLookup: ProfileBadgeLookup,
        oneTimeBoostReceiptCredentialRequestError: SubscriptionReceiptCredentialRequestError?,
        hasAnyBadges: Bool
    ) -> OWSTableSection? {
        let section = OWSTableSection(title: OWSLocalizedString(
            "DONATION_VIEW_MY_SUPPORT_TITLE",
            comment: "Title for the 'my support' section in the donation view"
        ))

        switch subscriptionStatus {
        case .loadFailed:
            section.add(.label(withText: OWSLocalizedString(
                "DONATION_VIEW_LOAD_FAILED",
                comment: "Text that's shown when the donation view fails to load data, probably due to network failure"
            )))
        case .noSubscription:
            break
        case let .hasSubscription(
            subscription,
            subscriptionLevel,
            previouslyHadActiveSubscription,
            receiptCredentialRequestError
        ):
            if let recurringSubscriptionTableItem = mySupportRecurringSubscriptionTableItem(
                subscription: subscription,
                subscriptionBadge: subscriptionLevel?.badge,
                previouslyHadActiveSubscription: previouslyHadActiveSubscription,
                receiptCredentialRequestError: receiptCredentialRequestError
            ) {
                section.add(recurringSubscriptionTableItem)
            }
        }

        if let oneTimeBoostItem = mySupportOneTimeBoostTableItem(
            boostBadge: profileBadgeLookup.boostBadge,
            receiptCredentialRequestError: oneTimeBoostReceiptCredentialRequestError
        ) {
            section.add(oneTimeBoostItem)
        }

        if hasAnyBadges {
            section.add(.disclosureItem(
                icon: .donateBadges,
                name: OWSLocalizedString("DONATION_VIEW_MANAGE_BADGES", comment: "Title for the 'Badges' button on the donation screen"),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "badges"),
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    let vc = BadgeConfigurationViewController(fetchingDataFromLocalProfileWithDelegate: self)
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }

        guard section.itemCount > 0 else {
            return nil
        }

        return section
    }

    private func mySupportRecurringSubscriptionTableItem(
        subscription: Subscription,
        subscriptionBadge: ProfileBadge?,
        previouslyHadActiveSubscription: Bool,
        receiptCredentialRequestError: SubscriptionReceiptCredentialRequestError?
    ) -> OWSTableItem? {
        let errorState: MySupportErrorState?

        if let receiptCredentialRequestError {
            logger.warn("Recurring subscription with receipt credential request error! \(receiptCredentialRequestError)")

            errorState = receiptCredentialRequestError.mySupportErrorState(
                previouslyHadActiveSubscription: previouslyHadActiveSubscription
            )
        } else {
            if subscription.isPaymentProcessing {
                logger.warn("Subscription is processing, but we don't have a receipt credential request error about it!")
            } else if subscription.chargeFailure != nil {
                logger.warn("Subscription has charge failure, but we don't have a receipt credential request error about it!")
            }

            switch subscription.status {
            case .active:
                errorState = nil
            case .pastDue:
                // Don't treat a subscription with a failed renewal as failed
                // for the purposes of this view – it may yet succeed!
                errorState = nil
            case .canceled:
                logger.warn("Subscription is canceled, but we don't have a receipt credential request error about it!")
                return nil
            case
                    .incomplete,
                    .incompleteExpired,
                    .trialing,
                    .unpaid,
                    .unknown:
                // Not sure what's going on here, but we don't want to show a
                // subscription with an unexpected status.
                logger.error("Unexpected subscription status: \(subscription.status)")
                return nil
            }
        }

        let pricingTitle: String = {
            let pricingFormat = OWSLocalizedString(
                "SUSTAINER_VIEW_PRICING",
                comment: "Pricing text for sustainer view badges, embeds {{price}}"
            )
            let currencyString = DonationUtilities.format(money: subscription.amount)

            return String(format: pricingFormat, currencyString)
        }()

        let statusSubtitle: String = {
            if let errorState {
                return errorState.tableCellSubtitle
            }

            let renewalFormat = OWSLocalizedString(
                "SUSTAINER_VIEW_RENEWAL",
                comment: "Renewal date text for sustainer view level, embeds {{renewal date}}"
            )

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let dateArg = dateFormatter.string(from: Date(
                timeIntervalSince1970: subscription.endOfCurrentPeriod
            ))

            return String(format: renewalFormat, dateArg)
        }()

        let errorIconView: UIView? = {
            if let errorState, errorState.shouldShowErrorIcon {
                return mySupportErrorIconView()
            }

            return nil
        }()

        return OWSTableItem(
            customCellBlock: { () -> UITableViewCell in
                return OWSTableItem.buildImageCell(
                    image: subscriptionBadge?.assets?.universal160,
                    itemName: pricingTitle,
                    subtitle: statusSubtitle,
                    accessoryType: .disclosureIndicator,
                    accessoryContentView: errorIconView
                )
            },
            actionBlock: { [weak self] () -> Void in
                guard let self else { return }

                guard let errorState else {
                    self.showDonateViewController(preferredDonateMode: .monthly)
                    return
                }

                switch errorState {
                case let .previouslyActiveSubscriptionLapsed(chargeFailureCode, paymentMethod):
                    self.presentRecurringSubscriptionLapsedActionSheet(
                        chargeFailureCode: chargeFailureCode,
                        paymentMethod: paymentMethod
                    )
                case let .paymentProcessing(paymentMethod):
                    self.presentPaymentProcessingActionSheet(
                        paymentMethod: paymentMethod
                    )
                case let .paymentFailed(chargeFailureCode, paymentMethod):
                    self.presentDonationFailedActionSheet(
                        chargeFailureCode: chargeFailureCode,
                        paymentMethod: paymentMethod,
                        preferredDonateMode: .monthly
                    )
                }
            }
        )
    }

    private func mySupportOneTimeBoostTableItem(
        boostBadge: ProfileBadge?,
        receiptCredentialRequestError: SubscriptionReceiptCredentialRequestError?
    ) -> OWSTableItem? {
        guard let receiptCredentialRequestError else {
            // We don't show anything for one-time boosts unless there's an
            // error.
            return nil
        }

        guard let amount = receiptCredentialRequestError.amount else {
            owsFailBeta("We never persisted these without an amount for one-time boosts. How did we get here?")
            return nil
        }

        logger.info("Showing boost error. \(receiptCredentialRequestError)")

        // Previous active subscription is irrelevant for one-time boosts.
        let errorState = receiptCredentialRequestError.mySupportErrorState(
            previouslyHadActiveSubscription: false
        )

        return OWSTableItem(
            customCellBlock: { [weak self] () -> UITableViewCell in
                guard let self else { return UITableViewCell() }

                let pricingTitle: String = {
                    let pricingFormat = OWSLocalizedString(
                        "DONATION_SETTINGS_ONE_TIME_AMOUNT_FORMAT",
                        comment: "A string describing the amount and currency of a one-time payment. Embeds {{ the amount, formatted as a currency }}."
                    )

                    return String(
                        format: pricingFormat,
                        DonationUtilities.format(money: amount)
                    )
                }()

                return OWSTableItem.buildImageCell(
                    image: boostBadge?.assets?.universal160,
                    itemName: pricingTitle,
                    subtitle: errorState.tableCellSubtitle,
                    accessoryType: .disclosureIndicator,
                    accessoryContentView: errorState.shouldShowErrorIcon ? self.mySupportErrorIconView() : nil
                )
            },
            actionBlock: { [weak self] () -> Void in
                guard let self else { return }

                switch errorState {
                case .previouslyActiveSubscriptionLapsed:
                    owsFail("Impossible for one-time boost!")
                case let .paymentProcessing(paymentMethod):
                    self.presentPaymentProcessingActionSheet(
                        paymentMethod: paymentMethod
                    )
                case let .paymentFailed(chargeFailureCode, paymentMethod):
                    self.presentDonationFailedActionSheet(
                        chargeFailureCode: chargeFailureCode,
                        paymentMethod: paymentMethod,
                        preferredDonateMode: .oneTime
                    )
                }
            }
        )
    }

    private func presentPaymentProcessingActionSheet(
        paymentMethod: DonationPaymentMethod?
    ) {
        let actionSheet: ActionSheetController

        switch paymentMethod {
        case nil, .applePay, .creditOrDebitCard, .paypal:
            actionSheet = DonationViewsUtil.nonBankPaymentStillProcessingActionSheet()
        case .sepa:
            actionSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_BANK_PAYMENT_PROCESSING_TITLE",
                    comment: "Title for an alert explaining that a one-time payment made via bank transfer is being processed."
                ),
                message: OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_BANK_PAYMENT_PROCESSING_MESSAGE",
                    comment: "Message for an alert explaining that a one-time payment made via bank transfer is being processed."
                )
            )

            actionSheet.addAction(ActionSheetAction(
                title: CommonStrings.learnMore,
                handler: { [weak self] _ in
                    guard let self else { return }

                    self.present(
                        SFSafariViewController(url: SupportConstants.donationPendingLearnMoreURL),
                        animated: true
                    )
                }
            ))
            actionSheet.addAction(OWSActionSheets.okayAction)
        }

        self.presentActionSheet(actionSheet, animated: true)
    }

    private func presentDonationFailedActionSheet(
        chargeFailureCode: String?,
        paymentMethod: DonationPaymentMethod?,
        preferredDonateMode: DonateViewController.DonateMode
    ) {
        let actionSheetMessage: String = {
            let messageFormat: String = OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_DONATION_FAILED_ALERT_MESSAGE_FORMAT",
                comment: "Message shown in a sheet explaining that the user's donation has failed because payment failed. Embeds {{ a specific, already-localized string describing the payment failure reason }}."
            )

            let (chargeFailureString, _) = DonationViewsUtil.localizedDonationFailure(
                chargeErrorCode: chargeFailureCode,
                paymentMethod: paymentMethod
            )

            return String(format: messageFormat, chargeFailureString)
        }()

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_DONATION_FAILED_ALERT_TITLE",
                comment: "Title for a sheet explaining that a payment failed."
            ),
            message: actionSheetMessage
        )

        actionSheet.addAction(showDonateAndClearErrorAction(
            title: .tryAgain,
            preferredDonateMode: preferredDonateMode
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)

        self.presentActionSheet(actionSheet, animated: true)
    }

    private func presentRecurringSubscriptionLapsedActionSheet(
        chargeFailureCode: String?,
        paymentMethod: DonationPaymentMethod?
    ) {
        let actionSheetMessage: String = {
            let messageFormat = OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_RECURRING_SUBSCRIPTION_LAPSED_CHARGE_FAILURE_ALERT_MESSAGE_FORMAT",
                comment: "Message shown in a sheet explaining that the user's recurring subscription has ended because payment failed. Embeds {{ a specific, already-localized string describing the failure reason }}."
            )

            let (chargeFailureString, _) = DonationViewsUtil.localizedDonationFailure(
                chargeErrorCode: chargeFailureCode,
                paymentMethod: paymentMethod
            )

            return String(format: messageFormat, chargeFailureString)
        }()

        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_RECURRING_SUBSCRIPTION_LAPSED_TITLE",
                comment: "Title for a sheet explaining that the user's recurring subscription has ended because payment failed."
            ),
            message: actionSheetMessage
        )

        actionSheet.addAction(showDonateAndClearErrorAction(
            title: .renewSubscription,
            preferredDonateMode: .monthly
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)

        self.presentActionSheet(actionSheet, animated: true)
    }

    private enum ShowDonateActionTitle {
        case renewSubscription
        case tryAgain

        var localizedTitle: String {
            switch self {
            case .renewSubscription:
                return OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_ACTION_SHEET_ACTION_TITLE_RENEW_SUBSCRIPTION",
                    comment: "Title for an action in an action sheet asking the user to renew a subscription that has failed to renew."
                )
            case .tryAgain:
                return OWSLocalizedString(
                    "DONATION_SETTINGS_MY_SUPPORT_ACTION_SHEET_ACTION_TITLE_TRY_AGAIN",
                    comment: "Title for an action in an action sheet asking the user to try again, in reference to a donation that failed."
                )
            }
        }
    }

    private func showDonateAndClearErrorAction(
        title: ShowDonateActionTitle,
        preferredDonateMode: DonateViewController.DonateMode
    ) -> ActionSheetAction {
        return ActionSheetAction(title: title.localizedTitle) { _ in
            self.databaseStorage.write { tx in
                switch preferredDonateMode {
                case .oneTime:
                    DependenciesBridge.shared.subscriptionReceiptCredentialResultStore
                        .clearRequestError(errorMode: .oneTimeBoost, tx: tx.asV2Write)
                case .monthly:
                    DependenciesBridge.shared.subscriptionReceiptCredentialResultStore
                        .clearRequestErrorForAnyRecurringSubscription(tx: tx.asV2Write)
                }
            }

            // Not ideal, because this makes network requests. However, this
            // should be rare, and doing it this way avoids us needing to add
            // methods for updating the state outside the normal loading flow.
            self.loadAndUpdateState().done(on: DispatchQueue.main) { [weak self] in
                guard let self else { return }
                self.showDonateViewController(preferredDonateMode: preferredDonateMode)
            }
        }
    }

    private func mySupportErrorIconView() -> UIView {
        let imageView = UIImageView.withTemplateImageName(
            "error-circle",
            tintColor: .ows_accentRed
        )
        imageView.autoPinToSquareAspectRatio()

        return imageView
    }
}

private extension Subscription {
    /// If this subscription has a payment processing, returns an error state
    /// describing that fact.
    var errorStateIfIsPaymentProcessing: MySupportErrorState? {
        if isPaymentProcessing {
            return .paymentProcessing(paymentMethod: paymentMethod)
        }

        return nil
    }
}

private extension SubscriptionReceiptCredentialRequestError {
    func mySupportErrorState(
        previouslyHadActiveSubscription: Bool
    ) -> MySupportErrorState {
        switch errorCode {
        case .paymentFailed:
            if previouslyHadActiveSubscription {
                return .previouslyActiveSubscriptionLapsed(
                    chargeFailureCode: chargeFailureCodeIfPaymentFailed,
                    paymentMethod: paymentMethod
                )
            }

            return .paymentFailed(
                chargeFailureCode: chargeFailureCodeIfPaymentFailed,
                paymentMethod: paymentMethod
            )
        case .paymentStillProcessing:
            return .paymentProcessing(paymentMethod: paymentMethod)
        case
                .localValidationFailed,
                .serverValidationFailed,
                .paymentNotFound,
                .paymentIntentRedeemed:
            // This isn't quite the right thing to do, since the payment isn't
            // the thing that failed. However, it should be super rare for us to
            // get into this state – we could alternatively add a "generic
            // error" case for us to fall back on.
            return .paymentFailed(
                chargeFailureCode: nil,
                paymentMethod: paymentMethod
            )
        }
    }
}
