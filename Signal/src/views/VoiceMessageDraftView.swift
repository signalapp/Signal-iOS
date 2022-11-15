//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalUI

class VoiceMessageDraftView: UIStackView {
    private let playbackTimeLabel = UILabel()
    private let waveformView: AudioWaveformProgressView
    private let voiceMessageModel: VoiceMessageModel
    private let playPauseButton = LottieToggleButton()

    var audioPlaybackState: AudioPlaybackState = .stopped

    init(voiceMessageModel: VoiceMessageModel,
         mediaCache: CVMediaCache,
         didDeleteCallback: @escaping () -> Void) {
        self.voiceMessageModel = voiceMessageModel

        self.waveformView = AudioWaveformProgressView(mediaCache: mediaCache)

        super.init(frame: .zero)

        axis = .horizontal
        spacing = 8
        alignment = .center
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 0)

        let trashButton = OWSButton {
            voiceMessageModel.audioPlayer.stop()
            Self.databaseStorage.asyncWrite {
                voiceMessageModel.clearDraft(transaction: $0)
            } completion: {
                didDeleteCallback()
            }
        }
        trashButton.setTemplateImageName("trash-solid-24", tintColor: .ows_accentRed)
        trashButton.autoSetDimensions(to: CGSize(square: 24))
        addArrangedSubview(trashButton)

        playPauseButton.animationName = "playPauseButton"
        playPauseButton.animationSize = CGSize(square: 24)
        playPauseButton.animationSpeed = 3
        playPauseButton.addTarget(self, action: #selector(didTogglePlayPause), for: .touchUpInside)

        let playedColor: UIColor = Theme.isDarkThemeEnabled ? .ows_gray15 : .ows_gray60

        let fillColorKeypath = AnimationKeypath(keypath: "**.Fill 1.Color")
        playPauseButton.setValueProvider(
            ColorValueProvider(playedColor.lottieColorValue),
            keypath: fillColorKeypath
        )

        addArrangedSubview(playPauseButton)

        waveformView.thumbColor = playedColor
        waveformView.playedColor = playedColor
        waveformView.unplayedColor = Theme.isDarkThemeEnabled ? .ows_gray60 : .ows_gray25
        waveformView.audioWaveform = voiceMessageModel.audioWaveform
        waveformView.autoSetDimension(.height, toSize: 22)

        addArrangedSubview(waveformView)

        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGestureRecognizer)

        playbackTimeLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_monospaced
        playbackTimeLabel.textColor = Theme.ternaryTextColor
        updateAudioProgress(currentTime: 0)
        addArrangedSubview(playbackTimeLabel)

        voiceMessageModel.audioPlayer.delegate = self
    }

    deinit {
        voiceMessageModel.audioPlayer.stop()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var isScrubbing = false

    @objc
    private func handlePan(_ sender: UIPanGestureRecognizer) {
        let location = sender.location(in: waveformView)
        var progress = CGFloatClamp01(location.x / waveformView.width)

        // When in RTL mode, the slider moves in the opposite direction so inverse the ratio.
        if CurrentAppContext().isRTL {
            progress = 1 - progress
        }

        guard let duration = voiceMessageModel.duration else {
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
            voiceMessageModel.audioPlayer.setCurrentTime(currentTime)
        case .cancelled, .failed, .possible:
            isScrubbing = false
        @unknown default:
            isScrubbing = false
        }
    }

    func updateAudioProgress(currentTime: TimeInterval) {
        guard let duration = voiceMessageModel.duration else { return }
        waveformView.value = CGFloatClamp01(CGFloat(currentTime / duration))
        playbackTimeLabel.text = OWSFormat.localizedDurationString(from: duration - currentTime)
    }

    @objc
    private func didTogglePlayPause() {
        cvAudioPlayer.stopAll()
        playPauseButton.setSelected(!playPauseButton.isSelected, animated: true)
        voiceMessageModel.audioPlayer.togglePlayState()
    }
}

extension VoiceMessageDraftView: OWSAudioPlayerDelegate {

    func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float) {
        guard !isScrubbing else { return }
        updateAudioProgress(currentTime: progress)
    }

    func audioPlayerDidFinish() {
        playPauseButton.setSelected(false, animated: true)
        updateAudioProgress(currentTime: 0)
    }
}
