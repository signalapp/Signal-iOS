//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import Photos
import SignalMessaging
import UIKit

protocol VideoEditorViewDelegate: AnyObject {
    func videoEditorViewPlaybackTimeDidChange(_ videoEditorView: VideoEditorView)
}

protocol VideoEditorViewControllerProviding: AnyObject {
    func viewController(forVideoEditorView videoEditorView: VideoEditorView) -> UIViewController
}

// A view for editing outgoing video attachments.
class VideoEditorView: UIView {

    weak var delegate: VideoEditorViewDelegate?
    weak var dataSource: VideoEditorDataSource?
    weak var viewControllerProvider: VideoEditorViewControllerProviding?

    private let model: VideoEditorModel

    var isTrimmingVideo: Bool = false

    private lazy var playerView: VideoPlayerView = {
        let playerView = VideoPlayerView()
        playerView.videoPlayer = OWSVideoPlayer(url: URL(fileURLWithPath: model.srcVideoPath))
        playerView.delegate = self
        return playerView
    }()
    private lazy var playButton: UIButton = {
        let playButton = RoundMediaButton(image: #imageLiteral(resourceName: "play-solid-34"), backgroundStyle: .blur)
        playButton.accessibilityLabel = OWSLocalizedString("PLAY_BUTTON_ACCESSABILITY_LABEL",
                                                           comment: "Accessibility label for button to start media playback")
        // this makes the blur circle 72 pts in diameter
        playButton.contentEdgeInsets = UIEdgeInsets(margin: 26)
        // play button must be slightly off-center to appear centered
        playButton.imageEdgeInsets = UIEdgeInsets(top: 0, leading: 3, bottom: 0, trailing: -3)
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)
        return playButton
    }()

    required init(model: VideoEditorModel,
                  delegate: VideoEditorViewDelegate,
                  dataSource: VideoEditorDataSource,
                  viewControllerProvider: VideoEditorViewControllerProviding) {

        self.model = model
        self.delegate = delegate
        self.dataSource = dataSource
        self.viewControllerProvider = viewControllerProvider

        super.init(frame: .zero)

        backgroundColor = .black
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Views

    func configureSubviews() {
        let aspectRatio: CGFloat = model.displaySize.width / model.displaySize.height
        addSubviewWithScaleAspectFitLayout(view: playerView, aspectRatio: aspectRatio)
        playerView.setContentHuggingLow()
        playerView.setCompressionResistanceLow()
        playerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapPlayerView(_:))))

        addSubview(playButton)
        playButton.autoAlignAxis(.horizontal, toSameAxisOf: playerView)
        playButton.autoAlignAxis(.vertical, toSameAxisOf: playerView)

        ensureSeekReflectsTrimming()
    }

    private func addSubviewWithScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) {
        addSubview(view)
        // This emulates the behavior of contentMode = .scaleAspectFit using iOS auto layout constraints.
        addConstraints({
            let constraints = [ view.centerXAnchor.constraint(equalTo: centerXAnchor),
                                view.centerYAnchor.constraint(equalTo: centerYAnchor) ]
            constraints.forEach { $0.priority = .defaultHigh - 100 }
            return constraints
        }())
        addConstraint(view.topAnchor.constraint(greaterThanOrEqualTo: topAnchor))
        view.autoPin(toAspectRatio: aspectRatio)
        view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
        view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .equal)
            view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .equal)
        }
    }

    // MARK: - Event Handlers

    @objc
    private func didTapPlayerView(_ gestureRecognizer: UIGestureRecognizer) {
        togglePlayback()
    }

    @objc
    private func playButtonTapped() {
        togglePlayback()
    }

    private func togglePlayback() {
        if isPlaying {
            pauseVideo()
        } else {
            playVideo()
        }
    }

    // MARK: - Video

    var trimmedStartSeconds: TimeInterval {
        return model.trimmedStartSeconds
    }

    var trimmedEndSeconds: TimeInterval {
        return model.trimmedEndSeconds
    }

    @discardableResult
    func pauseIfPlaying() -> Bool {
        guard playerView.isPlaying else {
            return false
        }
        playerView.pause()
        return true
    }

    func seek(toSeconds seconds: TimeInterval) {
        playerView.seek(to: CMTime(seconds: seconds, preferredTimescale: model.untrimmedDuration.timescale))
    }

    func playVideo() {
        if ensureSeekReflectsTrimming() {
            // If this delay isn't induced OWSVideoPlayer.play() would reset
            // current position to 0, likely because AVPlayer hasn't yet
            // had a chance to update its currentTime.
            DispatchQueue.main.async {
                self.playerView.play()
            }
        } else {
            playerView.play()
        }
    }

    @discardableResult
    func ensureSeekReflectsTrimming() -> Bool {
        var shouldSeekToStart = false
        if currentTimeSeconds < trimmedStartSeconds {
            // If playback cursor is before the start of the clipping,
            // restart playback.
            shouldSeekToStart = true
        } else {
            // If playback cursor is very near the end of the clipping,
            // restart playback.
            let toleranceSeconds: TimeInterval = 0.1
            if currentTimeSeconds > trimmedEndSeconds - toleranceSeconds {
                shouldSeekToStart = true
            }
        }

        if shouldSeekToStart {
            seek(toSeconds: trimmedStartSeconds)
        }
        return shouldSeekToStart
    }

    private func pauseVideo() {
        playerView.pause()
    }

    private var isShowingPlayButton = true

    private func updateControls() {
        AssertIsOnMainThread()

        if isPlaying {
            if isShowingPlayButton {
                isShowingPlayButton = false
                UIView.animate(withDuration: 0.1) {
                    self.playButton.alpha = 0.0
                }
            }
        } else {
            if !isShowingPlayButton {
                isShowingPlayButton = true
                UIView.animate(withDuration: 0.1) {
                    self.playButton.alpha = 1.0
                }
            }
        }
    }

    // MARK: - Actions

    @objc
    private func didTapSave(sender: UIButton) {
        playerView.pause()

        guard let viewControllerProvider = viewControllerProvider else {
            owsFailDebug("Missing viewControllerProvider.")
            return
        }
        let viewController = viewControllerProvider.viewController(forVideoEditorView: self)
        viewController.ows_askForMediaLibraryPermissions { isGranted in
            AssertIsOnMainThread()

            guard isGranted else { return }

            ModalActivityIndicatorViewController.present(fromViewController: viewController, canCancel: false) { modalVC in
                firstly {
                    self.saveVideoPromise()
                }.done(on: DispatchQueue.main) {
                    modalVC.dismiss()
                }.catch { _ in
                    modalVC.dismiss {
                        OWSActionSheets.showErrorAlert(message: OWSLocalizedString("ERROR_COULD_NOT_SAVE_VIDEO", comment: "Error indicating that 'save video' failed."))
                    }
                }
            }
        }
    }

    private func saveVideoPromise() -> Promise<Void> {
        // Creates a copy of a file in a new temporary path
        // The file path returned in a Result is guaranteed valid for the Result's lifetime
        // Making a copy protects us from any modifications to a file we don't own
        func createCopyOfFile(_ path: String) throws -> String {
            guard let fileExtension = path.fileExtension else {
                throw OWSAssertionError("Missing fileExtension.")
            }
            let dstPath = OWSFileSystem.temporaryFilePath(fileExtension: fileExtension)
            try FileManager.default.copyItem(atPath: path, toPath: dstPath)
            return dstPath
        }

        return firstly(on: DispatchQueue.sharedUtility) { () -> Promise<String> in
            guard self.model.needsRender else {
                // Nothing to render, just use the original file
                let copy = try createCopyOfFile(self.model.srcVideoPath)
                return Promise.value(copy)
            }

            return self.model.ensureCurrentRender().result.map(on: DispatchQueue.sharedUtility) { result in
                try createCopyOfFile(result.getResultPath())
            }

        }.then(on: DispatchQueue.sharedUtility) { (videoFilePath: String) -> Promise<Void> in
            Promise { future in
                let videoUrl = URL(fileURLWithPath: videoFilePath)

                PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: videoUrl)
                } completionHandler: { (didSucceed, error) in
                    OWSFileSystem.deleteFileIfExists(videoFilePath)

                    if let error = error {
                        future.reject(error)
                        return
                    }
                    guard didSucceed else {
                        future.reject(OWSAssertionError("Video export failed."))
                        return
                    }
                    future.resolve()
                }
            }
        }
    }
}

extension VideoEditorView: VideoPlaybackState {

    var isPlaying: Bool { playerView.isPlaying }

    var currentTimeSeconds: TimeInterval { playerView.currentTimeSeconds }
}

extension VideoEditorView: VideoPlayerViewDelegate {

    func videoPlayerViewStatusDidChange(_ view: VideoPlayerView) {
        updateControls()
    }

    func videoPlayerViewPlaybackTimeDidChange(_ view: VideoPlayerView) {
        // Trimming the video also changes current playback position
        // and we don't need the code below to be executed when that happens.
        guard !isTrimmingVideo else {
            return
        }

        // Prevent playback past the end of the trimming.
        guard currentTimeSeconds <= trimmedEndSeconds else {
            playerView.stop()
            return
        }

        delegate?.videoEditorViewPlaybackTimeDidChange(self)
    }
}
