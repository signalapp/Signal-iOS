//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
        label.font = .ows_dynamicTypeBody
        label.textColor = Theme.primaryTextColor
        label.textAlignment = .center
        return label
    }()
    let bottomLabel: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeBody2
        label.textColor = Theme.secondaryTextAndIconColor
        label.textAlignment = .center
        return label
    }()
    let dateComponentsFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
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

    func startUpdatingProgress() {
        AssertIsOnMainThread()

        progressBar.progressTintColor = .ows_accentBlue
        topLabel.text = nil

        progress.addObserver(self, forKeyPath: "fractionCompleted", options: .initial, context: nil)
    }

    func stopUpdatingProgress() {
        AssertIsOnMainThread()

        progress.removeObserver(self, forKeyPath: "fractionCompleted")
    }

    func renderError(text: String) {
        stopUpdatingProgress()

        progressBar.progressTintColor = .ows_accentRed

        // TODO: error icon
        topLabel.text = text
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

        DispatchQueue.main.async {
            self.topLabel.text = "\(Int(self.progress.fractionCompleted * 100))%"
            self.progressBar.setProgress(Float(self.progress.fractionCompleted), animated: true)

            if #available(iOS 11, *), let estimatedTime = self.progress.estimatedTimeRemaining, estimatedTime.isFinite {
                self.bottomLabel.text = self.dateComponentsFormatter.string(from: estimatedTime)
            } else {
                self.bottomLabel.text = nil
            }
        }
    }
}
