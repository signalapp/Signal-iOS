//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSMediaGalleryCellViewDelegate)
public protocol MediaGalleryCellViewDelegate: class {
    @objc(tryToLoadCellMedia:mediaView:cacheKey:canLoadAsync:)
    func tryToLoadCellMedia(loadCellMediaBlock: @escaping () -> Any?,
                            mediaView: UIView,
                            cacheKey: String,
                            canLoadAsync: Bool) -> Any?
}

@objc(OWSMediaGalleryCellView)
public class MediaGalleryCellView: UIView {
    private weak var delegate: MediaGalleryCellViewDelegate?
    private let items: [ConversationMediaGalleryItem]
    private let itemViews: [MediaItemView]

    private static let kSpacingPts: CGFloat = 2
    private static let kMaxItems = 5

    @objc
    public required init(delegate: MediaGalleryCellViewDelegate,
                         items: [ConversationMediaGalleryItem],
                         maxMessageWidth: CGFloat) {
        self.delegate = delegate
        self.items = items
        self.itemViews = MediaGalleryCellView.itemsToDisplay(forItems: items).map {
            MediaItemView(delegate: delegate,
                          item: $0)
        }

        super.init(frame: .zero)

        self.backgroundColor = .white

        createContents(maxMessageWidth: maxMessageWidth)
    }

    private func createContents(maxMessageWidth: CGFloat) {
        switch itemViews.count {
        case 0:
            return
        case 1:
            guard let itemView = itemViews.first else {
                owsFailDebug("Missing item view.")
                return
            }
            addSubview(itemView)
            itemView.autoPinEdgesToSuperviewEdges()
        case 4:
            // Square
            let imageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts) / 2
            for itemView in itemViews {
                itemView.autoSetDimensions(to: CGSize(width: imageSize, height: imageSize))
            }

            let topViews = Array(itemViews[0..<2])
            let topStack = UIStackView(arrangedSubviews: topViews)
            topStack.axis = .horizontal
            topStack.spacing = MediaGalleryCellView.kSpacingPts

            let bottomViews = Array(itemViews[2..<4])
            let bottomStack = UIStackView(arrangedSubviews: bottomViews)
            bottomStack.axis = .horizontal
            bottomStack.spacing = MediaGalleryCellView.kSpacingPts

            let vStackView = UIStackView(arrangedSubviews: [topStack, bottomStack])
            vStackView.axis = .vertical
            vStackView.spacing = MediaGalleryCellView.kSpacingPts
            addSubview(vStackView)
            vStackView.autoPinEdgesToSuperviewEdges()
        case 2:
            // X X
            // side-by-side.
            let imageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts) / 2
            for itemView in itemViews {
                itemView.autoSetDimensions(to: CGSize(width: imageSize, height: imageSize))
            }

            let views = Array(itemViews[0..<2])
            let hStackView = UIStackView(arrangedSubviews: views)
            hStackView.axis = .horizontal
            hStackView.spacing = MediaGalleryCellView.kSpacingPts
            addSubview(hStackView)
            hStackView.autoPinEdgesToSuperviewEdges()
        case 3:
            //   x
            // X
            //   x
            // Big on left, 2 small on right.
            let smallImageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts * 2) / 3
            let bigImageSize = smallImageSize * 2 + MediaGalleryCellView.kSpacingPts

            guard let leftItemView = itemViews.first else {
                owsFailDebug("Missing view")
                return
            }
            leftItemView.autoSetDimensions(to: CGSize(width: bigImageSize, height: bigImageSize))

            let rightViews = Array(itemViews[1..<3])
            for itemView in rightViews {
                itemView.autoSetDimensions(to: CGSize(width: smallImageSize, height: smallImageSize))
            }
            let rightStack = UIStackView(arrangedSubviews: rightViews)
            rightStack.axis = .vertical
            rightStack.spacing = MediaGalleryCellView.kSpacingPts

            let hStackView = UIStackView(arrangedSubviews: [leftItemView, rightStack])
            hStackView.axis = .horizontal
            hStackView.spacing = MediaGalleryCellView.kSpacingPts
            addSubview(hStackView)
            hStackView.autoPinEdgesToSuperviewEdges()
        default:
            // X X
            // xxx
            // 2 big on top, 3 small on bottom.
            let bigImageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts) / 2
            let smallImageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts * 2) / 3

            let topViews = Array(itemViews[0..<2])
            for itemView in topViews {
                itemView.autoSetDimensions(to: CGSize(width: bigImageSize, height: bigImageSize))
            }
            let topStack = UIStackView(arrangedSubviews: topViews)
            topStack.axis = .horizontal
            topStack.spacing = MediaGalleryCellView.kSpacingPts

            let bottomViews = Array(itemViews[2..<5])
            for itemView in bottomViews {
                itemView.autoSetDimensions(to: CGSize(width: smallImageSize, height: smallImageSize))
            }
            let bottomStack = UIStackView(arrangedSubviews: bottomViews)
            bottomStack.axis = .horizontal
            bottomStack.spacing = MediaGalleryCellView.kSpacingPts

            let vStackView = UIStackView(arrangedSubviews: [topStack, bottomStack])
            vStackView.axis = .vertical
            vStackView.spacing = MediaGalleryCellView.kSpacingPts
            addSubview(vStackView)
            vStackView.autoPinEdgesToSuperviewEdges()
        }
    }

    @objc
    public func loadMedia() {
        for itemView in itemViews {
            itemView.loadMedia()
        }
    }

    @objc
    public func unloadMedia() {
        for itemView in itemViews {
            itemView.unloadMedia()
        }
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private class func itemsToDisplay(forItems items: [ConversationMediaGalleryItem]) -> [ConversationMediaGalleryItem] {
        let validItems = items.filter {
            $0.attachmentStream != nil
            }

        guard validItems.count < kMaxItems else {
            return Array(validItems[0..<kMaxItems])
        }
        return validItems
    }

    @objc
    public class func layoutSize(forMaxMessageWidth maxMessageWidth: CGFloat,
                                 items: [ConversationMediaGalleryItem]) -> CGSize {
        let itemCount = itemsToDisplay(forItems: items).count
        switch itemCount {
        case 0, 1, 4:
            // Square
            return CGSize(width: maxMessageWidth, height: maxMessageWidth)
        case 2:
            // X X
            // side-by-side.
            let imageSize = (maxMessageWidth - kSpacingPts) / 2
            return CGSize(width: maxMessageWidth, height: imageSize)
        case 3:
            //   x
            // X
            //   x
            // Big on left, 2 small on right.
            let smallImageSize = (maxMessageWidth - kSpacingPts * 2) / 3
            let bigImageSize = smallImageSize * 2 + kSpacingPts
            return CGSize(width: maxMessageWidth, height: bigImageSize)
        default:
            // X X
            // xxx
            // 2 big on top, 3 small on bottom.
            let bigImageSize = (maxMessageWidth - kSpacingPts) / 2
            let smallImageSize = (maxMessageWidth - kSpacingPts * 2) / 3
            return CGSize(width: maxMessageWidth, height: bigImageSize + smallImageSize + kSpacingPts)
        }
    }

    private class MediaItemView: UIView {
        private weak var delegate: MediaGalleryCellViewDelegate?
        private let item: ConversationMediaGalleryItem
        private var loadBlock : (() -> Void)?
        private var unloadBlock : (() -> Void)?

        required init(delegate: MediaGalleryCellViewDelegate,
                      item: ConversationMediaGalleryItem) {
            self.delegate = delegate
            self.item = item

            super.init(frame: .zero)

            // TODO:
            self.backgroundColor = .white
            self.backgroundColor = .red

            createContents()
        }

        @available(*, unavailable, message: "use other init() instead.")
        required public init?(coder aDecoder: NSCoder) {
            notImplemented()
        }

        private func createContents() {
            guard let attachmentStream = item.attachmentStream else {
                // TODO: Handle this case.
                owsFailDebug("Missing attachment stream.")
                return
            }
            if attachmentStream.isAnimated {
                configureForAnimatedImage(attachmentStream: attachmentStream)
            } else if attachmentStream.isImage {
                configureForStillImage(attachmentStream: attachmentStream)
            } else if attachmentStream.isVideo {
                configureForVideo(attachmentStream: attachmentStream)
            }
        }

        private func configureForAnimatedImage(attachmentStream: TSAttachmentStream) {
            guard let cacheKey = attachmentStream.uniqueId else {
                owsFailDebug("Attachment stream missing unique ID.")
                return
            }
            let animatedImageView = YYAnimatedImageView()
            // We need to specify a contentMode since the size of the image
            // might not match the aspect ratio of the view.
            animatedImageView.contentMode = .scaleAspectFill
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            animatedImageView.layer.minificationFilter = kCAFilterTrilinear
            animatedImageView.layer.magnificationFilter = kCAFilterTrilinear
            animatedImageView.backgroundColor = .white
            addSubview(animatedImageView)
            animatedImageView.autoPinEdgesToSuperviewEdges()
            //            [self addAttachmentUploadViewIfNecessary];
            loadBlock = { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                guard let strongDelegate = strongSelf.delegate else {
                    return
                }
                if animatedImageView.image != nil {
                    return
                }
                let cachedValue = strongDelegate.tryToLoadCellMedia(loadCellMediaBlock: { () -> Any? in
                    guard let filePath = attachmentStream.originalFilePath else {
                        owsFailDebug("Attachment stream missing original file path.")
                        return nil
                    }
                    let animatedImage = YYImage(contentsOfFile: filePath)
                    return animatedImage
                },
                                                                    mediaView: animatedImageView,
                                                                    cacheKey: cacheKey,
                                                                    canLoadAsync: true)
                guard let image = cachedValue as? YYImage else {
                    return
                }
                animatedImageView.image = image
            }
            unloadBlock = {
                animatedImageView.image = nil
            }
        }

        private func configureForStillImage(attachmentStream: TSAttachmentStream) {
            guard let cacheKey = attachmentStream.uniqueId else {
                owsFailDebug("Attachment stream missing unique ID.")
                return
            }
            let stillImageView = UIImageView()
            // We need to specify a contentMode since the size of the image
            // might not match the aspect ratio of the view.
            stillImageView.contentMode = .scaleAspectFill
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            stillImageView.layer.minificationFilter = kCAFilterTrilinear
            stillImageView.layer.magnificationFilter = kCAFilterTrilinear
            stillImageView.backgroundColor = .white
            addSubview(stillImageView)
            stillImageView.autoPinEdgesToSuperviewEdges()
            //            [self addAttachmentUploadViewIfNecessary];
            loadBlock = { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                guard let strongDelegate = strongSelf.delegate else {
                    return
                }
                if stillImageView.image != nil {
                    return
                }
                let cachedValue = strongDelegate.tryToLoadCellMedia(loadCellMediaBlock: { () -> Any? in
                    return attachmentStream.thumbnailImageMedium(success: { (image) in
                        stillImageView.image = image
                    }, failure: {
                        Logger.error("Could not load thumbnail")
                    })
                },
                                                                    mediaView: stillImageView,
                                                                    cacheKey: cacheKey,
                                                                    canLoadAsync: true)
                guard let image = cachedValue as? UIImage else {
                    return
                }
                stillImageView.image = image
            }
            unloadBlock = {
                stillImageView.image = nil
            }
        }

        private func configureForVideo(attachmentStream: TSAttachmentStream) {
            guard let cacheKey = attachmentStream.uniqueId else {
                owsFailDebug("Attachment stream missing unique ID.")
                return
            }
            let stillImageView = UIImageView()
            // We need to specify a contentMode since the size of the image
            // might not match the aspect ratio of the view.
            stillImageView.contentMode = .scaleAspectFill
            // Use trilinear filters for better scaling quality at
            // some performance cost.
            stillImageView.layer.minificationFilter = kCAFilterTrilinear
            stillImageView.layer.magnificationFilter = kCAFilterTrilinear
            stillImageView.backgroundColor = .white
            addSubview(stillImageView)
            stillImageView.autoPinEdgesToSuperviewEdges()

            // TODO: Hide during upload/download.
            let videoPlayIcon = UIImage(named: "play_button")
            let videoPlayButton = UIImageView(image: videoPlayIcon)
            stillImageView.addSubview(videoPlayButton)
            videoPlayButton.autoCenterInSuperview()

            //            [self addAttachmentUploadViewIfNecessary];
            loadBlock = { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                guard let strongDelegate = strongSelf.delegate else {
                    return
                }
                if stillImageView.image != nil {
                    return
                }
                let cachedValue = strongDelegate.tryToLoadCellMedia(loadCellMediaBlock: { () -> Any? in
                    return attachmentStream.thumbnailImageMedium(success: { (image) in
                        stillImageView.image = image
                    }, failure: {
                        Logger.error("Could not load thumbnail")
                    })
                },
                                                                    mediaView: stillImageView,
                                                                    cacheKey: cacheKey,
                                                                    canLoadAsync: true)
                guard let image = cachedValue as? UIImage else {
                    return
                }
                stillImageView.image = image
            }
            unloadBlock = {
                stillImageView.image = nil
            }
        }

        func loadMedia() {
            guard let loadBlock = loadBlock else {
                owsFailDebug("Missing loadBlock")
                return
            }
            loadBlock()
        }

        func unloadMedia() {
            guard let unloadBlock = unloadBlock else {
                owsFailDebug("Missing unloadBlock")
                return
            }
            unloadBlock()
        }

        private class func itemsToDisplay(forItems items: [ConversationMediaGalleryItem]) -> Int {
            let validItemCount = items.filter {
                $0.attachmentStream != nil
                }.count
            return max(1, min(5, validItemCount))
        }

        @objc
        public class func layoutSize(forMaxMessageWidth maxMessageWidth: CGFloat,
                                     items: [ConversationMediaGalleryItem]) -> CGSize {
            let itemCount = itemsToDisplay(forItems: items)
            switch itemCount {
            case 0, 1, 4:
                // Square
                //
                // TODO: What's the correct size here?
                return CGSize(width: maxMessageWidth, height: maxMessageWidth)
            case 2:
                // X X
                // side-by-side.
                let imageSize = (maxMessageWidth - kSpacingPts) / 2
                return CGSize(width: maxMessageWidth, height: imageSize)
            case 3:
                //   x
                // X
                //   x
                // Big on left, 2 small on right.
                let smallImageSize = (maxMessageWidth - kSpacingPts * 2) / 3
                let bigImageSize = smallImageSize * 2 + kSpacingPts
                return CGSize(width: maxMessageWidth, height: bigImageSize)
            default:
                // X X
                // xxx
                // 2 big on top, 3 small on bottom.
                let bigImageSize = (maxMessageWidth - kSpacingPts) / 2
                let smallImageSize = (maxMessageWidth - kSpacingPts * 2) / 3
                return CGSize(width: maxMessageWidth, height: bigImageSize + smallImageSize + kSpacingPts)
            }
        }
    }
}
