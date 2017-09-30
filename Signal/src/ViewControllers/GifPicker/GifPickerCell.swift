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

            ensureLoad()
        }
    }

    var shouldLoad = false {
        didSet {
            AssertIsOnMainThread()

            ensureLoad()
        }
    }

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

    override func prepareForReuse() {
        super.prepareForReuse()

        imageInfo = nil
        shouldLoad = false
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

    private func clearAssetRequest() {
        clearStillAssetRequest()
        clearFullAssetRequest()
    }

    private func ensureLoad() {
        guard shouldLoad else {
            clearAssetRequest()
            return
        }
        guard let imageInfo = imageInfo else {
            clearAssetRequest()
            return
        }
        guard self.fullAsset == nil else {
            return
        }
        guard let fullRendition = imageInfo.pickGifRendition() else {
            Logger.warn("\(TAG) could not pick gif rendition: \(imageInfo.giphyId)")
            clearAssetRequest()
            return
        }
        guard let stillRendition = imageInfo.pickStillRendition() else {
            Logger.warn("\(TAG) could not pick still rendition: \(imageInfo.giphyId)")
            clearAssetRequest()
            return
        }

        if stillAsset == nil && fullAsset == nil && stillAssetRequest == nil {
            stillAssetRequest = GifDownloader.sharedInstance.downloadAssetAsync(rendition:stillRendition,
                                                                                priority:.high,
                                                                                success: { [weak self] asset in
                                                                                    guard let strongSelf = self else { return }
                                                                                    strongSelf.clearStillAssetRequest()
                                                                                    strongSelf.stillAsset = asset
                                                                                    strongSelf.tryToDisplayAsset()
                },
                                                                                failure: { [weak self] in
                                                                                    guard let strongSelf = self else { return }
                                                                                    strongSelf.clearStillAssetRequest()
            })
        }
        if fullAsset == nil && fullAssetRequest == nil {
            fullAssetRequest = GifDownloader.sharedInstance.downloadAssetAsync(rendition:fullRendition,
                                                                               priority:.low,
                                                                               success: { [weak self] asset in
                                                                                guard let strongSelf = self else { return }
                                                                                strongSelf.clearAssetRequest()
                                                                                strongSelf.fullAsset = asset
                                                                                strongSelf.tryToDisplayAsset()
                },
                                                                               failure: { [weak self] in
                                                                                guard let strongSelf = self else { return }
                                                                                strongSelf.clearAssetRequest()
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
