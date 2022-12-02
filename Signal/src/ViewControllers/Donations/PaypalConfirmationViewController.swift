//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

class PaypalConfirmationViewController: OWSTableSheetViewController {
    private enum Constants {
        static let buttonHeight: CGFloat = 48
    }

    enum ConfirmationResult {
        case approved
        case canceled
    }

    typealias CompletionHandler = (ConfirmationResult, PaypalConfirmationViewController) -> Void

    private let amount: FiatMoney
    private let badge: ProfileBadge
    private let donationMode: DonationMode

    private var hasCompleted: Bool = false
    private let completion: CompletionHandler

    /// Create a confirmation view with the given completion handler. The
    /// handler is guaranteed to be called exactly once.
    init(
        amount: FiatMoney,
        badge: ProfileBadge,
        donationMode: DonationMode,
        completion: @escaping CompletionHandler
    ) {
        self.amount = amount
        self.badge = badge
        self.donationMode = donationMode
        self.completion = completion
    }

    /// Do not use!
    required init() {
        owsFail("Do not use this initializer!")
    }

    override func updateTableContents(shouldReload: Bool = true) {
        updateTop(shouldReload: shouldReload)
        updateBottom()
    }

    override func viewDidDisappear(_ animated: Bool) {
        complete(withResult: .canceled)
    }

    private func complete(withResult result: ConfirmationResult) {
        guard !hasCompleted else { return }

        hasCompleted = true
        completion(result, self)
    }
}

// MARK: - UI elements

private extension PaypalConfirmationViewController {
    func updateTop(shouldReload: Bool) {
        let headerView = DonateInfoSheetHeaderView(
            amount: amount,
            badge: badge,
            donationMode: donationMode
        )
        let headerSection = OWSTableSection(items: [.init(customCellBlock: {
            let cell = OWSTableItem.newCell()
            cell.contentView.addSubview(headerView)
            headerView.autoPinEdgesToSuperviewMargins()
            return cell
        })])
        headerSection.hasBackground = false
        headerSection.shouldDisableCellSelection = true

         let text = NSLocalizedString(
            "DONATION_CONFIRMATION_PAYMENT_METHOD",
            value: "Payment Method",
            comment: "Users can donate to Signal. They may be asked to confirm their donation after entering payment information. This text will show the payment method, such as PayPal, next to it."
         )
        let paymentMethodSection = OWSTableSection(items: [OWSTableItem.actionItem(
            name: text,
            accessoryImage: Theme.isDarkThemeEnabled
            ? UIImage(named: "paypal-logo-on-dark")!
            : UIImage(named: "paypal-logo")!,
            accessoryImageTint: .untinted,
            accessibilityIdentifier: "payment_method_section",
            actionBlock: nil
        )])
        paymentMethodSection.shouldDisableCellSelection = true

        let contents = OWSTableContents(sections: [headerSection, paymentMethodSection])

        self.tableViewController.setContents(contents, shouldReload: shouldReload)
    }

    @objc
    private func didCancel() {
        complete(withResult: .canceled)
    }

    func updateBottom() {
        let confirmButton: UIButton = {
             let title = NSLocalizedString(
                 "DONATION_CONFIRMATION_BUTTON_CONFIRM",
                 value: "Complete Donation",
                 comment: "Users can donate to Signal. They may be asked to confirm their donation after entering payment information. If the user clicks this button, their payment will be confirmed."
             )
            let button = OWSButton(title: title) { [weak self] in
                guard let self else { return }
                self.complete(withResult: .approved)
            }

            button.layer.cornerRadius = 12
            button.backgroundColor = .ows_accentBlue
            button.dimsWhenHighlighted = true
            button.titleLabel?.font = .ows_dynamicTypeBody.ows_semibold

            return button
        }()

        let cancelButton = {
            let button = OWSFlatButton()
            button.setTitle(
                title: CommonStrings.cancelButton,
                font: .ows_dynamicTypeBody.ows_semibold,
                titleColor: Theme.accentBlueColor
            )
            button.setBackgroundColors(upColor: .clear)

            button.enableMultilineLabel()
            button.button.clipsToBounds = true
            button.button.layer.cornerRadius = 8
            button.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 8)

            button.addTarget(target: self, selector: #selector(didCancel))

            return button
        }()

        let buttons = [confirmButton, cancelButton]
        for button in buttons {
            button.autoSetDimension(
                .height,
                toSize: Constants.buttonHeight,
                relation: .greaterThanOrEqual
            )
        }

        let buttonsStackView = UIStackView(arrangedSubviews: buttons)
        buttonsStackView.axis = .vertical
        buttonsStackView.alignment = .fill
        buttonsStackView.spacing = 12

        footerStack.removeAllSubviews()
        footerStack.addArrangedSubview(buttonsStackView)
        footerStack.alignment = .fill
        footerStack.layoutMargins = UIEdgeInsets(top: 12, leading: 40, bottom: 12, trailing: 40)
        footerStack.isLayoutMarginsRelativeArrangement = true

        buttonsStackView.autoPinWidthToSuperviewMargins()
    }
}
