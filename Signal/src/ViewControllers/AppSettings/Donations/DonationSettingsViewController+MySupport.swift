//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalMessaging
import SignalUI

private enum MySupportErrorState: UserErrorDescriptionProvider {
    case previouslyActiveSubscriptionLapsed(Subscription.ChargeFailure)
    case paymentProcessing(paymentMethod: DonationPaymentMethod?)
    case paymentFailed

    var localizedDescription: String {
        switch self {
        case .previouslyActiveSubscriptionLapsed:
            return OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_MONTHLY_DONATION_CANCELED",
                comment: "A label describing a recurring monthly donation that used to be active, but has now been canceled because it failed to renew."
            )
        case .paymentProcessing(paymentMethod: .sepa):
            return OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_DONATION_PENDING",
                comment: "A label describing a donation payment that was made via bank transfer, which is still processing and has not completed."
            )
        case .paymentProcessing:
            return OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_PROCESSING_PAYMENT",
                comment: "A label describing a donation payment that was made by a method other than bank transfer (such as by credit card), which is still processing and has not completed."
            )
        case .paymentFailed:
            return OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_ERROR_PROCESSING_PAYMENT",
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
            section.add(mySupportRecurringSubscriptionTableItem(
                subscription: subscription,
                subscriptionBadge: subscriptionLevel?.badge,
                previouslyHadActiveSubscription: previouslyHadActiveSubscription,
                receiptCredentialRequestError: receiptCredentialRequestError
            ))
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
    ) -> OWSTableItem {
        let errorState: MySupportErrorState? = {
            if let errorState = subscription.errorStateIfIsPaymentProcessing {
                if previouslyHadActiveSubscription {
                    logger.info("Renewal of recurring subscription has payment processing.")
                } else {
                    logger.info("First-time recurring subscription has payment processing.")
                }

                return errorState
            } else if let chargeFailure = subscription.chargeFailure {
                if previouslyHadActiveSubscription {
                    logger.warn("Renewal of recurring subscription had payment failure!")
                    return .previouslyActiveSubscriptionLapsed(chargeFailure)
                } else {
                    logger.warn("First-time recurring subscription had payment failure!")
                    return .paymentFailed
                }
            } else if let receiptCredentialRequestError {
                // Errors pertaining to payment processing or failed should have
                // been caught above, so ending up here probably indicates the
                // subscription isn't in a bad state but we still had an error
                // with the receipt credential request. That would in turn mean
                // that we charged the user, but failed to get them a badge.
                //
                // It's also possible the payment was processing the last time
                // we ran the receipt credential request job, and we haven't run
                // the job again since the payment finished processing.
                owsAssertDebug(receiptCredentialRequestError.errorCode == .paymentStillProcessing)

                logger.warn("Recurring subscription with receipt credential request error! \(receiptCredentialRequestError)")
                return receiptCredentialRequestError.mySupportErrorState
            } else {
                owsAssertDebug(subscription.active)

                logger.info("Recurring subscription in good state.")
                return nil
            }
        }()

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
                return errorState.localizedDescription
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
                case let .previouslyActiveSubscriptionLapsed(chargeFailure):
                    self.presentRecurringSubscriptionLapsedActionSheet()
                case let .paymentProcessing(paymentMethod):
                    self.presentPaymentProcessingActionSheet(paymentMethod: paymentMethod)
                case .paymentFailed:
                    self.presentPaymentFailedActionSheet(errorMode: .recurringSubscription)
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

        let errorState = receiptCredentialRequestError.mySupportErrorState

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
                    subtitle: errorState.localizedDescription,
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
                    self.presentPaymentProcessingActionSheet(paymentMethod: paymentMethod)
                case .paymentFailed:
                    self.presentPaymentFailedActionSheet(errorMode: .oneTimeBoost)
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

            actionSheet.addAction(OWSActionSheets.okayAction)
            actionSheet.addAction(OWSActionSheets.learnMoreUrlAction(
                url: SupportConstants.donationPendingLearnMoreURL
            ))
        }

        self.presentActionSheet(actionSheet, animated: true)
    }

    private func presentPaymentFailedActionSheet(
        errorMode: SubscriptionReceiptCredentialResultStore.Mode
    ) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_PAYMENT_FAILED_ALERT_TITLE",
                comment: "Title for a sheet explaining that a payment failed."
            ),
            message: OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_PAYMENT_FAILED_ALERT_MESSAGE",
                comment: "Message shown in a sheet explaining that a payment failed."
            )
        )

        actionSheet.addAction(okayAndClearErrorActionSheetAction(
            errorMode: errorMode
        ))
        actionSheet.addAction(OWSActionSheets.learnMoreUrlAction(
            url: SupportConstants.badgeExpirationLearnMoreURL
        ))
        self.presentActionSheet(actionSheet, animated: true)
    }

    private func presentRecurringSubscriptionLapsedActionSheet() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_RECURRING_SUBSCRIPTION_LAPSED_TITLE",
                comment: "Title for a sheet explaining that the user's recurring subscription has ended because payment failed."
            ),
            message: OWSLocalizedString(
                "DONATION_SETTINGS_MY_SUPPORT_RECURRING_SUBSCRIPTION_LAPSED_ALERT_MESSAGE",
                comment: "Message shown in a sheet explaining that the user's recurring subscription has ended because payment failed."
            )
        )

        actionSheet.addAction(okayAndClearErrorActionSheetAction(
            errorMode: .recurringSubscription
        ))
        actionSheet.addAction(OWSActionSheets.learnMoreUrlAction(
            url: SupportConstants.badgeExpirationLearnMoreURL
        ))
        self.presentActionSheet(actionSheet, animated: true)
    }

    private func okayAndClearErrorActionSheetAction(
        errorMode: SubscriptionReceiptCredentialResultStore.Mode
    ) -> ActionSheetAction {
        return ActionSheetAction(
            title: CommonStrings.okButton,
            style: .default
        ) { _ in
            self.databaseStorage.write { tx in
                DependenciesBridge.shared.subscriptionReceiptCredentialResultStore
                    .clearRequestError(errorMode: errorMode, tx: tx.asV2Write)
            }

            // Not ideal, because this makes network requests. However, this
            // should be rare, and doing it this way avoids us needing to add
            // methods for updating the state outside the normal loading flow.
            self.loadAndUpdateState()
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
    var mySupportErrorState: MySupportErrorState {
        guard case .paymentStillProcessing = errorCode else {
            // This isn't quite the right thing to do, since the payment isn't
            // the thing that failed. However, it should be super rare for us to
            // get into this state – we could alternatively add a "generic
            // error" case for us to fall back on.
            return .paymentFailed
        }

        return .paymentProcessing(paymentMethod: paymentMethod)
    }
}

private extension OWSActionSheets {
    static func learnMoreUrlAction(url: URL) -> ActionSheetAction {
        return ActionSheetAction(
            title: CommonStrings.learnMore,
            handler: { _ in
                UIApplication.shared.open(url)
            }
        )
    }
}
