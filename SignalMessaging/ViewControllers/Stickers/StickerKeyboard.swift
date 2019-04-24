//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol StickerKeyboardDelegate {
//    func didTapConversationHeaderView(_ conversationHeaderView: ConversationHeaderView)
}

@objc
public class StickerKeyboard: UIStackView {

    @objc
    public weak var delegate: StickerKeyboardDelegate?

    @objc
    override public var frame: CGRect {
        didSet {
            Logger.verbose("----- frame: \(frame)")
        }
    }

    @objc
    override public var bounds: CGRect {
        didSet {
            Logger.verbose("----- bounds: \(bounds)")
        }
    }

//    @objc
//    public var attributedTitle: NSAttributedString? {
//        get {
//            return self.titleLabel.attributedText
//        }
//        set {
//            self.titleLabel.attributedText = newValue
//        }
//    }
//
//    @objc
//    public var attributedSubtitle: NSAttributedString? {
//        get {
//            return self.subtitleLabel.attributedText
//        }
//        set {
//            self.subtitleLabel.attributedText = newValue
//            self.subtitleLabel.isHidden = newValue == nil
//        }
//    }
//
//    public var avatarImage: UIImage? {
//        get {
//            return self.avatarView.image
//        }
//        set {
//            self.avatarView.image = newValue
//        }
//    }
//
//    @objc
//    public let titlePrimaryFont: UIFont =  UIFont.ows_boldFont(withSize: 17)
//    @objc
//    public let titleSecondaryFont: UIFont =  UIFont.ows_regularFont(withSize: 9)
//    @objc
//    public let subtitleFont: UIFont = UIFont.ows_regularFont(withSize: 12)
//
//    private let titleLabel: UILabel
//    private let subtitleLabel: UILabel
//    private let avatarView: ConversationAvatarImageView
//

    private let headerView = UIStackView()
    // TODO: Custom layout.  We might want to instantiate stickerCollectionView later.
    private let stickerCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let footerView = UIStackView()

    @objc
    public required init() {
        super.init(frame: .zero)

        createSubviews()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.StickersOrPacksDidChange,
                                               object: nil)
    }

    @objc
    public override var intrinsicContentSize: CGSize {
        // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
        // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
        return .zero
    }

    private func createSubviews() {
        self.axis = .vertical
        self.layoutMargins = .zero
        self.autoresizingMask = .flexibleHeight

        self.addBackgroundView(withBackgroundColor: .red)

        headerView.axis = .horizontal
        addArrangedSubview(headerView)
        headerView.setContentHuggingVerticalHigh()
        headerView.setCompressionResistanceVerticalHigh()
        headerView.autoSetDimension(.height, toSize: 44)

        headerView.backgroundColor = .green
        stickerCollectionView.backgroundColor = .red

        addArrangedSubview(stickerCollectionView)
        stickerCollectionView.setContentHuggingVerticalLow()
        stickerCollectionView.setCompressionResistanceVerticalLow()

        footerView.axis = .horizontal
        footerView.alignment = .center
        addArrangedSubview(footerView)
        footerView.setContentHuggingVerticalHigh()
        footerView.setCompressionResistanceVerticalHigh()
    }

    // MARK: Events

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        // TODO: Reload header too.
        stickerCollectionView.reloadData()
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
