//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalServiceKit
import SignalMessaging

class DonateChoosePaymentMethodSheet: OWSTableSheetViewController {
    private let amount: FiatMoney
    private let badge: ProfileBadge?
    private let donationMode: DonationMode
    private let supportedPaymentMethods: Set<DonationPaymentMethod>
    private let didChoosePaymentMethod: (DonateChoosePaymentMethodSheet, DonationPaymentMethod) -> Void

    private let buttonHeight: CGFloat = 48

    init(
        amount: FiatMoney,
        badge: ProfileBadge?,
        donationMode: DonationMode,
        supportedPaymentMethods: Set<DonationPaymentMethod>,
        didChoosePaymentMethod: @escaping (DonateChoosePaymentMethodSheet, DonationPaymentMethod) -> Void
    ) {
        self.amount = amount
        self.badge = badge
        self.donationMode = donationMode
        self.supportedPaymentMethods = supportedPaymentMethods
        self.didChoosePaymentMethod = didChoosePaymentMethod

        super.init()
    }

    required init() {
        owsFail("init() has not been implemented")
    }

    // MARK: - Updating table contents

    public override func updateTableContents(shouldReload: Bool = true) {
        updateTop(shouldReload: shouldReload)
        updateBottom()
    }

    private func updateTop(shouldReload: Bool) {
        let headerView = DonateInfoSheetHeaderView(
            amount: amount,
            badge: badge,
            donationMode: donationMode
        )
        let section = OWSTableSection(items: [.init(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.contentView.addSubview(headerView)
            headerView.autoPinEdgesToSuperviewMargins()
            return cell
        })])
        section.hasBackground = false
        let contents = OWSTableContents(sections: [section])

        self.tableViewController.setContents(contents, shouldReload: shouldReload)
    }

    private func updateBottom() {
        let paymentButtonContainerView: UIView = {
            var paymentMethodButtons = [UIView]()

            if supportedPaymentMethods.contains(.applePay) {
                paymentMethodButtons.append(ApplePayButton { [weak self] in
                    guard let self else { return }
                    self.didChoosePaymentMethod(self, .applePay)
                })
            }

            if supportedPaymentMethods.contains(.paypal) {
                paymentMethodButtons.append(PaypalButton { [weak self] in
                    guard let self else { return }
                    self.didChoosePaymentMethod(self, .paypal)
                })
            }

            if supportedPaymentMethods.contains(.creditOrDebitCard) {
                let title = NSLocalizedString(
                    "DONATE_CHOOSE_CREDIT_OR_DEBIT_CARD_AS_PAYMENT_METHOD",
                    comment: "When users make donations, they can choose which payment method they want to use. This is the text on the button that lets them choose to pay with credit or debit card."
                )

                let creditOrDebitCardButton = OWSButton(title: title) { [weak self] in
                    guard let self else { return }
                    self.didChoosePaymentMethod(self, .creditOrDebitCard)
                }
                guard let image = UIImage(named: "credit-or-debit-card") else {
                    owsFail("Card asset not found")
                }
                creditOrDebitCardButton.setImage(image, for: .normal)
                creditOrDebitCardButton.setPaddingBetweenImageAndText(
                    to: 8,
                    isRightToLeft: CurrentAppContext().isRTL
                )
                creditOrDebitCardButton.layer.cornerRadius = 12
                creditOrDebitCardButton.backgroundColor = .ows_accentBlue
                creditOrDebitCardButton.dimsWhenHighlighted = true
                creditOrDebitCardButton.titleLabel?.font = .ows_dynamicTypeBody.ows_semibold
                paymentMethodButtons.append(creditOrDebitCardButton)
            }

            owsAssert(!paymentMethodButtons.isEmpty, "Expected at least one payment method")

            let stackView = UIStackView(arrangedSubviews: paymentMethodButtons)
            stackView.axis = .vertical
            stackView.alignment = .fill
            stackView.spacing = 12

            for button in paymentMethodButtons {
                button.autoSetDimension(.height, toSize: buttonHeight)
            }

            return stackView
        }()

        footerStack.removeAllSubviews()
        footerStack.addArrangedSubview(paymentButtonContainerView)
        footerStack.alignment = .fill
        footerStack.layoutMargins = UIEdgeInsets(top: 28, left: 40, bottom: 8, right: 40)
        footerStack.isLayoutMarginsRelativeArrangement = true

        paymentButtonContainerView.autoPinWidthToSuperviewMargins()
    }
}
