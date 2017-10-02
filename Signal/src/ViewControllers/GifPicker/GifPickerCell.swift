//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class GifPickerCell: UICollectionViewCell {
    let TAG = "[GifPickerCell]"

    // MARK: Properties

    var imageInfo: GiphyImageInfo? {
        didSet {
            AssertIsOnMainThread()

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
    var stillAssetRequest: GiphyAssetRequest?
    var stillAsset: GiphyAsset?
    var animatedAssetRequest: GiphyAssetRequest?
    var animatedAsset: GiphyAsset?
    var imageView: YYAnimatedImageView?

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
        imageView?.removeFromSuperview()
        imageView = nil
    }

    private func clearStillAssetRequest() {
        stillAssetRequest?.cancel()
        stillAssetRequest = nil
    }

    private func clearanimatedAssetRequest() {
        animatedAssetRequest?.cancel()
        animatedAssetRequest = nil
    }

    private func clearAssetRequests() {
        clearStillAssetRequest()
        clearanimatedAssetRequest()
    }

    public func ensureCellState() {
        guard isCellVisible else {
            // Cancel any outstanding requests.
            clearAssetRequests()
            // Clear image view so we don't animate offscreen GIFs.
            imageView?.image = nil
            return
        }
        guard let imageInfo = imageInfo else {
            clearAssetRequests()
            return
        }
        guard self.animatedAsset == nil else {
            return
        }
        // The Giphy API returns a slew of "renditions" for a given image. 
        // It's critical that we carefully "pick" the best rendition to use.
        guard let animatedRendition = imageInfo.pickAnimatedRendition() else {
            Logger.warn("\(TAG) could not pick gif rendition: \(imageInfo.giphyId)")
            clearAssetRequests()
            return
        }
        guard let stillRendition = imageInfo.pickStillRendition() else {
            Logger.warn("\(TAG) could not pick still rendition: \(imageInfo.giphyId)")
            clearAssetRequests()
            return
        }

        // Start still asset request if necessary.
        if stillAsset == nil && animatedAsset == nil && stillAssetRequest == nil {
            stillAssetRequest = GiphyDownloader.sharedInstance.requestAsset(rendition:stillRendition,
                                                                                priority:.high,
                                                                                success: { [weak self] assetRequest, asset in
                                                                                    guard let strongSelf = self else { return }
                                                                                    if assetRequest != nil && assetRequest != strongSelf.stillAssetRequest {
                                                                                        owsFail("Obsolete request callback.")
                                                                                        return
                                                                                    }
                                                                                    strongSelf.clearStillAssetRequest()
                                                                                    strongSelf.stillAsset = asset
                                                                                    strongSelf.tryToDisplayAsset()
                },
                                                                                failure: { [weak self] assetRequest in
                                                                                    guard let strongSelf = self else { return }
                                                                                    if assetRequest != strongSelf.stillAssetRequest {
                                                                                        owsFail("Obsolete request callback.")
                                                                                        return
                                                                                    }
                                                                                    strongSelf.clearStillAssetRequest()
            })
        }

        // Start animated asset request if necessary.
        if animatedAsset == nil && animatedAssetRequest == nil {
            animatedAssetRequest = GiphyDownloader.sharedInstance.requestAsset(rendition:animatedRendition,
                                                                               priority:.low,
                                                                               success: { [weak self] assetRequest, asset in
                                                                                guard let strongSelf = self else { return }
                                                                                if assetRequest != nil && assetRequest != strongSelf.animatedAssetRequest {
                                                                                    owsFail("Obsolete request callback.")
                                                                                    return
                                                                                }
                                                                                // If we have the animated asset, we don't need the still asset.
                                                                                strongSelf.clearAssetRequests()
                                                                                strongSelf.animatedAsset = asset
                                                                                strongSelf.tryToDisplayAsset()
                },
                                                                               failure: { [weak self] assetRequest in
                                                                                guard let strongSelf = self else { return }
                                                                                if assetRequest != strongSelf.animatedAssetRequest {
                                                                                    owsFail("Obsolete request callback.")
                                                                                    return
                                                                                }
                                                                                strongSelf.clearanimatedAssetRequest()
            })
        }
    }

    private func tryToDisplayAsset() {
        guard let asset = pickBestAsset() else {
            owsFail("\(TAG) missing asset.")
            return
        }
        guard let image = YYImage(contentsOfFile:asset.filePath) else {
            owsFail("\(TAG) could not load asset.")
            return
        }
        if imageView == nil {
            let imageView = YYAnimatedImageView()
            self.imageView = imageView
            self.contentView.addSubview(imageView)
            imageView.autoPinToSuperviewEdges()
        }
        guard let imageView = imageView else {
            owsFail("\(TAG) missing imageview.")
            return
        }
        imageView.image = image
    }

    private func pickBestAsset() -> GiphyAsset? {
        return animatedAsset ?? stillAsset
    }
}
