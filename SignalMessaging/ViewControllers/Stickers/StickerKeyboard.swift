//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol StickerKeyboardDelegate {
    func didSelectSticker(stickerInfo: StickerInfo)
}

// MARK: -

@objc
public class StickerKeyboard: UIStackView {

    @objc
    public weak var delegate: StickerKeyboardDelegate?

    @objc
    override public var frame: CGRect {
        didSet {
            Logger.verbose("----- frame: \(frame), bounds: \(bounds)")
        }
    }

    @objc
    override public var bounds: CGRect {
        didSet {
            Logger.verbose("----- frame: \(frame), bounds: \(bounds)")
        }
    }

    private let headerView = UIStackView()
    private let stickerCollectionView = StickerPackCollectionView()
    private let footerView = UIStackView()

    private var stickerPacks = [StickerPack]()
    private var stickerPack: StickerPack? {
        didSet {
            AssertIsOnMainThread()

            stickerCollectionView.stickerPack = stickerPack
        }
    }

    @objc
    public required init() {
        super.init(frame: .zero)

        createSubviews()

        reloadStickers()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.StickersOrPacksDidChange,
                                               object: nil)
    }

    @objc
    public override var intrinsicContentSize: CGSize {
        // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
        // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
        return CGSize(width: 0, height: 200)
//        return .zero
    }

    private func createSubviews() {
        self.axis = .vertical
        self.layoutMargins = .zero
        self.autoresizingMask = .flexibleHeight
        self.alignment = .fill

        self.addBackgroundView(withBackgroundColor: .red)

        headerView.axis = .horizontal
        addArrangedSubview(headerView)
        headerView.setContentHuggingVerticalHigh()
        headerView.setCompressionResistanceVerticalHigh()
        headerView.autoSetDimension(.height, toSize: 44)

        headerView.backgroundColor = .green
        stickerCollectionView.backgroundColor = .orange

        stickerCollectionView.stickerDelegate = self
        addArrangedSubview(stickerCollectionView)
        stickerCollectionView.setContentHuggingVerticalLow()
        stickerCollectionView.setCompressionResistanceVerticalLow()
//        stickerCollectionView.autoSetDimension(.height, toSize: 100)

        footerView.axis = .horizontal
        footerView.alignment = .center
        addArrangedSubview(footerView)
        footerView.setContentHuggingVerticalHigh()
        footerView.setCompressionResistanceVerticalHigh()
    }

    private func reloadStickers() {
        stickerPacks = StickerManager.installedStickerPacks()

        guard stickerPacks.count > 0 else {
           stickerPack = nil
            return
        }

        if stickerPack == nil {
            stickerPack = stickerPacks.first
        }

        // TODO: Reload header?
    }

    // MARK: Events

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        reloadStickers()
    }

    //    @objc
//    public required init(thread: TSThread, contactsManager: OWSContactsManager) {
//
//        let avatarView = ConversationAvatarImageView(thread: thread, diameter: 36, contactsManager: contactsManager)
//        self.avatarView = avatarView
//        // remove default border on avatarView
//        avatarView.layer.borderWidth = 0
//
//        titleLabel = UILabel()
//        titleLabel.textColor = Theme.navbarTitleColor
//        titleLabel.lineBreakMode = .byTruncatingTail
//        titleLabel.font = titlePrimaryFont
//        titleLabel.setContentHuggingHigh()
//
//        subtitleLabel = UILabel()
//        subtitleLabel.textColor = Theme.navbarTitleColor
//        subtitleLabel.lineBreakMode = .byTruncatingTail
//        subtitleLabel.font = subtitleFont
//        subtitleLabel.setContentHuggingHigh()
//
//        let textRows = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
//        textRows.axis = .vertical
//        textRows.alignment = .leading
//        textRows.distribution = .fillProportionally
//        textRows.spacing = 0
//
//        textRows.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
//        textRows.isLayoutMarginsRelativeArrangement = true
//
//        // low content hugging so that the text rows push container to the right bar button item(s)
//        textRows.setContentHuggingLow()
//
//        super.init(frame: .zero)
//
//        self.layoutMargins = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
//        self.isLayoutMarginsRelativeArrangement = true
//
//        self.axis = .horizontal
//        self.alignment = .center
//        self.spacing = 0
//        self.addArrangedSubview(avatarView)
//        self.addArrangedSubview(textRows)
//
//        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapView))
//        self.addGestureRecognizer(tapGesture)
//    }

    required public init(coder: NSCoder) {
        notImplemented()
    }

//    required public override init(frame: CGRect) {
//        notImplemented()
//    }
//
//    public override var intrinsicContentSize: CGSize {
//        // Grow to fill as much of the navbar as possible.
//        return UIView.layoutFittingExpandedSize
//    }
//
//    @objc
//    public func updateAvatar() {
//        self.avatarView.updateImage()
//    }
//
//    // MARK: Delegate Methods
//
//    @objc func didTapView(tapGesture: UITapGestureRecognizer) {
//        guard tapGesture.state == .recognized else {
//            return
//        }
//
//        self.delegate?.didTapConversationHeaderView(self)
//    }
}

// MARK: -

extension StickerKeyboard: StickerPackCollectionViewDelegate {
    public func didTapSticker(stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        delegate?.didSelectSticker(stickerInfo: stickerInfo)
    }
}
