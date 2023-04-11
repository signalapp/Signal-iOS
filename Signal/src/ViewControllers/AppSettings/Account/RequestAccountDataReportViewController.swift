//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalMessaging
import SignalServiceKit

// TODO[ADE] Localize the strings in this file

class RequestAccountDataReportViewController: OWSTableViewController2 {
    private var learnMoreUrl: URL {
        URL(string: "https://support.signal.org/hc/articles/5538911756954")!
    }

    private enum FileType {
        case json
        case text
    }

    private var selectedFileType: FileType = .text {
        didSet {
            if selectedFileType != oldValue {
                updateTableContents()
            }
        }
    }

    public override init() {
        owsAssert(FeatureFlags.canRequestAccountDataReport)

        super.init()
    }

    // MARK: - Callbacks

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your Account Data"
        updateTableContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    // MARK: - Rendering

    private lazy var exportButton: UIView = {
        let title = "Export Report"
        let result = OWSButton(title: title) { [weak self] in self?.didTapExport() }
        result.dimsWhenHighlighted = true
        result.layer.cornerRadius = 8
        result.backgroundColor = .ows_accentBlue
        result.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
        result.autoSetDimension(.height, toSize: 48)
        return result
    }()

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: [
            headerSection(),
            chooseFileTypeSection(),
            exportButtonSection()
        ])
    }

    private func headerSection() -> OWSTableSection {
        let result = OWSTableSection(items: [
            .init(customCellBlock: { [weak self] in
                let cell = UITableViewCell()
                guard let self else { return cell }
                cell.layoutMargins = OWSTableViewController2.cellOuterInsets(in: self.view)
                cell.contentView.layoutMargins = .zero

                let iconView = UIImageView(image: .init(named: "account_data_report"))
                iconView.autoSetDimensions(to: .square(88))

                let titleLabel = UILabel()
                titleLabel.textAlignment = .center
                titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
                titleLabel.text = "Your Account Data"
                titleLabel.numberOfLines = 0
                titleLabel.lineBreakMode = .byWordWrapping

                let descriptionTextView = LinkingTextView()
                descriptionTextView.attributedText = .composed(
                    of: [
                        "Download and export a report of your Signal account data. This report does not include any messages or media.",
                        CommonStrings.learnMore.styled(with: .link(self.learnMoreUrl))
                    ],
                    baseStyle: .init(.color(Theme.primaryTextColor), .font(.ows_dynamicTypeBody)),
                    separator: " "
                )
                descriptionTextView.linkTextAttributes = [
                    .foregroundColor: Theme.accentBlueColor,
                    .underlineColor: UIColor.clear,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                descriptionTextView.textAlignment = .center

                let stackView = UIStackView(arrangedSubviews: [
                    iconView,
                    titleLabel,
                    descriptionTextView
                ])
                stackView.axis = .vertical
                stackView.alignment = .center
                stackView.spacing = 12
                stackView.setCustomSpacing(24, after: iconView)

                cell.contentView.backgroundColor = .cyan

                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()

                return cell
            })
        ])
        result.hasBackground = false
        return result
    }

    private func chooseFileTypeSection() -> OWSTableSection {
        let selectedFileType = self.selectedFileType
        return OWSTableSection(items: [
            .init(
                customCellBlock: {
                    return OWSTableItem.buildImageNameCell(
                        itemName: "Export as TXT",
                        subtitle: "Easy-to-read text file",
                        accessoryType: selectedFileType == .text ? .checkmark : .none
                    )
                },
                actionBlock: { [weak self] in
                    self?.didSelectFileType(.text)
                }
            ),
            .init(
                customCellBlock: {
                    return OWSTableItem.buildImageNameCell(
                        itemName: "Export as JSON",
                        subtitle: "Machine-readable file",
                        accessoryType: selectedFileType == .json ? .checkmark : .none
                    )
                },
                actionBlock: { [weak self] in
                    self?.didSelectFileType(.json)
                }
            )
        ])
    }

    private func exportButtonSection() -> OWSTableSection {
        let result = OWSTableSection(items: [.init(customCellBlock: { [weak self] in
            let cell = UITableViewCell()
            guard let self else { return cell }

            cell.contentView.addSubview(self.exportButton)
            self.exportButton.autoPinEdgesToSuperviewMargins()

            return cell
        })])
        result.hasBackground = false
        result.footerTitle = "Your report is generated only at the time of export and is not stored by Signal on your device."
        return result
    }

    // MARK: - Events

    private func didTapExport() {
        let request = AccountDataReportRequestFactory.createAccountDataReportRequest()

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: true
        ) { [weak self] modal in
            guard let self else {
                modal.dismissIfNotCanceled()
                return
            }

            self.signalService.urlSessionForMainSignalService()
                .promiseForTSRequest(request)
                .then(on: DispatchQueue.sharedUserInitiated) { response -> Promise<AccountDataReport> in
                    let status = response.responseStatusCode
                    guard status == 200 else {
                        return .init(
                            error: OWSGenericError("Received a \(status) status code. The request failed")
                        )
                    }

                    guard let rawData = response.responseBodyData else {
                        return .init(error: OWSGenericError("Received an empty response"))
                    }

                    guard let report = try? AccountDataReport(rawData: rawData) else {
                        return .init(
                            error: OWSGenericError("Couldn't parse account data report, presumably due to a bug")
                        )
                    }

                    return .value(report)
                }.done(on: DispatchQueue.main) { report in
                    modal.dismiss { [weak self] in
                        if modal.wasCancelled { return }

                        self?.confirmExport { [weak self] in
                            self?.didConfirmExport(of: report)
                        }
                    }
                }.catch(on: DispatchQueue.main) { error in
                    modal.dismiss { [weak self] in
                        if modal.wasCancelled { return }

                        Logger.warn("\(error)")

                        self?.didRequestFail()
                    }
                }
        }
    }

    private func didRequestFail() {
        OWSActionSheets.showActionSheet(
            title: "Couldn’t Generate Report",
            message: "Check your connection and try again."
        )
    }

    private func didSelectFileType(_ fileType: FileType) {
        self.selectedFileType = fileType
    }

    private func confirmExport(didConfirm: @escaping () -> Void) {
        let actionSheet = ActionSheetController(
            message: "Only share your Signal account data with people or apps you trust."
        )

        actionSheet.addAction(.init(
            title: "Export Report"
        ) { _ in
            didConfirm()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    private func didConfirmExport(of report: AccountDataReport) {
        let (activityItem, cleanup) = prepareForSharing(report: report)

        ShareActivityUtil.present(
            activityItems: [activityItem],
            from: self,
            sourceView: exportButton,
            completion: cleanup
        )
    }

    private func prepareForSharing(
        report: AccountDataReport
    ) -> (activityItem: Any, cleanup: () -> Void) {
        let data: Data
        let fileExtension: String
        switch selectedFileType {
        case .text:
            data = report.textData
            fileExtension = "txt"
        case .json:
            data = report.formattedJsonData
            fileExtension = "json"
        }

        let temporaryFileUrl = URL(
            // This isn't localized because the report is *also* not localized.
            fileURLWithPath: "account-data.\(fileExtension)",
            relativeTo: URL(fileURLWithPath: OWSTemporaryDirectory(), isDirectory: true)
        )

        let activityItem: Any
        let cleanup: () -> Void

        do {
            try data.write(to: temporaryFileUrl, options: .completeFileProtection)
            activityItem = temporaryFileUrl
            cleanup = {
                do {
                    try OWSFileSystem.deleteFile(url: temporaryFileUrl)
                } catch {
                    owsFailBeta("Failed to delete temporary account data report file")
                }
            }
        } catch {
            owsFailBeta("Failed to write account data report to temporary file. Falling back to plain data")
            activityItem = data
            cleanup = {}
        }

        return (activityItem, cleanup)
    }
}
