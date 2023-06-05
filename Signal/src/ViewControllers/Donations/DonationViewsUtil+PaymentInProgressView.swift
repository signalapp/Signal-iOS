//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

extension DonationViewsUtil {
    public static func wrapPromiseInProgressView<T>(
        from viewController: UIViewController,
        promise wrappedPromise: Promise<T>
    ) -> Promise<T> {
        guard let view = viewController.view else {
            owsFail("Cannot wrap promise in progress view when the view doesn't exist")
        }

        let backdropView = UIView()
        backdropView.backgroundColor = Theme.backdropColor
        backdropView.alpha = 0
        view.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()

        let progressViewContainer = UIView()
        progressViewContainer.backgroundColor = Theme.backgroundColor
        progressViewContainer.layer.cornerRadius = 12
        backdropView.addSubview(progressViewContainer)
        progressViewContainer.autoCenterInSuperview()

        let progressView = AnimatedProgressView(loadingText: OWSLocalizedString(
            "SUSTAINER_VIEW_PROCESSING_PAYMENT",
            comment: "Loading indicator on the sustainer view"
        ))
        view.addSubview(progressView)
        progressView.autoCenterInSuperview()
        progressViewContainer.autoMatch(.width, to: .width, of: progressView, withOffset: 32)
        progressViewContainer.autoMatch(.height, to: .height, of: progressView, withOffset: 32)

        progressView.startAnimating {
            backdropView.alpha = 1
        }

        let (promise, future) = Promise<T>.pending()

        wrappedPromise.done(on: DispatchQueue.main) { result in
            progressView.stopAnimating(success: true) {
                backdropView.alpha = 0
            } completion: {
                backdropView.removeFromSuperview()
                progressView.removeFromSuperview()

                future.resolve(result)
            }
        }.catch(on: DispatchQueue.main) { error in
            progressView.stopAnimating(success: false) {
                backdropView.alpha = 0
            } completion: {
                backdropView.removeFromSuperview()
                progressView.removeFromSuperview()

                future.reject(error)
            }
        }

        return promise
    }
}
