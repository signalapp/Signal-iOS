//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsDeactivateViewController: OWSViewController {

    private var paymentBalance: PaymentBalance {
        didSet {
            updateBalance()
        }
    }

    private let balanceLabel = UILabel()
    private var observations = [NotificationCenter.Observer]()

    init(paymentBalance: PaymentBalance) {
        owsAssertDebug(paymentBalance.amount.isValidAmount(canBeEmpty: false))

        self.paymentBalance = paymentBalance
        super.init()
    }

    deinit {
        for observation in observations {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_DEACTIVATE_TITLE",
            comment: "Label for the 'de-activate payments' view of the app settings.",
        )

        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.didTapDismiss()
        }

        view.backgroundColor = .Signal.groupedBackground

        balanceLabel.font = UIFont.systemFont(ofSize: 54)
        balanceLabel.textColor = .Signal.label
        balanceLabel.adjustsFontSizeToFitWidth = true
        balanceLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "SETTINGS_PAYMENTS_REMAINING_BALANCE",
            comment: "Label for the current balance in the 'deactivate payments' settings.",
        )
        subtitleLabel.font = .dynamicTypeBodyClamped
        subtitleLabel.textColor = .Signal.secondaryLabel
        subtitleLabel.textAlignment = .center

        let balanceStack = UIStackView(arrangedSubviews: [balanceLabel, subtitleLabel])
        balanceStack.axis = .vertical
        balanceStack.spacing = 8
        balanceStack.alignment = .center

        let explanationLabel = PaymentsUI.buildTextWithLearnMoreLinkTextView(
            text: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_WITH_BALANCE_EXPLANATION",
                comment: "Explanation of the 'deactivate payments with balance' process in the 'deactivate payments' settings.",
            ),
            font: .dynamicTypeSubheadlineClamped,
            learnMoreUrl: URL.Support.Payments.deactivate,
        )

        let transferBalanceButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_AFTER_TRANSFERRING_BALANCE",
                comment: "Label for 'transfer balance' button in the 'deactivate payments' settings.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapTransferBalanceButton()
            },
        )

        let deactivateImmediatelyButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_WITHOUT_TRANSFERRING_BALANCE",
                comment: "Label for 'deactivate payments without transferring balance' button in the 'deactivate payments' settings.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapDeactivateImmediatelyButton()
            },
        )
        deactivateImmediatelyButton.configuration?.baseForegroundColor = .Signal.red

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                balanceStack,
                explanationLabel,
                .vStretchingSpacer(),
                [transferBalanceButton, deactivateImmediatelyButton].enclosedInVerticalStackView(isFullWidthButtons: true),
            ],
            isScrollable: true,
        )
        stackView.setCustomSpacing(44, after: balanceStack)

        addObservations()
        updateBalance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
    }

    private func addObservations() {
        observations.append(NotificationCenter.default.addObserver(
            name: PaymentsConstants.arePaymentsEnabledDidChange,
        ) { [weak self] _ in
            self?.arePaymentsEnabledDidChange()
        })
        observations.append(NotificationCenter.default.addObserver(
            name: PaymentsImpl.currentPaymentBalanceDidChange,
        ) { [weak self] _ in
            self?.currentPaymentBalanceDidChange()
        })
    }

    private func arePaymentsEnabledDidChange() {
        dismiss(animated: true, completion: nil)
    }

    private func currentPaymentBalanceDidChange() {
        guard
            let currentPaymentBalance = SUIEnvironment.shared.paymentsSwiftRef.currentPaymentBalance,
            currentPaymentBalance.amount.isValidAmount(canBeEmpty: false)
        else {
            // We need to abort the "deactivate payments with outstanding balance"
            // flow if:
            //
            // * The balance becomes unavailable (this should never happen).
            // * The balance becomes zero (this should be extremely rare).
            Logger.warn("Missing or empty balance.")
            dismiss(animated: true, completion: nil)
            return
        }
        paymentBalance = currentPaymentBalance
    }

    private func updateBalance() {
        balanceLabel.attributedText = PaymentsFormat.attributedFormat(
            paymentAmount: paymentBalance.amount,
            isShortForm: false,
        )
    }

    // MARK: - Events

    private func didTapTransferBalanceButton() {
        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            asyncBlock: { modalActivityIndicator in
                do {
                    let transferAmount = try await SUIEnvironment.shared.paymentsSwiftRef.maximumPaymentAmount()
                    modalActivityIndicator.dismiss {
                        guard let navigationController = self.navigationController else {
                            owsFailDebug("Missing navigationController.")
                            return
                        }
                        let view = PaymentsTransferOutViewController(transferAmount: transferAmount)
                        navigationController.pushViewController(view, animated: true)
                    }
                } catch {
                    owsFailDebug("Error: \(error)")

                    modalActivityIndicator.dismiss {
                        OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                            "SETTINGS_PAYMENTS_DEACTIVATION_FAILED",
                            comment: "Error indicating that payments could not be deactivated in the payments settings.",
                        ))
                    }
                }
            },
        )
    }

    private func didTapDeactivateImmediatelyButton() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_WITHOUT_TRANSFER_CONFIRM_TITLE",
                comment: "Title for the 'deactivate payments confirmation' UI in the payment settings.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_WITHOUT_TRANSFER_CONFIRM_DESCRIPTION",
                comment: "Description for the 'deactivate payments confirmation' UI in the payment settings.",
            ),
        )

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_DEACTIVATE_BUTTON",
                comment: "Label for the 'deactivate payments' button in the payment settings.",
            ),
            style: .destructive,
        ) { [weak self] _ in
            self?.deactivateImmediately()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func deactivateImmediately() {
        dismiss(animated: true) {
            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                SSKEnvironment.shared.paymentsHelperRef.disablePayments(transaction: transaction)
            }
        }
    }

    private func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }
}
