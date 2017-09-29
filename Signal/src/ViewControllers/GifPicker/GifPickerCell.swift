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

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
//        self.searchBar = UISearchBar()
//        self.layout = GifPickerLayout()
//        self.collectionView = UICollectionView(frame:CGRect.zero, collectionViewLayout:self.layout)
//        //        self.attachment = SignalAttachment.empty()
        super.init(coder: aDecoder)
        owsFail("\(self.TAG) invalid constructor")
    }

    override init(frame: CGRect) {
//        self.searchBar = UISearchBar()
//        self.layout = GifPickerLayout()
//        self.collectionView = UICollectionView(frame:CGRect.zero, collectionViewLayout:self.layout)
//        //        assert(!attachment.hasError)
//        //        self.attachment = attachment
//        //        self.successCompletion = successCompletion
        super.init(frame: frame)

        self.backgroundColor = UIColor.white
        // TODO:
        self.backgroundColor = UIColor.red
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageInfo = nil
        shouldLoad = false
        asset = nil
        assetRequest?.cancel()
        assetRequest = nil

        // TODO:
        self.backgroundColor = UIColor.red
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
        Logger.verbose("\(TAG) picked rendition: \(rendition.name)")

        assetRequest = GifManager.sharedInstance.downloadAssetAsync(rendition:rendition,
                                       success: { [weak self] asset in
                                        guard let strongSelf = self else { return }
                                        strongSelf.clearAssetRequest()
                                        strongSelf.asset = asset
                                        // TODO:
                                        strongSelf.backgroundColor = UIColor.blue
            },
                                       failure: { [weak self] in
                                        guard let strongSelf = self else { return }
                                        strongSelf.clearAssetRequest()
        })
    }
}
