//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class PaymentsDeactivateViewController: OWSViewController {

    var paymentBalance: PaymentBalance

    public required init(paymentBalance: PaymentBalance) {
        owsAssertDebug(paymentBalance.amount.isValidAmount(canBeEmpty: false))

        self.paymentBalance = paymentBalance
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_TITLE",
                                  comment: "Label for the 'de-activate payments' view of the app settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                           target: self,
                                                           action: #selector(didTapDismiss),
                                                           accessibilityIdentifier: "dismiss")

        addListeners()

        updateContents()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        paymentsSwift.updateCurrentPaymentBalance()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateContents()
    }

    private func addListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(arePaymentsEnabledDidChange),
            name: PaymentsConstants.arePaymentsEnabledDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(currentPaymentBalanceDidChange),
            name: PaymentsImpl.currentPaymentBalanceDidChange,
            object: nil
        )
    }

    @objc
    private func arePaymentsEnabledDidChange() {
        Logger.info("")
        dismiss(animated: true, completion: nil)
    }

    @objc
    private func currentPaymentBalanceDidChange() {
        guard let currentPaymentBalance = paymentsSwift.currentPaymentBalance,
              currentPaymentBalance.amount.isValidAmount(canBeEmpty: false) else {
            // We need to abort the "deactivate payments with outstanding balance"
            // flow if:
            //
            // * The balance becomes unavailable (this should never happen).
            // * The balance becomes zero (this should be extremely rare).
            Logger.warn("Missing or empty balance.")
            dismiss(animated: true, completion: nil)
            return
        }
        self.paymentBalance = currentPaymentBalance
        self.updateContents()
    }

    private func updateContents() {
        let backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)
        view.backgroundColor = backgroundColor

        view.removeAllSubviews()

        let titleLabel = UILabel()
        titleLabel.font = UIFont.regularFont(ofSize: 54)
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.attributedText = PaymentsFormat.attributedFormat(paymentAmount: paymentBalance.amount,
                                                                    isShortForm: false)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_REMAINING_BALANCE",
                                               comment: "Label for the current balance in the 'deactivate payments' settings.")
        subtitleLabel.font = .dynamicTypeBodyClamped
        subtitleLabel.textColor = Theme.secondaryTextAndIconColor
        subtitleLabel.textAlignment = .center

        let explanationLabel = PaymentsViewUtils.buildTextWithLearnMoreLinkTextView(
            text: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_WITH_BALANCE_EXPLANATION",
                                    comment: "Explanation of the 'deactivate payments with balance' process in the 'deactivate payments' settings."),
            font: .dynamicTypeBody2Clamped,
            learnMoreUrl: "https://support.signal.org/hc/en-us/articles/360057625692#payments_deactivate")
        explanationLabel.backgroundColor = backgroundColor
        explanationLabel.textAlignment = .center

        let transferBalanceButton = OWSFlatButton.button(title: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_AFTER_TRANSFERRING_BALANCE",
                                                                                  comment: "Label for 'transfer balance' button in the 'deactivate payments' settings."),
                                                         font: UIFont.dynamicTypeBody.semibold(),
                                                         titleColor: .white,
                                                         backgroundColor: .ows_accentBlue,
                                                         target: self,
                                                         selector: #selector(didTapTransferBalanceButton))
        transferBalanceButton.autoSetHeightUsingFont()

        let deactivateImmediatelyButton = OWSFlatButton.button(title: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_WITHOUT_TRANSFERRING_BALANCE",
                                                                                        comment: "Label for 'deactivate payments without transferring balance' button in the 'deactivate payments' settings."),
                                                               font: UIFont.dynamicTypeBody.semibold(),
                                                               titleColor: .ows_accentRed,
                                                               backgroundColor: backgroundColor,
                                                               target: self,
                                                               selector: #selector(didTapDeactivateImmediatelyButton))
        deactivateImmediatelyButton.autoSetHeightUsingFont()

        let topStack = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 8),
            subtitleLabel,
            UIView.spacer(withHeight: 44),
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 0)

        let stackView = UIStackView(arrangedSubviews: [
            UIView.spacer(withHeight: 40),
            topStack,
            UIView.vStretchingSpacer(),
            transferBalanceButton,
            UIView.spacer(withHeight: 8),
            deactivateImmediatelyButton,
            UIView.spacer(withHeight: 8)
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
    }

    // MARK: - Events

    @objc
    private func didTapTransferBalanceButton() {

        Logger.verbose("paymentBalance: \(paymentBalance.amount.picoMob)")

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { [weak self] modalActivityIndicator in

            firstly(on: DispatchQueue.global()) {
                Self.paymentsSwift.maximumPaymentAmount()
            }.done { (transferAmount: TSPaymentAmount) in
                AssertIsOnMainThread()

                Logger.verbose("maximumPaymentAmount: \(transferAmount.picoMob)")

                modalActivityIndicator.dismiss {
                    guard let navigationController = self?.navigationController else {
                        owsFailDebug("Missing navigationController.")
                        return
                    }
                    let view = PaymentsTransferOutViewController(transferAmount: transferAmount)
                    navigationController.pushViewController(view, animated: true)
                }
            }.catch { error in
                AssertIsOnMainThread()
                owsFailDebug("Error: \(error)")

                modalActivityIndicator.dismiss {
                    OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATION_FAILED",
                                                                              comment: "Error indicating that payments could not be deactivated in the payments settings."))
                }
            }
        }
    }

    @objc
    private func didTapDeactivateImmediatelyButton() {
        let actionSheet = ActionSheetController(title: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_WITHOUT_TRANSFER_CONFIRM_TITLE",
                                                                         comment: "Title for the 'deactivate payments confirmation' UI in the payment settings."),
                                                message: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_WITHOUT_TRANSFER_CONFIRM_DESCRIPTION",
                                                                           comment: "Description for the 'deactivate payments confirmation' UI in the payment settings."))

        actionSheet.addAction(ActionSheetAction(title: OWSLocalizedString("SETTINGS_PAYMENTS_DEACTIVATE_BUTTON",
                                                                         comment: "Label for the 'deactivate payments' button in the payment settings."),
                                                accessibilityIdentifier: "payments.settings.deactivate.continue",
                                                style: .destructive) { [weak self] _ in
            self?.deactivateImmediately()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func deactivateImmediately() {
        dismiss(animated: true) {
            Self.databaseStorage.write { transaction in
                Self.paymentsHelperSwift.disablePayments(transaction: transaction)
            }
        }
    }

    @objc
    private func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }
}
