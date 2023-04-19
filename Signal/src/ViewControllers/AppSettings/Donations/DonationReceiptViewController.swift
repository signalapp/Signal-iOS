//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import UIKit

class DonationReceiptViewController: OWSTableViewController2 {
    let model: DonationReceipt
    let signalLogoView: UIImageView = {
        let view = UIImageView()
        view.autoSetDimensions(to: CGSize(width: 100, height: 31))
        view.contentMode = .scaleAspectFit
        return view
    }()

    let shareReceiptButton: OWSButton = {
        let button = OWSButton()
        button.setTitle(NSLocalizedString("DONATION_RECEIPT_EXPORT_RECEIPT_BUTTON", comment: "Text on the button that exports the receipt"),
                        for: .normal)
        button.titleLabel?.font = .dynamicTypeBodyClamped.semibold()
        button.clipsToBounds = true
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
        button.dimsWhenHighlighted = true
        button.backgroundColor = .ows_accentBlue

        return button
    }()
    let shareReceiptButtonContainer: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins.top = 10
        stackView.layoutMargins.bottom = 10
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init(model: DonationReceipt) {
        self.model = model
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("DONATION_RECEIPT_DETAILS", comment: "Title on the view where you can see a single receipt")

        shareReceiptButton.block = { self.showShareReceiptActivity() }
        shareReceiptButtonContainer.addArrangedSubview(shareReceiptButton)

        updateTableContents()
        updateSignalLogoImage()
        updateShareReceiptButton()
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateSignalLogoImage()
        updateShareReceiptButton()
    }

    private func updateSignalLogoImage() {
        let signalLogoImage = UIImage(named: "signal-full-logo")
        if Theme.isDarkThemeEnabled {
            signalLogoView.image = signalLogoImage?.tintedImage(color: .ows_white)
        } else {
            signalLogoView.image = signalLogoImage
        }
    }

    // MARK: - Rendering table contents

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: [amountSection(), detailsSection()])
    }

    private func amountSection() -> OWSTableSection {
        OWSTableSection(items: [
            OWSTableItem(customCellBlock: {
                let model = self.model

                let amountLabel = UILabel()
                amountLabel.text = DonationUtilities.format(money: model.amount)
                amountLabel.textColor = Theme.primaryTextColor
                amountLabel.font = .preferredFont(forTextStyle: .largeTitle)
                amountLabel.adjustsFontForContentSizeCategory = true

                let content = UIStackView(arrangedSubviews: [self.signalLogoView, amountLabel])
                content.axis = .vertical
                content.alignment = .center
                content.spacing = 12

                let cell = OWSTableItem.newCell()
                cell.contentView.addSubview(content)

                content.autoPinEdgesToSuperviewMargins()

                return cell
            })
        ])
    }

    private func detailsSection() -> OWSTableSection {
        OWSTableSection(items: [
            .item(
                name: NSLocalizedString("DONATION_RECEIPT_TYPE", comment: "Section title for donation type on receipts"),
                subtitle: model.localizedName,
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donation_receipt_details_type")
            ),
            .item(
                name: NSLocalizedString("DONATION_RECEIPT_DATE_PAID", comment: "Section title for donation date on receipts"),
                subtitle: dateFormatter.string(from: model.timestamp),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "donation_receipt_details_date")
            )
        ])
    }

    // MARK: - Share button

    open override var bottomFooter: UIView? {
        get { shareReceiptButtonContainer }
        set {}
    }

    private func updateShareReceiptButton() {
        let textColor: UIColor = Theme.isDarkThemeEnabled ? .ows_whiteAlpha90 : .ows_white
        shareReceiptButton.setTitleColor(textColor, for: .normal)
    }

    private func showShareReceiptActivity() {
        ShareActivityUtil.present(
            activityItems: [DonationReceiptImageActivityItemProvider(donationReceipt: model)],
            from: self,
            sourceView: shareReceiptButton
        )
    }

    // MARK: - Donation receipt image activity provider

    private class DonationReceiptImageActivityItemProvider: UIActivityItemProvider {
        let donationReceiptImage: UIImage

        public override var item: Any { donationReceiptImage }

        init(donationReceipt: DonationReceipt) {
            donationReceiptImage = Self.getDonationReceiptImage(donationReceipt: donationReceipt)
            super.init(placeholderItem: donationReceiptImage)
        }

        // MARK: Image creation

        private class func getDonationReceiptImage(donationReceipt: DonationReceipt) -> UIImage {
            let view = Self.makeView(donationReceipt: donationReceipt)
            let renderer = UIGraphicsImageRenderer(size: view.bounds.size)
            return renderer.image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
        }

        // MARK: View creation

        private class func makeView(donationReceipt: DonationReceipt) -> UIView {
            let stackView = UIStackView()
            stackView.backgroundColor = .white
            stackView.isOpaque = true
            stackView.axis = .vertical
            stackView.alignment = .fill

            let subviewsWithSpacings: [(UIView, CGFloat)] = [
                (Self.headerView(), 12),
                (Self.dividerView(color: .ows_gray15), 37),
                (Self.titleView(), 24),
                (Self.amountView(donationReceipt: donationReceipt), 20),
                (Self.dividerView(color: .ows_gray90), 22),
                (Self.donationTypeView(donationReceipt: donationReceipt), 10),
                (Self.dividerView(color: .ows_gray20), 20),
                (Self.datePaidView(donationReceipt: donationReceipt), 22),
                (Self.footerView(), 0)
            ]
            for (subview, spacing) in subviewsWithSpacings {
                stackView.addArrangedSubview(subview)
                stackView.setCustomSpacing(spacing, after: subview)
            }

            let containerWidth: CGFloat = 612
            let containerMargins = UIEdgeInsets(hMargin: 65, vMargin: 32)

            let stackViewSize = stackView.systemLayoutSizeFitting(CGSize(width: containerWidth - containerMargins.leading - containerMargins.trailing,
                                                                         height: CGFloat.greatestFiniteMagnitude),
                                                                  withHorizontalFittingPriority: .required,
                                                                  verticalFittingPriority: .fittingSizeLevel)
            let containerView = UIView()
            containerView.frame.size = CGSize(width: stackViewSize.width + containerMargins.leading + containerMargins.trailing,
                                              height: stackViewSize.height + containerMargins.top + containerMargins.bottom)
            containerView.backgroundColor = .white
            containerView.isOpaque = true
            containerView.addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges(with: containerMargins)

            return containerView
        }

        private class func headerView() -> UIView {
            let signalLogo = UIImage(named: "signal-full-logo")
            let signalLogoView = UIImageView(image: signalLogo)
            signalLogoView.autoSetDimensions(to: CGSize(width: 100, height: 31))

            let currentDateView = label(dateFormatter().string(from: Date()),
                                        fontSize: 13,
                                        textColor: .ows_gray60,
                                        isAlignedToEdge: true)

            let headerView = UIStackView(arrangedSubviews: [signalLogoView, currentDateView])
            headerView.axis = .horizontal
            headerView.alignment = .center
            headerView.distribution = .fill

            return headerView
        }

        private class func titleView() -> UIView {
            label(NSLocalizedString("DONATION_RECEIPT_TITLE", comment: "Title on donation receipts"),
                  fontSize: 20)
        }

        private class func amountView(donationReceipt: DonationReceipt) -> UIView {
            let arrangedSubviews = [
                label(NSLocalizedString("DONATION_RECEIPT_AMOUNT", comment: "Section title for donation amount on receipts")),
                label(DonationUtilities.format(money: donationReceipt.amount), isAlignedToEdge: true)
            ]
            let amountView = UIStackView(arrangedSubviews: arrangedSubviews)
            amountView.axis = .horizontal
            amountView.alignment = .leading
            amountView.distribution = .fillProportionally
            return amountView
        }

        private class func donationTypeView(donationReceipt: DonationReceipt) -> UIView {
            detailView(title: NSLocalizedString("DONATION_RECEIPT_TYPE", comment: "Section title for donation type on receipts"),
                       subtitle: donationReceipt.localizedName)
        }

        private class func datePaidView(donationReceipt: DonationReceipt) -> UIView {
            detailView(title: NSLocalizedString("DONATION_RECEIPT_DATE_PAID", comment: "Section title for donation date on receipts"),
                       subtitle: dateFormatter().string(from: donationReceipt.timestamp))
        }

        private class func footerView() -> UIView {
            label(NSLocalizedString("DONATION_RECEIPT_FOOTER", comment: "Footer text at the bottom of donation receipts"),
                  fontSize: 12,
                  textColor: .ows_gray60)
        }

        private class func label(_ text: String,
                                 fontSize: CGFloat = 17,
                                 textColor: UIColor = .ows_gray95,
                                 isAlignedToEdge: Bool = false) -> UILabel {
            let result = UILabel()
            result.text = text
            result.textColor = textColor
            result.font = UIFont(name: "Inter-Regular_Medium", size: fontSize)
            result.numberOfLines = 0
            if isAlignedToEdge {
                result.textAlignment = CurrentAppContext().isRTL ? .left : .right
            }
            return result
        }

        private class func dividerView(color: UIColor) -> UIView {
            let divider = UIView()
            divider.backgroundColor = color
            divider.autoSetDimension(.height, toSize: 1)
            return divider
        }

        private class func detailView(title: String, subtitle: String) -> UIView {
            let arrangedSubviews = [
                label(title),
                label(subtitle, fontSize: 13, textColor: .ows_gray45)
            ]
            let detailView = UIStackView(arrangedSubviews: arrangedSubviews)
            detailView.axis = .vertical
            detailView.alignment = .leading
            return detailView
        }

        private class func dateFormatter() -> DateFormatter {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            return dateFormatter
        }
    }
}
