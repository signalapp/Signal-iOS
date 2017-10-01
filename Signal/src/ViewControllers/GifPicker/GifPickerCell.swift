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

    // We do "progressive" loading by loading stills (jpg or gif) and "full" gifs. 
    // This is critical on cellular connections.
    var stillAssetRequest: GiphyAssetRequest?
    var stillAsset: GiphyAsset?
    var fullAssetRequest: GiphyAssetRequest?
    var fullAsset: GiphyAsset?
    var imageView: YYAnimatedImageView?

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        owsFail("\(self.TAG) invalid constructor")
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    deinit {
        stillAssetRequest?.cancel()
        fullAssetRequest?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageInfo = nil
        isCellVisible = false
        stillAsset = nil
        stillAssetRequest?.cancel()
        stillAssetRequest = nil
        fullAsset = nil
        fullAssetRequest?.cancel()
        fullAssetRequest = nil
        imageView?.removeFromSuperview()
        imageView = nil
    }

    private func clearStillAssetRequest() {
        stillAssetRequest?.cancel()
        stillAssetRequest = nil
    }

    private func clearFullAssetRequest() {
        fullAssetRequest?.cancel()
        fullAssetRequest = nil
    }

    private func clearAssetRequests() {
        clearStillAssetRequest()
        clearFullAssetRequest()
    }

    public func ensureCellState() {
        guard isCellVisible else {
            // Cancel any outstanding requests.
            clearAssetRequests()
            // Clear image view so we don't animate offscreen GIFs.
            imageView?.removeFromSuperview()
            imageView = nil
            return
        }
        guard let imageInfo = imageInfo else {
            clearAssetRequests()
            return
        }
        guard self.fullAsset == nil else {
            return
        }
        // The Giphy API returns a slew of "renditions" for a given image. 
        // It's critical that we carefully "pick" the best rendition to use.
        guard let fullRendition = imageInfo.pickGifRendition() else {
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
        if stillAsset == nil && fullAsset == nil && stillAssetRequest == nil {
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

        // Start full asset request if necessary.
        if fullAsset == nil && fullAssetRequest == nil {
            fullAssetRequest = GiphyDownloader.sharedInstance.requestAsset(rendition:fullRendition,
                                                                               priority:.low,
                                                                               success: { [weak self] assetRequest, asset in
                                                                                guard let strongSelf = self else { return }
                                                                                if assetRequest != nil && assetRequest != strongSelf.fullAssetRequest {
                                                                                    owsFail("Obsolete request callback.")
                                                                                    return
                                                                                }
                                                                                // If we have the full asset, we don't need the still asset.
                                                                                strongSelf.clearAssetRequests()
                                                                                strongSelf.fullAsset = asset
                                                                                strongSelf.tryToDisplayAsset()
                },
                                                                               failure: { [weak self] assetRequest in
                                                                                guard let strongSelf = self else { return }
                                                                                if assetRequest != strongSelf.fullAssetRequest {
                                                                                    owsFail("Obsolete request callback.")
                                                                                    return
                                                                                }
                                                                                strongSelf.clearFullAssetRequest()
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
            imageView.autoPinWidthToSuperview()
            imageView.autoPinHeightToSuperview()
        }
        guard let imageView = imageView else {
            owsFail("\(TAG) missing imageview.")
            return
        }
        imageView.image = image
    }

    private func pickBestAsset() -> GiphyAsset? {
        if let fullAsset = fullAsset {
            return fullAsset
        }
        if let stillAsset = stillAsset {
            return stillAsset
        }
        return nil
    }
}
