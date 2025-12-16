//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - CallQualitySurveyNavigationController

final class CallQualitySurveyNavigationController: UINavigationController {
    init() {
        let vc = CallQualitySurveyRatingViewController()
        super.init(rootViewController: vc)
        vc.navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #unavailable(iOS 26) {
            view.backgroundColor = .systemGroupedBackground
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        // The presentation jumps if you try to set the height here,
        // pre-iOS 26 jumps if you don't set it here 🤷‍♀️
        if #unavailable(iOS 26) {
            reloadHeight()
        }
    }

    private var hasSetUpDetents = false
    private func setUpDetents() {
        hasSetUpDetents = true
        if #available(iOS 16.0, *) {
            sheetPresentationController?.detents = [.custom(identifier: .medium, resolver: { [weak self] context in
                min(
                    self?.topViewHeight() ?? context.maximumDetentValue,
                    context.maximumDetentValue,
                )
            })]
        } else {
            sheetPresentationController?.detents = [.medium(), .large()]
        }
    }

    @available(iOS 16.0, *)
    private func topViewHeight() -> CGFloat? {
        (viewControllers.last as? CallQualitySurveySheetViewController)?.customSheetHeight()
    }

    private func addFadeTransition() {
        let transition: CATransition = CATransition()
        transition.duration = 0.3
        transition.type = CATransitionType.fade
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(transition, forKey: nil)
    }

    func didTapHadIssues() {
        let vc = CallQualitySurveyIssuesViewController()
        vc.navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)
        vc.navigationItem.leftBarButtonItem = makeBackButton()
        addFadeTransition()
        pushViewController(vc, animated: false)
    }

    // [Call Quality Survey] TODO: Pass state through
    func doneSelectingIssues() {
        let vc = SurveyDebugLogViewController()
        vc.navigationItem.rightBarButtonItem = .cancelButton(dismissingFrom: self)
        vc.navigationItem.leftBarButtonItem = makeBackButton()
        addFadeTransition()
        pushViewController(vc, animated: false)
    }

    private func makeBackButton() -> UIBarButtonItem {
        UIBarButtonItem.button(
            image: UIImage(resource: .chevronLeftBold28),
            style: .plain
        ) { [weak self] in
            self?.didTapBack()
        }
    }

    func didTapBack() {
        addFadeTransition()
        popViewController(animated: false)
    }

    func reloadHeight() {
        guard hasSetUpDetents else {
            setUpDetents()
            return
        }

        guard #available(iOS 16, *), let sheet = sheetPresentationController else { return }
        sheet.animateChanges {
            sheet.invalidateDetents()
        }
    }
}

// MARK: - CallQualitySurveySheetViewController

class CallQualitySurveySheetViewController: UIViewController {
    var sheetNav: CallQualitySurveyNavigationController? {
        navigationController as? CallQualitySurveyNavigationController
    }

    @available(iOS 16.0, *)
    func customSheetHeight() -> CGFloat? {
        // Override this in subclasses
        owsFailDebug("customSheetHeight not set")
        return nil
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        DispatchQueue.main.async {
            self.reloadHeight()
        }
    }

    func reloadHeight() {
        sheetNav?.reloadHeight()
    }
}
