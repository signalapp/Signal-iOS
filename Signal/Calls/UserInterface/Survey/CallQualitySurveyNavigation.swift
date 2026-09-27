//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - CallQualitySurveyNavigationController

final class CallQualitySurveyNavigationController: SheetNavigationController {
    let callQualitySurveyManager: CallQualitySurveyManager

    override var sheetBackgroundColor: UIColor { .systemGroupedBackground }

    init(callQualitySurveyManager: CallQualitySurveyManager) {
        self.callQualitySurveyManager = callQualitySurveyManager
        let vc = CallQualitySurveyRatingViewController()
        super.init(rootViewController: vc)
        vc.navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func didTapHadIssues() {
        let vc = CallQualitySurveyIssuesViewController()
        vc.navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)
        vc.navigationItem.leftBarButtonItem = makeBackButton()
        pushViewControllerWithFade(vc)
    }

    func doneSelectingIssues(rating: CallQualitySurvey.Rating) {
        let vc = SurveyDebugLogViewController(rating: rating)
        vc.navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)
        vc.navigationItem.leftBarButtonItem = makeBackButton()
        pushViewControllerWithFade(vc)
    }

    func submit(
        rating: CallQualitySurvey.Rating,
        logsToSubmit: DebugLogs?,
    ) {
        callQualitySurveyManager.submit(
            rating: rating,
            logsToSubmit: logsToSubmit,
        )
        let host = presentingViewController
        dismiss(animated: true) {
            host?.presentToast(text: OWSLocalizedString(
                "CALL_QUALITY_SURVEY_COMPLETION_TOAST",
                comment: "Title for toast which appears after submitting a call quality survey",
            ))
        }
    }

    private func makeBackButton() -> UIBarButtonItem {
        .button(image: UIImage(resource: .chevronLeftBold28)) { [weak self] in
            self?.didTapBack()
        }
    }

    func didTapBack() {
        popViewControllerWithFade()
    }
}

// MARK: - CallQualitySurveySheetViewController

class CallQualitySurveySheetViewController: NavStackSheetViewController {
    override var minimumBottomInsetIncludingSafeArea: CGFloat { 24 }

    var sheetNav: CallQualitySurveyNavigationController? {
        navigationController as? CallQualitySurveyNavigationController
    }
}
