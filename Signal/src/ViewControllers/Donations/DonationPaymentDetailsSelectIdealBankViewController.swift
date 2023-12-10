//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI
import SignalMessaging

public protocol DonationPaymentDetailsSelectIdealBankDelegate: AnyObject {
    func viewController(_ viewController: DonationPaymentDetailsSelectIdealBankViewController, didSelect iDEALBank: Stripe.PaymentMethod.IDEALBank)
}

public class DonationPaymentDetailsSelectIdealBankViewController: OWSTableViewController2 {
    public weak var bankSelectionDelegate: DonationPaymentDetailsSelectIdealBankDelegate?

    public override init() {
        super.init()
        title = OWSLocalizedString(
            "IDEAL_DONATION_CHOOSE_YOUR_BANK_LABEL",
            comment: "Label for both bank chooser header and the bank form field on the iDEAL payment detail page."
        )
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
    }

    public func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { setContents(contents, shouldReload: shouldReload) }

        let section = OWSTableSection()
        for bank in Stripe.PaymentMethod.IDEALBank.allCases {
            section.add(.init(customCellBlock: {
                return OWSTableItem.buildImageCell(
                    image: bank.image,
                    itemName: bank.displayName
                )
            },
            actionBlock: { [weak self] in
                guard let self else { return }
                self.bankSelectionDelegate?.viewController(self, didSelect: bank)
            }))
        }
        contents.add(section)
    }
}
