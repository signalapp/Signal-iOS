//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import SignalUI

extension DonationViewsUtil {
    @MainActor
    public static func wrapInProgressView<T, E>(
        from viewController: UIViewController,
        operation: () async throws(E) -> T,
    ) async throws(E) -> T {
        let backdropView = UIView()
        backdropView.backgroundColor = .Signal.backdrop
        backdropView.alpha = 0
        viewController.view.addSubview(backdropView)
        backdropView.autoPinEdgesToSuperviewEdges()

        let progressViewContainer = UIView()
        progressViewContainer.backgroundColor = .Signal.background
        progressViewContainer.layer.cornerRadius = 12
        backdropView.addSubview(progressViewContainer)
        progressViewContainer.autoCenterInSuperview()

        let progressView = AnimatedProgressView(loadingText: OWSLocalizedString(
            "SUSTAINER_VIEW_PROCESSING_PAYMENT",
            comment: "Loading indicator on the sustainer view",
        ))
        viewController.view.addSubview(progressView)
        progressView.autoCenterInSuperview()
        progressViewContainer.autoMatch(.width, to: .width, of: progressView, withOffset: 32)
        progressViewContainer.autoMatch(.height, to: .height, of: progressView, withOffset: 32)

        progressView.startAnimating {
            backdropView.alpha = 1
        }

        let result = await Result(catching: { () async throws(E) in
            try await operation()
        })

        await withCheckedContinuation { continuation in
            progressView.stopAnimating(success: result.isSuccess) {
                backdropView.alpha = 0
            } completion: {
                backdropView.removeFromSuperview()
                progressView.removeFromSuperview()
                continuation.resume()
            }
        }

        return try result.get()
    }
}
