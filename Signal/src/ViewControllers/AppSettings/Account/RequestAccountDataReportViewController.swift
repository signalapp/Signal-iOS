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

    private enum State {
        case initializing
        case hasNoReport
        case hasReport(report: AccountDataReport, selectedFileType: FileType)

        func selectFileType(_ fileType: FileType) -> State {
            switch self {
            case .initializing, .hasNoReport:
                owsFailBeta("It should be impossible to select a file type in this state")
                return self
            case let .hasReport(report, _):
                return .hasReport(report: report, selectedFileType: fileType)
            }
        }
    }
    private var state: State = .initializing {
        didSet { updateTableContents() }
    }

    public override init() {
        owsAssert(FeatureFlags.canRequestAccountDataReport)

        super.init()
    }

    // MARK: - Callbacks

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = "Request Account Data"

        // TODO[ADE] Check the database for the initial state.
        state = .hasNoReport
    }

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    // MARK: - Rendering

    private lazy var exportButton = Self.button(title: "Export Report") { [weak self] in
        self?.didTapExport()
    }

    private static func button(title: String, block: @escaping () -> Void) -> UIView {
        let result = OWSButton(title: title, block: block)
        result.dimsWhenHighlighted = true
        result.layer.cornerRadius = 8
        result.backgroundColor = .ows_accentBlue
        result.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_semibold
        result.autoSetDimension(.height, toSize: 48)
        return result
    }

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: getTableSections())
    }

    private func getTableSections() -> [OWSTableSection] {
        var result = [OWSTableSection]()

        result.append(headerSection())

        switch state {
        case .initializing:
            owsFailBeta("We don't expect to be in this state.")
        case .hasNoReport:
            result.append(downloadReportSection())
        case let .hasReport(report, selectedFileType):
            if report.textData != nil {
                result.append(chooseFileTypeSection(selectedFileType: selectedFileType))
            }
            result.append(exportButtonSection())
        }

        return result
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

    private func downloadReportSection() -> OWSTableSection {
        let result = OWSTableSection(items: [.init(customCellBlock: {
            let cell = UITableViewCell()

            let downloadButton = Self.button(title: "Download Report") { [weak self] in
                self?.didRequestDownload()
            }

            cell.contentView.addSubview(downloadButton)
            downloadButton.autoPinWidthToSuperviewMargins()

            return cell
        })])
        result.hasBackground = false
        return result
    }

    private func chooseFileTypeSection(selectedFileType: FileType) -> OWSTableSection {
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

    private func didRequestDownload() {
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
                .done(on: DispatchQueue.main) { [weak self] response in
                    modal.dismissIfNotCanceled()
                    if modal.wasCancelled { return }

                    guard let self else { return }

                    let status = response.responseStatusCode
                    guard status == 200 else {
                        Logger.warn("Received a \(status) status code. The request failed")
                        self.didRequestFail()
                        return
                    }

                    guard let rawData = response.responseBodyData else {
                        Logger.error("Received an empty response")
                        self.didRequestFail()
                        return
                    }

                    guard let report = try? AccountDataReport(rawData: rawData) else {
                        Logger.error("Couldn't parse account data report, presumably due to a bug")
                        self.didRequestFail()
                        return
                    }

                    self.state = .hasReport(
                        report: report,
                        selectedFileType: report.textData == nil ? .json : .text
                    )
                }
                .catch(on: DispatchQueue.main) { [weak self] error in
                    modal.dismissIfNotCanceled()
                    if modal.wasCancelled { return }

                    owsFailDebugUnlessNetworkFailure(error)

                    self?.didRequestFail()
                }
        }
    }

    private func didRequestFail() {
        // TODO[ADE] Improve this UI
        OWSActionSheets.showActionSheet(
            message: CommonStrings.somethingWentWrongTryAgainLaterError
        )
    }

    private func didSelectFileType(_ fileType: FileType) {
        state = state.selectFileType(fileType)
    }

    private func didTapExport() {
        let actionSheet = ActionSheetController(
            message: "Only share your Signal account data with people or apps you trust."
        )

        actionSheet.addAction(.init(
            title: "Export Report"
        ) { [weak self] _ in
            self?.didConfirmExport()
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: self)
    }

    private func didConfirmExport() {
        let report: AccountDataReport
        let fileType: FileType
        switch state {
        case .initializing, .hasNoReport:
            owsFail("Nothing to export. This should be prevented in the UI")
        case let .hasReport(reportInState, selectedFileType):
            report = reportInState
            fileType = selectedFileType
        }

        let (activityItem, cleanup) = prepareForSharing(report: report, fileType: fileType)

        ShareActivityUtil.present(
            activityItems: [activityItem],
            from: self,
            sourceView: exportButton,
            completion: cleanup
        )
    }

    private func prepareForSharing(
        report: AccountDataReport,
        fileType: FileType
    ) -> (activityItem: Any, cleanup: () -> Void) {
        let data: Data
        let fileExtension: String
        switch fileType {
        case .text:
            guard let textData = report.textData else {
                owsFail("No text data is available. This should be prevented in the UI")
            }
            data = textData
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
