//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class TransferProgressView: UIStackView {
    let progress: Progress

    let progressBar: UIProgressView = {
        let progressBar = UIProgressView()
        progressBar.progressTintColor = .ows_accentBlue
        progressBar.trackTintColor = Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05
        return progressBar
    }()
    let topLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = .dynamicTypeBody
        label.textColor = Theme.primaryTextColor
        label.textAlignment = .center
        return label
    }()
    let bottomLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBody2
        label.textColor = Theme.secondaryTextAndIconColor
        label.textAlignment = .center
        return label
    }()
    let dateComponentsFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.includesApproximationPhrase = true
        formatter.includesTimeRemainingPhrase = true
        return formatter
    }()

    init(progress: Progress) {
        self.progress = progress
        super.init(frame: .zero)

        axis = .vertical
        spacing = 16

        addArrangedSubview(topLabel)
        addArrangedSubview(progressBar)
        addArrangedSubview(bottomLabel)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isObservingProgress = false
    func startUpdatingProgress() {
        AssertIsOnMainThread()

        guard !isObservingProgress else { return }

        progressBar.progressTintColor = .ows_accentBlue
        topLabel.text = nil

        progress.addObserver(self, forKeyPath: "fractionCompleted", options: .initial, context: nil)
        isObservingProgress = true
    }

    func stopUpdatingProgress() {
        AssertIsOnMainThread()

        guard isObservingProgress else { return }

        progress.removeObserver(self, forKeyPath: "fractionCompleted")
        isObservingProgress = false
    }

    func renderError(text: String) {
        stopUpdatingProgress()

        progressBar.progressTintColor = .ows_accentRed

        topLabel.textColor = .ows_accentRed
        topLabel.text = text
        bottomLabel.text = nil
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "fractionCompleted" else {
            return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }

        DispatchMainThreadSafe {
            guard self.isObservingProgress else { return }

            self.topLabel.text = "\(Int(self.progress.fractionCompleted * 100))%"
            self.progressBar.setProgress(Float(self.progress.fractionCompleted), animated: true)

            if let estimatedTime = self.progress.estimatedTimeRemaining, estimatedTime.isFinite {
                self.bottomLabel.text = self.dateComponentsFormatter.string(from: estimatedTime)
            } else {
                self.bottomLabel.text = nil
            }
        }
    }
}
