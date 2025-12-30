//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

class RequestAccountDataReportViewController: OWSTableViewController2 {
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

    // MARK: - Callbacks

    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "ACCOUNT_DATA_REPORT_TITLE",
            comment: "Users can request a report of their account data. This is the title on the screen where they do this.",
        )
        updateTableContents()
    }

    // MARK: - Rendering

    private lazy var exportButton = UIButton(
        configuration: .largePrimary(title: OWSLocalizedString(
            "ACCOUNT_DATA_REPORT_EXPORT_REPORT_BUTTON",
            comment: "Users can request a report of their account data. Users tap this button to export their data.",
        )),
        primaryAction: UIAction { [weak self] _ in
            self?.didTapExport()
        },
    )

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: [
            headerSection(),
            chooseFileTypeSection(),
            exportButtonSection(),
        ])
    }

    private func headerSection() -> OWSTableSection {
        let result = OWSTableSection(items: [
            .init(customCellBlock: {
                let cell = UITableViewCell()

                let iconView = UIImageView(image: .init(named: "account_data_report"))
                iconView.translatesAutoresizingMaskIntoConstraints = false
                let iconViewContainer = UIView.container()
                iconViewContainer.addSubview(iconView)
                iconViewContainer.addConstraints([
                    iconView.topAnchor.constraint(equalTo: iconViewContainer.topAnchor),
                    iconView.leadingAnchor.constraint(greaterThanOrEqualTo: iconViewContainer.leadingAnchor),
                    iconView.centerXAnchor.constraint(equalTo: iconViewContainer.centerXAnchor),
                    iconView.bottomAnchor.constraint(equalTo: iconViewContainer.bottomAnchor, constant: -12),
                ])

                let descriptionTextView = LinkingTextView()
                descriptionTextView.attributedText = .composed(
                    of: [
                        OWSLocalizedString(
                            "ACCOUNT_DATA_REPORT_SUBTITLE",
                            comment: "Users can request a report of their account data. This is the subtitle on the screen where they do this, giving them more information.",
                        ),
                        CommonStrings.learnMore.styled(with: .link(URL.Support.requestingAccountData)),
                    ],
                    baseStyle: .init(.color(.Signal.secondaryLabel), .font(.dynamicTypeSubheadline)),
                    separator: " ",
                )
                descriptionTextView.textAlignment = .center

                let stackView = UIStackView(arrangedSubviews: [
                    iconViewContainer,
                    descriptionTextView,
                ])
                stackView.axis = .vertical
                stackView.spacing = 12
                cell.contentView.addSubview(stackView)
                stackView.autoPinEdgesToSuperviewMargins()

                return cell
            }),
        ])
        result.hasBackground = false
        return result
    }

    private func chooseFileTypeSection() -> OWSTableSection {
        let selectedFileType = self.selectedFileType
        return OWSTableSection(items: [
            .init(
                customCellBlock: {
                    return OWSTableItem.buildImageCell(
                        itemName: OWSLocalizedString(
                            "ACCOUNT_DATA_REPORT_EXPORT_AS_TXT_TITLE",
                            comment: "Users can request a report of their account data. They can choose to export it as plain text (TXT) or as JSON. This is the title on the button that switches to plain text mode.",
                        ),
                        subtitle: OWSLocalizedString(
                            "ACCOUNT_DATA_REPORT_EXPORT_AS_TXT_SUBTITLE",
                            comment: "Users can request a report of their account data. They can choose to export it as plain text (TXT) or as JSON. This is the subtitle on the button that switches to plain text mode.",
                        ),
                        accessoryType: selectedFileType == .text ? .checkmark : .none,
                    )
                },
                actionBlock: { [weak self] in
                    self?.didSelectFileType(.text)
                },
            ),
            .init(
                customCellBlock: {
                    return OWSTableItem.buildImageCell(
                        itemName: OWSLocalizedString(
                            "ACCOUNT_DATA_REPORT_EXPORT_AS_JSON_TITLE",
                            comment: "Users can request a report of their account data. They can choose to export it as plain text (TXT) or as JSON. This is the title on the button that switches to JSON mode.",
                        ),
                        subtitle: OWSLocalizedString(
                            "ACCOUNT_DATA_REPORT_EXPORT_AS_JSON_SUBTITLE",
                            comment: "Users can request a report of their account data. They can choose to export it as plain text (TXT) or as JSON. This is the subtitle on the button that switches to JSON mode.",
                        ),
                        accessoryType: selectedFileType == .json ? .checkmark : .none,
                    )
                },
                actionBlock: { [weak self] in
                    self?.didSelectFileType(.json)
                },
            ),
        ])
    }

    private func exportButtonSection() -> OWSTableSection {
        let result = OWSTableSection(items: [.init(customCellBlock: { [weak self] in
            let cell = UITableViewCell()
            guard let self else { return cell }

            cell.contentView.addSubview(self.exportButton)
            self.exportButton.autoPinHeightToSuperviewMargins()
            self.exportButton.autoPinWidthToSuperview(withMargin: 12)

            return cell
        })])
        result.hasBackground = false
        result.footerTitle = OWSLocalizedString(
            "ACCOUNT_DATA_REPORT_FOOTER",
            comment: "Users can request a report of their account data. This text appears at the bottom of this screen, offering more information.",
        )
        return result
    }

    // MARK: - Events

    private func didTapExport() {
        let request = AccountDataReportRequestFactory.createAccountDataReportRequest()

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: true,
            asyncBlock: { modal in
                do {
                    let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
                    guard response.responseStatusCode == 200 else {
                        throw response.asError()
                    }
                    let report = try AccountDataReport(rawData: response.responseBodyData ?? Data())
                    modal.dismissIfNotCanceled(completionIfNotCanceled: { [weak self] in
                        self?.confirmExport {
                            self?.didConfirmExport(of: report)
                        }
                    })
                } catch {
                    Logger.warn("\(error)")
                    modal.dismissIfNotCanceled(completionIfNotCanceled: { [weak self] in
                        self?.didRequestFail()
                    })
                }
            },
        )
    }

    private func didRequestFail() {
        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString(
                "ACCOUNT_DATA_REPORT_ERROR_TITLE",
                comment: "Users can request a report of their account data. If this request fails (probably because of a network connection problem), they will see an error sheet. This is the title on that error.",
            ),
            message: OWSLocalizedString(
                "ACCOUNT_DATA_REPORT_ERROR_MESSAGE",
                comment: "Users can request a report of their account data. If this request fails (probably because of a network connection problem), they will see an error sheet. This is the message on that error.",
            ),
        )
    }

    private func didSelectFileType(_ fileType: FileType) {
        self.selectedFileType = fileType
    }

    private func confirmExport(didConfirm: @escaping () -> Void) {
        let actionSheet = ActionSheetController(
            message: OWSLocalizedString(
                "ACCOUNT_DATA_REPORT_CONFIRM_EXPORT_MESSAGE",
                comment: "Users can request a report of their account data. Before they get their account export, they are warned to only share account data with trustworthy sources. This is the message on that warning.",
            ),
        )

        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "ACCOUNT_DATA_REPORT_CONFIRM_EXPORT_CONFIRM_BUTTON",
                comment: "Users can request a report of their account data. Before they get their account export, they are warned to only share account data with trustworthy sources. This is the button on that warning, and tapping it lets users continue.",
            ),
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
            completion: cleanup,
        )
    }

    private func prepareForSharing(
        report: AccountDataReport,
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

        // In theory, we could put the temporary file directly in the top-level temporary directory.
        // In practice, this doesn't work when sharing back into Signal. We don't understand why
        // but suspect a platform bug (or, at best, an error message that didn't help us figure out
        // the source of the problem).
        let temporaryDirUrl = URL(
            fileURLWithPath: OWSTemporaryDirectory(),
        ).appendingPathComponent(UUID().uuidString)
        let temporaryFileUrl = temporaryDirUrl.appendingPathComponent(
            // This isn't localized because the report is *also* not localized.
            "account-data.\(fileExtension)",
            isDirectory: false,
        )
        OWSFileSystem.ensureDirectoryExists(temporaryDirUrl.path)

        let activityItem: Any
        let cleanup: () -> Void

        do {
            try data.write(to: temporaryFileUrl, options: .completeFileProtection)
            activityItem = temporaryFileUrl
            cleanup = {
                do {
                    try OWSFileSystem.deleteFile(url: temporaryDirUrl)
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
