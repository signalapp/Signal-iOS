//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalMessaging
import SignalUI
import YYImage

class GifPickerCell: UICollectionViewCell {

    private let imageView = YYAnimatedImageView()
    private let mp4View = LoopingVideoView()
    private let activityIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .gray)
        view.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        view.autoSetDimension(.width, toSize: 30)
        view.autoSetDimension(.height, toSize: 30)
        view.layer.cornerRadius = 3
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(square: 1)
        view.layer.shadowOpacity = 0.7
        view.layer.shadowRadius = 1.0
        view.hidesWhenStopped = true
        return view
    }()

    private var previewAsset: ProxiedContentAsset?
    private var previewAssetRequest: ProxiedContentAssetRequest? {
        didSet { oldValue?.cancel() }
    }

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)

        [imageView, mp4View, activityIndicator].forEach {
            contentView.addSubview($0)
        }
        imageView.isHidden = true
        mp4View.isHidden = true

        imageView.autoPinEdgesToSuperviewEdges()
        mp4View.autoPinEdgesToSuperviewEdges()
        activityIndicator.autoCenterInSuperview()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: .themeDidChange,
            object: nil)

        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        previewAssetRequest?.cancel()
    }

    // MARK: Public

    public func ensureCellState() {
        ensureLoadState()
        ensureViewState()
    }

    var imageInfo: GiphyImageInfo? {
        didSet {
            AssertIsOnMainThread()
            if imageInfo?.isValidImage == false {
                owsFailDebug("Invalid image info set on cell")
                imageInfo = nil
            }
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

    override var isSelected: Bool {
        didSet {
            AssertIsOnMainThread()
            ensureCellState()
        }
    }

    public var isDisplayingPreview: Bool {
        (previewAsset != nil) && (mp4View.video != nil || imageView.image != nil)
    }

    public func requestRenditionForSending() -> Promise<ProxiedContentAsset> {
        guard let imageInfo = imageInfo,
              let fullSizeAsset = imageInfo.fullSizeAsset else {
            owsFailDebug("fullSizeAsset was unexpectedly nil")
            return Promise(error: GiphyError.assertionError(description: "fullSizeAsset was unexpectedly nil"))
        }

        let (promise, future) = Promise<ProxiedContentAsset>.pending()

        // We don't retain a handle on the asset request, since there will only ever
        // be one selected asset, and we never want to cancel it.
        _ = GiphyDownloader.giphyDownloader.requestAsset(
            assetDescription: fullSizeAsset,
            priority: .high,
            success: { _, asset in
                future.resolve(asset)
            },
            failure: { _ in
                // TODO GiphyDownloader API should pass through a useful failing error
                // so we can pass it through here
                Logger.error("request failed")
                future.reject(GiphyError.fetchFailure)
            })

        return promise
    }

    // MARK: UICollectionViewCell

    override func prepareForReuse() {
        super.prepareForReuse()
        imageInfo = nil
        isCellVisible = false
        isSelected = false
        previewAssetRequest = nil
        previewAsset = nil
        clearViewState()
    }

    // MARK: - Private

    @objc
    private func applyTheme() {
        backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray05
    }

    private func ensureLoadState() {
        guard isCellVisible, let imageInfo = imageInfo else {
            // Nothing to load. We don't load non-visible cell content
            previewAssetRequest = nil
            return
        }
        guard previewAssetRequest == nil, previewAsset == nil else {
            // We already have a load in progress, or we've already loaded the asset
            return
        }
        guard let previewAssetDescription = imageInfo.animatedPreviewAsset else {
            Logger.warn("could not pick gif rendition: \(imageInfo.giphyId)")
            return
        }

        previewAssetRequest = GiphyDownloader.giphyDownloader.requestAsset(
            assetDescription: previewAssetDescription,
            priority: .low,
            success: { [weak self] assetRequest, asset in
                AssertIsOnMainThread()
                guard let self = self else { return }
                guard assetRequest == self.previewAssetRequest else {
                    owsFailDebug("Obsolete request callback.")
                    return
                }
                self.previewAssetRequest = nil
                self.previewAsset = asset
                self.ensureViewState()
            },
            failure: { [weak self] assetRequest in
                AssertIsOnMainThread()
                guard let self = self else { return }
                guard assetRequest == self.previewAssetRequest else {
                    owsFailDebug("Obsolete request callback.")
                    return
                }
                self.previewAssetRequest = nil
            }
        )
    }

    private func ensureViewState() {
        AssertIsOnMainThread()

        guard isCellVisible, let asset = previewAsset else {
            // Nothing to show,
            clearViewState()
            return
        }
        if isSelected {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        if asset.assetDescription.fileExtension == "mp4",
           let video = LoopingVideo(url: URL(fileURLWithPath: asset.filePath)) {
            mp4View.video = video
            mp4View.isHidden = false
        } else if NSData.ows_isValidImage(atPath: asset.filePath, mimeType: OWSMimeTypeImageGif),
                  let image = YYImage(contentsOfFile: asset.filePath) {
            imageView.image = image
            imageView.isHidden = false
        } else if NSData.ows_isValidImage(atPath: asset.filePath, mimeType: OWSMimeTypeImageJpeg),
                  let image = UIImage(contentsOfFile: asset.filePath) {
            imageView.image = image
            imageView.isHidden = false
        } else {
            owsFailDebug("could not load asset.")
            clearViewState()
            return
        }
    }

    private func clearViewState() {
        AssertIsOnMainThread()

        imageView.image = nil
        imageView.isHidden = true
        mp4View.video = nil
        mp4View.isHidden = true
        activityIndicator.stopAnimating()
    }
}
