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
    private enum State {
        case initializing
        case hasNoReport
        case hasReport(report: AccountDataReport)
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

        // TODO[ADE] Handle theme changes
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

        switch state {
        case .initializing:
            owsFailBeta("We don't expect to be in this state.")
        case .hasNoReport:
            result.append(downloadReportSection())
        case .hasReport:
            result.append(exportButtonSection())
        }

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

    private func exportButtonSection() -> OWSTableSection {
        let result = OWSTableSection(items: [.init(customCellBlock: { [weak self] in
            let cell = UITableViewCell()
            guard let self else { return cell }

            cell.contentView.addSubview(self.exportButton)
            self.exportButton.autoPinWidthToSuperviewMargins()

            return cell
        })])
        result.hasBackground = false
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

                    self.state = .hasReport(report: report)
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
        let report: AccountDataReport = {
            switch state {
            case .initializing, .hasNoReport:
                owsFail("Nothing to export. This should be prevented in the UI")
            case let .hasReport(report):
                return report
            }
        }()

        // TODO[ADE] Allow saving text, if available
        let data: Data = report.formattedJsonData

        // TODO[ADE] Improve this UI by saving a file
        let activityItem = String(data: data, encoding: .utf8)!

        ShareActivityUtil.present(
            activityItems: [activityItem],
            from: self,
            sourceView: exportButton
        )
    }
}
