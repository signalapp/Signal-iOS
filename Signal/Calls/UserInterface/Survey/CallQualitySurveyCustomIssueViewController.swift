//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class CallQualitySurveyCustomIssueViewController: OWSTableViewController2 {
    static let placeholderText: String = OWSLocalizedString(
        "CALL_QUALITY_SURVEY_CUSTOM_ISSUE_PLACEHOLDER",
        comment: "Placeholder text for the custom issue entry in the call quality survey",
    )

    protocol Delegate: AnyObject {
        func didEnterCustomIssue(_ issue: String)
    }

    weak var surveyDelegate: Delegate?

    private let textView = TextViewWithPlaceholder()

    init(issue: String?) {
        super.init()
        textView.text = issue
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = .cancelButton(dismissingFrom: self)
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.doneButtonTapped()
        }

        textView.placeholderText = Self.placeholderText

        let section = OWSTableSection()
        section.add(self.textViewItem(
            textView,
            minimumHeight: 114,
            dataDetectorTypes: [],
        ))

        section.footerTitle = OWSLocalizedString(
            "CALL_QUALITY_SURVEY_CUSTOM_ISSUE_FOOTER",
            comment: "Footer text explaining custom issue descriptions in the call quality survey",
        )

        setContents(OWSTableContents(sections: [section]))
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        textView.becomeFirstResponder()
    }

    private func doneButtonTapped() {
        guard let text = textView.text else { return }
        surveyDelegate?.didEnterCustomIssue(text)
        dismiss(animated: true)
    }

    private func updateNavigation() {
        navigationItem.rightBarButtonItem?.isEnabled = !textView.text.isEmptyOrNil
    }
}

extension CallQualitySurveyCustomIssueViewController: TextViewWithPlaceholderDelegate {
    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        updateNavigation()
    }
}
