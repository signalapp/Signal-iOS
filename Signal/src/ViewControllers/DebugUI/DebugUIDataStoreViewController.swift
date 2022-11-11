//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class DebugUIReportsViewController: OWSTableViewController2 {

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
    }

    struct Report {
        let title: String
        let text: String
    }

    var currentReport: Report? {
        didSet {
            updateTableContents()
        }
    }

    public func updateTableContents() {
        let contents = OWSTableContents()

        contents.addSection(
            OWSTableSection(title: "Print Reports", items: [
                OWSTableItem.init(title: "Signal Recipients") { [weak self] in
                    guard let self = self else { return }
                    self.databaseStorage.read { transaction in
                        let report = Report(title: "Signal Recipients",
                                            text: self.signalRecipientsReport(transaction: transaction))
                        self.currentReport = report
                        Logger.debug("report: \(report.title), text:\n \(report.text)")
                    }
                }
            ])
        )

        if let report = self.currentReport {
            let item = OWSTableItem(customCellBlock: { () -> UITableViewCell in
                    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                    let textView = UITextView()
                    textView.text = report.text
                    cell.contentView.addSubview(textView)
                    textView.autoPinEdgesToSuperviewEdges()

                    return cell
                })
            item.customRowHeight = NSNumber(value: 400)

            contents.addSection(
                OWSTableSection(title: "Report: \(report.title)", items: [ item ])
            )
        }

        self.contents = contents
    }

    func signalRecipientsReport(transaction: SDSAnyReadTransaction) -> String {
        var recipients: [SignalServiceAddress: [String]] = [:]

        var reportText = ""
        let report: (String) -> Void = { line in
            reportText.append(line)
            reportText.append("\n")
        }

        report("== Signal Recipients ==")
        var i = 0
        SignalRecipient.anyEnumerate(transaction: transaction) { (recipient, _) in
            i += 1
            if let existing = recipients[recipient.address] {
                report("\(i). recipient (duplicated): \(recipient)")
                recipients[recipient.address] = existing + [recipient.uniqueId]
            } else {
                report("\(i). recipient: \(recipient)")
                recipients[recipient.address] = [recipient.uniqueId]
            }
        }

        var duplicatedRecipients: [SignalServiceAddress: [String]] = [:]
        for (address, recipients) in recipients {
            if recipients.count > 1 {
                duplicatedRecipients[address] = recipients
            }
        }

        if duplicatedRecipients.count > 0 {
            report("== Duplicated Signal Recipients ==")
            i = 0
            for (address, recipientIds) in duplicatedRecipients {
                i += 1
                report("\(i). address: \(address), recipientIds \(recipientIds.count): \(recipientIds)")
            }
        } else {
            report("== No Duplicated Signal Recipients ==")
        }

        return reportText
    }
}
