//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import Combine

final class SurveyDebugLogViewController: CallQualitySurveySheetViewController {
    private var sizeChangeSubscription: AnyCancellable?

    private let headerContainer = UIView()
    private let bottomStackView = UIStackView()

    private let tableViewController = OWSTableViewController2()

    private var shouldSubmitDebugLog = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_DEBUG_LOG_TITLE",
            comment: "Title for the debug log sharing screen in the call quality survey"
        )

        let headerLabel = UILabel()
        headerLabel.text = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_DEBUG_LOG_HEADER",
            comment: "Header text explaining the purpose of sharing debug logs in the call quality survey"
        )
        headerLabel.numberOfLines = 0
        headerLabel.font = .dynamicTypeSubheadline
        headerLabel.textColor = .Signal.secondaryLabel
        headerLabel.textAlignment = .center
        headerContainer.addSubview(headerLabel)
        headerLabel.autoPinEdgesToSuperviewMargins(with: .init(
            top: 0,
            leading: 36,
            bottom: 0,
            trailing: 36
        ))
        view.addSubview(headerContainer)
        headerContainer.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        headerContainer.layoutMargins = .zero
        headerContainer.preservesSuperviewLayoutMargins = true

        tableViewController.backgroundStyle = .none
        addChild(tableViewController)
        view.addSubview(tableViewController.view)
        tableViewController.tableView.alwaysBounceVertical = false
        tableViewController.view.autoPinWidthToSuperview()
        tableViewController.view.autoPinEdge(.top, to: .bottom, of: headerContainer)
        tableViewController.didMove(toParent: self)

        let section = OWSTableSection(
            title: nil,
            items: [
                .switch(
                    withText: OWSLocalizedString(
                        "CALL_QUALITY_SURVEY_DEBUG_LOG_TOGGLE",
                        comment: "Label for the toggle to share debug log in the call quality survey"
                    ),
                    isOn: { [weak self] in
                        self?.shouldSubmitDebugLog ?? false
                    },
                    actionBlock: { [weak self] control in
                        self?.shouldSubmitDebugLog = control.isOn
                    }
                ),
            ],
            footerTitle: OWSLocalizedString(
                "CALL_QUALITY_SURVEY_DEBUG_LOG_FOOTER",
                comment: "Footer text explaining what debug logs contain in the call quality survey"
            )
        )

        tableViewController.setContents(OWSTableContents(sections: [section]))

        bottomStackView.axis = .vertical
        bottomStackView.spacing = 24
        bottomStackView.isLayoutMarginsRelativeArrangement = true
        bottomStackView.directionalLayoutMargins = .init(hMargin: 12, vMargin: 0)
        view.addSubview(bottomStackView)
        bottomStackView.autoPinEdge(.top, to: .bottom, of: tableViewController.view)
        bottomStackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)

        let continueButton = UIButton(primaryAction: .init { [weak self] _ in
            // [Call Quality Survey] TODO: Implement
            self?.dismiss(animated: true)
        })
        continueButton.configuration = .largePrimary(title: OWSLocalizedString(
            "CALL_QUALITY_SURVEY_SUBMIT_BUTTON",
            comment: "Button text to submit the call quality survey"
        ))
        bottomStackView.addArrangedSubview(continueButton)

        if #available(iOS 16.0, *) {
            sizeChangeSubscription = tableViewController.tableView
                .publisher(for: \.contentSize)
                .removeDuplicates()
                .sink { [weak self] contentSize in
                    DispatchQueue.main.async {
                        self?.reloadHeight()
                    }
                }
        }
    }

    override func customSheetHeight() -> CGFloat? {
        let headerHeight = headerContainer.height
        let collectionViewHeight = tableViewController.tableView.contentSize.height + tableViewController.tableView.contentInset.totalHeight
        let bottomStackHeight = bottomStackView.height
        return headerHeight + collectionViewHeight + bottomStackHeight
    }
}
