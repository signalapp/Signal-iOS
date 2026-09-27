//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SignalServiceKit
import SignalUI

final class SurveyDebugLogViewController: CallQualitySurveySheetViewController {
    private var sizeChangeSubscription: AnyCancellable?

    override var stackViewInsets: UIEdgeInsets { .init(hMargin: 16, vMargin: 0) }

    private let tableViewController = OWSTableViewController2()

    private var shouldSubmitDebugLogs = true
    private var logs: DebugLogs

    private let rating: CallQualitySurvey.Rating

    init(rating: CallQualitySurvey.Rating) {
        self.logs = DebugLogs(dumper: .fromGlobals())
        self.rating = rating
        super.init()
    }

    @MainActor
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_DEBUG_LOG_TITLE",
            comment: "Title for the debug log sharing screen in the call quality survey",
        )

        let headerLabel = createHeaderView()
        let headerContainer = UIView()
        headerContainer.addSubview(headerLabel)
        headerLabel.autoPinEdgesToSuperviewEdges(with: .init(hMargin: 36, vMargin: 0))
        stackView.addArrangedSubview(headerContainer)

        // The table view is sized to its content and scrolls with the rest of
        // the sheet's stack view.
        tableViewController.backgroundStyle = .none
        tableViewController.tableView.isScrollEnabled = false
        addChild(tableViewController)
        let tableViewHeight = tableViewController.view.autoSetDimension(.height, toSize: 0)
        stackView.addArrangedSubview(tableViewController.view)
        tableViewController.didMove(toParent: self)

        let section = OWSTableSection(
            title: nil,
            items: [
                .switch(
                    withText: OWSLocalizedString(
                        "CALL_QUALITY_SURVEY_DEBUG_LOG_TOGGLE",
                        comment: "Label for the toggle to share debug log in the call quality survey",
                    ),
                    isOn: { [weak self] in
                        self?.shouldSubmitDebugLogs ?? false
                    },
                    actionBlock: { [weak self] control in
                        self?.shouldSubmitDebugLogs = control.isOn
                    },
                ),
            ],
        )
        section.customFooterView = createFooterView()

        tableViewController.setContents(OWSTableContents(sections: [section]))

        let continueButton = UIButton(primaryAction: .init { [weak self] _ in
            self?.submit()
        })
        continueButton.configuration = .largePrimary(title: OWSLocalizedString(
            "CALL_QUALITY_SURVEY_SUBMIT_BUTTON",
            comment: "Button text to submit the call quality survey",
        ))
        let buttonContainer = UIView()
        buttonContainer.addSubview(continueButton)
        continueButton.autoPinEdgesToSuperviewEdges(with: .init(hMargin: 12, vMargin: 0))
        stackView.addArrangedSubview(buttonContainer)

        let tableView = tableViewController.tableView
        sizeChangeSubscription = tableView
            .publisher(for: \.contentSize)
            .removeDuplicates()
            .sink { [weak tableView] contentSize in
                guard let tableView else { return }
                tableViewHeight.constant = contentSize.height + tableView.contentInset.totalHeight
            }
    }

    private func createHeaderView() -> UIView {
        let textView = LinkingTextView { [weak self] in
            self?.showDiagnosticsPreview()
        }
        textView.attributedText = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_DEBUG_LOG_HEADER",
            comment: "Header text explaining the purpose of sharing debug logs in the call quality survey. The text inside the <link> tags is tappable for viewing the diagnostic information.",
        )
        .styled(
            with: .font(.dynamicTypeSubheadline),
            .color(.Signal.secondaryLabel),
            .alignment(.center),
            .xmlRules([.style("link", .init(.link(.Support.generic)))]),
        )
        return textView
    }

    private func createFooterView() -> UIView {
        let container = UIView()

        let textView = LinkingTextView { [weak self] in
            guard let self else { return }
            self.logs.showPreview(from: self)
        }
        textView.attributedText = .composed(of: [
            OWSLocalizedString(
                "CALL_QUALITY_SURVEY_DEBUG_LOG_FOOTER",
                comment: "Footer text explaining what debug logs contain in the call quality survey",
            ),
            " ",
            OWSLocalizedString(
                "CALL_QUALITY_SURVEY_DEBUG_LOG_PREVIEW_LINK",
                comment: "Link text to open a preview of debug logs in the call quality survey. Appended to CALL_QUALITY_SURVEY_DEBUG_LOG_FOOTER",
            ).styled(with: .link(.Support.generic)),
        ]).styled(
            with: .font(.dynamicTypeFootnote),
            .color(.Signal.secondaryLabel),
        )
        container.addSubview(textView)
        textView.autoPinEdgesToSuperviewEdges(with: .init(top: 12, leading: 20, bottom: 0, trailing: 20))

        return container
    }

    private func showDiagnosticsPreview() {
        let protoJSON = sheetNav?.callQualitySurveyManager.protoJSONPreview(rating: rating)
        guard let protoJSON else { return }

        let vc = OWSTableViewController2()
        let section = OWSTableSection(items: [
            .init(customCellBlock: {
                let cell = UITableViewCell()

                let textView = UITextView()
                textView.backgroundColor = .clear
                textView.isOpaque = false
                textView.isEditable = false
                textView.textContainerInset = .zero
                textView.contentInset = .zero
                textView.textContainer.lineFragmentPadding = 0
                textView.isScrollEnabled = false
                textView.isSelectable = false

                textView.font = .dynamicTypeSubheadline
                textView.textColor = .Signal.secondaryLabel
                textView.text = protoJSON

                cell.contentView.addSubview(textView)
                textView.autoPinEdgesToSuperviewMargins()

                return cell
            }),
        ])
        let contents = OWSTableContents(
            title: OWSLocalizedString(
                "CALL_QUALITY_SURVEY_DIAGNOSTICS_TITLE",
                comment: "Title for preview of the call diagnostic info that will be sent with the survey",
            ),
            sections: [section],
        )
        vc.setContents(contents)
        vc.navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: vc)
        let nav = OWSNavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func submit() {
        sheetNav?.submit(
            rating: self.rating,
            logsToSubmit: shouldSubmitDebugLogs ? logs : nil,
        )
    }
}
