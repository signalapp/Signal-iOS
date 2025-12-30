//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

extension ConversationInputToolbar {

    class VoiceMemoLockView: UIView {

        override init(frame: CGRect) {
            super.init(frame: frame)

            directionalLayoutMargins = .init(top: 12, leading: 8, bottom: 8, trailing: 8)

            if #available(iOS 26, *) {
                visualEffectView.clipsToBounds = true
                visualEffectView.cornerConfiguration = .capsule()
            }
            addSubview(visualEffectView)
            visualEffectView.contentView.addSubview(lockIconView)
            visualEffectView.contentView.addSubview(chevronView)
            addConstraints([
                lockIconView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                lockIconView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                lockIconView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

                chevronView.centerXAnchor.constraint(equalTo: centerXAnchor),
                chevronView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
                iconSpacingConstraint,
            ])
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            visualEffectView.frame = bounds

            if #unavailable(iOS 26) {
                let maskLayer = CAShapeLayer()
                maskLayer.path = UIBezierPath(
                    roundedRect: bounds,
                    cornerRadius: bounds.size.smallerAxis / 2,
                ).cgPath
                visualEffectView.layer.mask = maskLayer
            }
        }

        func update(ratioComplete: CGFloat) {
            iconSpacingConstraint.constant = CGFloat.lerp(left: initialIconSpacing, right: 0, alpha: ratioComplete)
        }

        // MARK: - Subviews

        private let initialIconSpacing: CGFloat = 16

        private lazy var iconSpacingConstraint = chevronView.topAnchor.constraint(equalTo: lockIconView.bottomAnchor, constant: initialIconSpacing)

        private lazy var lockIconView: UIImageView = {
            let imageView = UIImageView(image: UIImage(imageLiteralResourceName: "lock"))
            imageView.tintColor = Style.primaryTextColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            return imageView
        }()

        private lazy var chevronView: UIImageView = {
            let imageView = UIImageView(image: UIImage(imageLiteralResourceName: "chevron-up"))
            imageView.tintColor = Style.primaryTextColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            return imageView
        }()

        private lazy var visualEffectView: UIVisualEffectView = {
            let visualEffect: UIVisualEffect = {
                if #available(iOS 26, *) {
                    UIGlassEffect(style: .regular)
                } else {
                    UIBlurEffect(style: .systemThinMaterial)
                }
            }()
            return UIVisualEffectView(effect: visualEffect)
        }()
    }

    class VoiceMessageDraftView: UIView, AudioPlayerDelegate {
        private let playbackTimeLabel: UILabel = {
            let label = UILabel()
            label.font = .monospacedDigitSystemFont(ofSize: UIFont.dynamicTypeSubheadlineClamped.pointSize, weight: .regular)
            label.textColor = Style.secondaryTextColor
            label.setContentHuggingHorizontalHigh()
            label.setCompressionResistanceHorizontalHigh()
            return label
        }()

        private lazy var playPauseButton: LottieToggleButton = {
            let button = LottieToggleButton()
            button.animationName = "playPauseButton"
            button.animationSize = CGSize(square: 24)
            button.animationSpeed = 3
            button.setValueProvider(
                ColorValueProvider(Theme.primaryIconColor.lottieColorValue),
                keypath: AnimationKeypath(keypath: "**.Fill 1.Color"),
            )
            button.addAction(
                UIAction { [weak self] _ in
                    self?.didTogglePlayPause()
                },
                for: .primaryActionTriggered,
            )
            return button
        }()

        private let waveformView: AudioWaveformProgressView
        private let voiceMessageInterruptedDraft: VoiceMessageInterruptedDraft

        var audioPlaybackState: AudioPlaybackState = .stopped

        init(
            voiceMessageInterruptedDraft: VoiceMessageInterruptedDraft,
            mediaCache: CVMediaCache,
        ) {
            self.voiceMessageInterruptedDraft = voiceMessageInterruptedDraft
            self.waveformView = AudioWaveformProgressView(mediaCache: mediaCache)

            super.init(frame: .zero)

            directionalLayoutMargins = .init(hMargin: 12, vMargin: 0)

            voiceMessageInterruptedDraft.audioPlayer.delegate = self

            waveformView.thumbColor = .Signal.label
            waveformView.playedColor = .Signal.label
            waveformView.unplayedColor = .Signal.tertiaryLabel
            waveformView.audioWaveformTask = voiceMessageInterruptedDraft.audioWaveformTask

            let stackView = UIStackView(arrangedSubviews: [
                playPauseButton,
                waveformView,
                playbackTimeLabel,
            ])
            stackView.axis = .horizontal
            stackView.spacing = 12
            stackView.alignment = .center
            addSubview(stackView)
            stackView.translatesAutoresizingMaskIntoConstraints = false
            addConstraints([
                waveformView.heightAnchor.constraint(equalToConstant: 28),

                stackView.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
                stackView.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor),
                stackView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            ])

            addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))

            updateAudioProgress(currentTime: 0)
        }

        deinit {
            voiceMessageInterruptedDraft.audioPlayer.stop()
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private var isScrubbing = false

        @objc
        private func handlePan(_ sender: UIPanGestureRecognizer) {
            let location = sender.location(in: waveformView)
            var progress = CGFloat.clamp01(location.x / waveformView.width)

            // When in RTL mode, the slider moves in the opposite direction so inverse the ratio.
            if CurrentAppContext().isRTL {
                progress = 1 - progress
            }

            guard let duration = voiceMessageInterruptedDraft.duration else {
                return owsFailDebug("Missing duration")
            }

            let currentTime = duration * Double(progress)

            switch sender.state {
            case .began:
                isScrubbing = true
                updateAudioProgress(currentTime: currentTime)
            case .changed:
                updateAudioProgress(currentTime: currentTime)
            case .ended:
                isScrubbing = false
                voiceMessageInterruptedDraft.audioPlayer.setCurrentTime(currentTime)
            case .cancelled, .failed, .possible:
                isScrubbing = false
            @unknown default:
                isScrubbing = false
            }
        }

        func updateAudioProgress(currentTime: TimeInterval) {
            guard let duration = voiceMessageInterruptedDraft.duration else { return }
            waveformView.value = CGFloat.clamp01(CGFloat(currentTime / duration))
            playbackTimeLabel.text = OWSFormat.localizedDurationString(from: duration - currentTime)
        }

        private func didTogglePlayPause() {
            AppEnvironment.shared.cvAudioPlayerRef.stopAll()
            playPauseButton.setSelected(!playPauseButton.isSelected, animated: true)
            voiceMessageInterruptedDraft.audioPlayer.togglePlayState()
        }

        func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float) {
            guard !isScrubbing else { return }
            updateAudioProgress(currentTime: progress)
        }

        func audioPlayerDidFinish() {
            playPauseButton.setSelected(false, animated: true)
            updateAudioProgress(currentTime: 0)
        }
    }
}
