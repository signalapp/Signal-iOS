//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum GetStartedBannerEntry: String, CaseIterable {
    case newGroup
    case avatarBuilder
    case inviteFriends
    case appearance

    var identifier: String { rawValue }
}

protocol GetStartedBannerCellDelegate: AnyObject {
    func didTapClose(_ cell: GetStartedBannerCell)
    func didTapAction(_ cell: GetStartedBannerCell)
}

class GetStartedBannerCell: UICollectionViewCell {
    static let reuseIdentifier = "GetStartedBannerCell"

    // MARK: - Views

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        return view
    }()

    private let closeButton: OWSButton = {
        let button = OWSButton(imageName: "x-16", tintColor: .ows_white)
        button.backgroundColor = .ows_gray40
        return button
    }()

    private let actionButton: OWSButton = {
        let button = OWSButton()
        button.titleLabel?.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.lineBreakMode = .byTruncatingTail

        button.layer.cornerRadius = 16
        button.layer.masksToBounds = true
        return button
    }()

    // MARK: - State

    private weak var delegate: GetStartedBannerCellDelegate?

    private(set) var model: GetStartedBannerEntry? {
        didSet {
            imageView.image = model?.image
            actionButton.setTitle(model?.buttonText, for: .normal)
        }
    }

    // MARK: - Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Content view is masked for curved corners
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true

        // Primary layer is not masked so the shadow can bleed outside the bounds
        layer.shadowRadius = 10
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(square: 0)
        layer.masksToBounds = false

        contentView.addSubview(actionButton)
        contentView.addSubview(imageView)
        contentView.addSubview(closeButton)

        closeButton.autoPinEdge(toSuperviewEdge: .top, withInset: 6)
        closeButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: 6)
        closeButton.autoSetDimensions(to: CGSize(square: 20))
        closeButton.layer.cornerRadius = 10

        actionButton.autoSetDimension(.height, toSize: 32)
        actionButton.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 0, leading: 12, bottom: 11, trailing: 12), excludingEdge: .top)

        imageView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        imageView.autoPinEdge(.bottom, to: .top, of: actionButton, withOffset: -11)

        closeButton.block = { [weak self] in
            guard let self = self else { return }
            self.delegate?.didTapClose(self)
        }

        actionButton.block = { [weak self] in
            guard let self = self else { return }
            self.delegate?.didTapAction(self)
        }

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

    override func prepareForReuse() {
        model = nil
        delegate = nil
    }

    func configure(model: GetStartedBannerEntry, delegate: GetStartedBannerCellDelegate) {
        self.model = model
        self.delegate = delegate
    }

    @objc
    func applyTheme() {
        let titleColor: UIColor = Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_accentBlue
        actionButton.setTitleColor(titleColor, for: .normal)

        actionButton.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray02
        contentView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white
    }
}

private extension GetStartedBannerEntry {
    var image: UIImage {
        switch self {
        case .newGroup:
            return UIImage(named: "new-group-card")!
        case .inviteFriends:
            return UIImage(named: "invite-friends-card")!
        case .appearance:
            return UIImage(named: "appearance-card")!
        case .avatarBuilder:
            return #imageLiteral(resourceName: "avatar_card")
        }
    }

    var buttonText: String {
        switch self {
        case .newGroup:
            return OWSLocalizedString("GET_STARTED_CARD_NEW_GROUP", comment: "'Get Started' button directing users to create a group")
        case .inviteFriends:
            return OWSLocalizedString("GET_STARTED_CARD_INVITE_FRIENDS", comment: "'Get Started' button directing users to invite friends")
        case .appearance:
            return OWSLocalizedString("GET_STARTED_CARD_APPEARANCE", comment: "'Get Started' button directing users to appearance")
        case .avatarBuilder:
            return OWSLocalizedString("GET_STARTED_CARD_AVATAR_BUILDER", comment: "'Get Started' button direction users to avatar builder")
        }
    }
}
