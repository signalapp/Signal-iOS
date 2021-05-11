//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PassKit
import PromiseKit

class DonationViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let section = OWSTableSection()
        section.hasBackground = false
        contents.addSection(section)

        section.add(.init(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none

                let imageView = UIImageView()
                imageView.image = #imageLiteral(resourceName: "character-loving")
                imageView.contentMode = .scaleAspectFit
                cell.contentView.addSubview(imageView)
                imageView.autoPinEdgesToSuperviewMargins()
                imageView.autoSetDimension(.height, toSize: 144)

                return cell
            },
            actionBlock: {

            }
        ))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let supportedNetworks: [PKPaymentNetwork] = [
            .amex,
            .discover,
            .masterCard,
            .visa
        ]

        let donation = PKPaymentSummaryItem(label: "Donation to Signal", amount: NSDecimalNumber(string: "10.00"), type: .final)
        let paymentSummaryItems = [donation]

        let paymentRequest = PKPaymentRequest()
        paymentRequest.paymentSummaryItems = paymentSummaryItems
        paymentRequest.merchantIdentifier = "merchant.org.signalfoundation"
        paymentRequest.merchantCapabilities = .capability3DS
        paymentRequest.countryCode = "US"
        paymentRequest.currencyCode = "USD"
        paymentRequest.requiredBillingContactFields = [.emailAddress]
        paymentRequest.supportedNetworks = supportedNetworks

        let paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        paymentController.delegate = self
        paymentController.present(completion: { (presented: Bool) in
            if presented {
                debugPrint("Presented payment controller")
            } else {
                debugPrint("Failed to present payment controller")
//                self.completionHandler(false)
            }
        })
    }
}

extension DonationViewController: PKPaymentAuthorizationControllerDelegate {
    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {

    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        Stripe.donate(amount: 10.00, in: "USD", for: payment).done {
            completion(.init(status: .success, errors: nil))
        }.catch { error in
            completion(.init(status: .failure, errors: [error]))
        }
    }
}
