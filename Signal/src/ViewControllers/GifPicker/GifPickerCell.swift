//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMessaging
import YYImage

class GifPickerCell: UICollectionViewCell {

    // MARK: Properties

    var imageInfo: GiphyImageInfo? {
        didSet {
            AssertIsOnMainThread()
            owsAssertDebug(imageInfo?.isValidImage != false)

            ensureCellState()
        }
    }

    // Loading and playing GIFs is quite expensive (network, memory, cpu).
    // Here's a bit of logic to not preload offscreen cells that are prefetched.
    var isCellVisible = false {
        didSet {
            AssertIsOnMainThread()

            ensureCellState()
        }
    }

    // We do "progressive" loading by loading stills (jpg or gif) and "animated" gifs.
    // This is critical on cellular connections.
    var stillAssetRequest: ProxiedContentAssetRequest?
    var stillAsset: ProxiedContentAsset?
    var animatedAssetRequest: ProxiedContentAssetRequest?
    var animatedAsset: ProxiedContentAsset?
    var previewView: UIView?
    var activityIndicator: UIActivityIndicatorView?

    override var isSelected: Bool {
        didSet {
            AssertIsOnMainThread()
            ensureCellState()
        }
    }

    // As another bandwidth saving measure, we only fetch the full sized GIF when the user selects it.
    private var gifAssetForSending: GiphyAsset?

    // MARK: Initializers

    deinit {
        stillAssetRequest?.cancel()
        animatedAssetRequest?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageInfo = nil
        isCellVisible = false
        stillAsset = nil
        stillAssetRequest?.cancel()
        stillAssetRequest = nil
        animatedAsset = nil
        animatedAssetRequest?.cancel()
        animatedAssetRequest = nil
        previewView?.removeFromSuperview()
        previewView = nil
        activityIndicator = nil
        isSelected = false
    }

    private func clearStillAssetRequest() {
        stillAssetRequest?.cancel()
        stillAssetRequest = nil
    }

    private func clearAnimatedAssetRequest() {
        animatedAssetRequest?.cancel()
        animatedAssetRequest = nil
    }

    private func clearAssetRequests() {
        clearStillAssetRequest()
        clearAnimatedAssetRequest()
    }

    public func ensureCellState() {
        ensureLoadState()
        ensureViewState()
    }

    public func ensureLoadState() {
        guard isCellVisible else {
            // Don't load if cell is not visible.
            clearAssetRequests()
            return
        }
        guard let imageInfo = imageInfo else {
            // Don't load if cell is not configured.
            clearAssetRequests()
            return
        }
        guard self.animatedAsset == nil else {
            // Don't load if cell is already loaded.
            clearAssetRequests()
            return
        }

        guard let fullSizeAssetDescription = imageInfo.fullSizeAsset,
              let previewAssetDescription = imageInfo.animatedPreviewAsset,
              let stillAssetDescription = imageInfo.stillPreviewAsset else {
            Logger.warn("could not pick gif rendition: \(imageInfo.giphyId)")
            clearAssetRequests()
            return
        }

        self.gifAssetForSending = fullSizeAssetDescription

        // Start still asset request if necessary.
        if stillAsset != nil || animatedAsset != nil {
            clearStillAssetRequest()
        } else if stillAssetRequest == nil {
            stillAssetRequest = GiphyDownloader.giphyDownloader.requestAsset(
                assetDescription: stillAssetDescription,
                priority: .high,
                success: { [weak self] assetRequest, asset in
                    guard let strongSelf = self else { return }
                    if assetRequest != nil && assetRequest != strongSelf.stillAssetRequest {
                        owsFailDebug("Obsolete request callback.")
                        return
                    }
                    strongSelf.clearStillAssetRequest()
                    strongSelf.stillAsset = asset
                    strongSelf.ensureViewState()
                },
                failure: { [weak self] assetRequest in
                    guard let strongSelf = self else { return }
                    if assetRequest != strongSelf.stillAssetRequest {
                        owsFailDebug("Obsolete request callback.")
                        return
                    }
                    strongSelf.clearStillAssetRequest()
                })
        }

        // Start animated asset request if necessary.
        if animatedAsset != nil {
            clearAnimatedAssetRequest()
        } else if animatedAssetRequest == nil {
            animatedAssetRequest = GiphyDownloader.giphyDownloader.requestAsset(
                assetDescription: previewAssetDescription,
                priority: .low,
                success: { [weak self] assetRequest, asset in
                    guard let strongSelf = self else { return }
                    if assetRequest != nil && assetRequest != strongSelf.animatedAssetRequest {
                        owsFailDebug("Obsolete request callback.")
                        return
                    }
                    // If we have the animated asset, we don't need the still asset.
                    strongSelf.clearAssetRequests()
                    strongSelf.animatedAsset = asset
                    strongSelf.ensureViewState()
                },
                failure: { [weak self] assetRequest in
                    guard let strongSelf = self else { return }
                    if assetRequest != strongSelf.animatedAssetRequest {
                        owsFailDebug("Obsolete request callback.")
                        return
                    }
                    strongSelf.clearAnimatedAssetRequest()
            })
        }
    }

    private func ensureViewState() {
        guard isCellVisible else {
            // Clear image view so we don't animate offscreen GIFs.
            clearViewState()
            return
        }
        guard let asset = pickBestAsset() else {
            clearViewState()
            return
        }

        let isValidGIF = NSData.ows_isValidImage(atPath: asset.filePath, mimeType: OWSMimeTypeImageGif)
        let isValidJPEG = NSData.ows_isValidImage(atPath: asset.filePath, mimeType: OWSMimeTypeImageJpeg)

        if asset.assetDescription.fileExtension == "mp4",
           let video = LoopingVideo(url: URL(fileURLWithPath: asset.filePath)) {

            // The underlying asset is an mp4. Set up the corresponding preview view if necessary
            let mp4View = (self.previewView as? LoopingVideoView) ?? {
                let newView = LoopingVideoView()
                contentView.addSubview(newView)
                newView.autoPinEdgesToSuperviewEdges()

                self.previewView?.removeFromSuperview()
                self.previewView = newView
                return newView
            }()
            mp4View.video = video
            mp4View.placeholderProvider = { [weak self] in
                guard let stillPath = self?.stillAsset?.filePath else { return nil }
                guard NSData.ows_isValidImage(atPath: stillPath) else { return nil }
                return UIImage(contentsOfFile: stillPath)
            }

        } else if (isValidGIF || isValidJPEG),
                  let image = YYImage(contentsOfFile: asset.filePath) {

            // The underlying asset is not a video. Set up the corresponding preview view if necessary
            let gifView = (self.previewView as? YYAnimatedImageView) ?? {
                let newView = YYAnimatedImageView()
                contentView.addSubview(newView)
                newView.autoPinEdgesToSuperviewEdges()

                self.previewView?.removeFromSuperview()
                self.previewView = newView
                return newView
            }()
            gifView.image = image

        } else {
            owsFailDebug("could not load asset.")
            clearViewState()
            return
        }

        self.backgroundColor = nil

        if isSelected, activityIndicator == nil {
            let activityIndicator = UIActivityIndicatorView(style: .gray)
            self.activityIndicator = activityIndicator
            addSubview(activityIndicator)
            activityIndicator.autoCenterInSuperview()
            activityIndicator.startAnimating()

            // Render activityIndicator on a white tile to ensure it's visible on
            // when overlayed on a variety of potential gifs.
            activityIndicator.backgroundColor = UIColor.white.withAlphaComponent(0.3)
            activityIndicator.autoSetDimension(.width, toSize: 30)
            activityIndicator.autoSetDimension(.height, toSize: 30)
            activityIndicator.layer.cornerRadius = 3
            activityIndicator.layer.shadowColor = UIColor.black.cgColor
            activityIndicator.layer.shadowOffset = CGSize(square: 1)
            activityIndicator.layer.shadowOpacity = 0.7
            activityIndicator.layer.shadowRadius = 1.0
        } else if !isSelected, let activityIndicator = self.activityIndicator {
            activityIndicator.stopAnimating()
            activityIndicator.removeFromSuperview()
            self.activityIndicator = nil
        }
    }

    public func requestRenditionForSending() -> Promise<ProxiedContentAsset> {
        guard let gifAssetForSending = self.gifAssetForSending else {
            owsFailDebug("renditionForSending was unexpectedly nil")
            return Promise(error: GiphyError.assertionError(description: "renditionForSending was unexpectedly nil"))
        }

        let (promise, resolver) = Promise<ProxiedContentAsset>.pending()

        // We don't retain a handle on the asset request, since there will only ever
        // be one selected asset, and we never want to cancel it.
        _ = GiphyDownloader.giphyDownloader.requestAsset(
            assetDescription: gifAssetForSending,
            priority: .high,
            success: { _, asset in
                resolver.fulfill(asset)
            },
            failure: { _ in
                // TODO GiphyDownloader API should pass through a useful failing error
                // so we can pass it through here
                Logger.error("request failed")
                resolver.reject(GiphyError.fetchFailure)
            })

        return promise
    }

    private func clearViewState() {
        (previewView as? LoopingVideoView)?.video = nil
        (previewView as? UIImageView)?.image = nil
        self.backgroundColor = (Theme.isDarkThemeEnabled
            ? UIColor(white: 0.25, alpha: 1.0)
            : UIColor(white: 0.95, alpha: 1.0))
        self.activityIndicator?.stopAnimating()
        activityIndicator?.removeFromSuperview()
        self.activityIndicator = nil
    }

    private func pickBestAsset() -> ProxiedContentAsset? {
        return animatedAsset ?? stillAsset
    }
}
