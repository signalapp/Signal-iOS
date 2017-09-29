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

    var assetRequest: GiphyAssetRequest?
    var asset: GiphyAsset?
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
        asset = nil
        assetRequest?.cancel()
        assetRequest = nil
        imageView?.removeFromSuperview()
        imageView = nil
    }

    private func clearAssetRequest() {
        assetRequest?.cancel()
        assetRequest = nil
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
        guard self.assetRequest == nil else {
            return
        }
        guard let rendition = imageInfo.pickGifRendition() else {
            Logger.warn("\(TAG) could not pick rendition")
            clearAssetRequest()
            return
        }
//        Logger.verbose("\(TAG) picked rendition: \(rendition.name)")

        assetRequest = GifDownloader.sharedInstance.downloadAssetAsync(rendition:rendition,
                                       success: { [weak self] asset in
                                        guard let strongSelf = self else { return }
                                        strongSelf.clearAssetRequest()
                                        strongSelf.asset = asset
                                        strongSelf.tryToDisplayAsset()
            },
                                       failure: { [weak self] in
                                        guard let strongSelf = self else { return }
                                        strongSelf.clearAssetRequest()
        })
    }

    private func tryToDisplayAsset() {
        guard let asset = asset else {
            owsFail("\(TAG) missing asset.")
            return
        }
        guard let image = YYImage(contentsOfFile:asset.filePath) else {
            owsFail("\(TAG) could not load asset.")
            return
        }
        let imageView = YYAnimatedImageView()
        self.imageView = imageView
        imageView.image = image
        self.contentView.addSubview(imageView)
        imageView.autoPinWidthToSuperview()
        imageView.autoPinHeightToSuperview()
    }
}
