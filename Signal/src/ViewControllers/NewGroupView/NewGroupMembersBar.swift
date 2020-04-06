//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct NewGroupMember {
    let recipient: PickedRecipient
    let address: SignalServiceAddress
    let displayName: String
    let shortName: String
    let comparableName: String
    let conversationColorName: ConversationColorName
}

// MARK: -

public protocol NewGroupMembersBarDelegate: NewGroupMemberCellDelegate {
}

// MARK: -

@objc
public class NewGroupMembersBar: UIView {

    weak var delegate: NewGroupMembersBarDelegate?

    private var members = [NewGroupMember]()

    func setMembers(_ members: [NewGroupMember]) {
        self.members = members
        resetContentAndLayout()
        updateHeightConstraint()
    }

    private let collectionView: UICollectionView
    private let collectionViewLayout = UICollectionViewFlowLayout()

    private var heightConstraint: NSLayoutConstraint?

    @objc
    public required init() {
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)

        super.init(frame: .zero)

        configure()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    @objc
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    static let hMargin: CGFloat = 12
    static let vMargin: CGFloat = 6
    static let spacing: CGFloat = 8

    private func configure() {
        collectionViewLayout.minimumInteritemSpacing = Self.spacing
        collectionViewLayout.minimumLineSpacing = Self.spacing
        collectionViewLayout.estimatedItemSize = CGSize(width: 1,
                                                        height: CGFloat(NewGroupMemberCell.minAvatarDiameter) * 2)
        collectionViewLayout.scrollDirection = .horizontal
        collectionView.contentInset = UIEdgeInsets(top: Self.vMargin, leading: Self.hMargin, bottom: Self.vMargin, trailing: Self.hMargin)

        collectionView.dataSource = self
        collectionView.delegate = self

        collectionView.register(NewGroupMemberCell.self, forCellWithReuseIdentifier: NewGroupMemberCell.reuseIdentifier)
        collectionView.backgroundColor = Theme.backgroundColor
        collectionView.showsHorizontalScrollIndicator = false

        addSubview(collectionView)
        collectionView.autoPinEdgesToSuperviewEdges()

        heightConstraint = autoSetDimension(.height, toSize: 0)
    }

    private func resetContentAndLayout() {
        AssertIsOnMainThread()

        collectionView.reloadData()
    }

    func updateHeightConstraint() {
        guard let heightConstraint = heightConstraint else {
            owsFailDebug("Missing heightConstraint.")
            return
        }
        let contentHeight = self.contentHeight
        heightConstraint.constant = members.isEmpty ? 0 : contentHeight
    }

    private var contentHeight: CGFloat {
        return preferredCellHeight() + Self.vMargin * 2
    }

}

// MARK: - NewGroupMembersBar

extension NewGroupMembersBar: UICollectionViewDelegateFlowLayout {
    public func preferredCellHeight() -> CGFloat {
        let indexPath = IndexPath(item: 0, section: 0)
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NewGroupMemberCell.reuseIdentifier, for: indexPath) as? NewGroupMemberCell else {
            owsFail("Missing or invalid cell.")
        }
        let address = SignalServiceAddress(uuid: UUID())
        let recipient = PickedRecipient.for(address: address)
        let member = NewGroupMember(recipient: recipient,
                                        address: address,
                                        displayName: "mock",
                                        shortName: "mock",
                                        comparableName: "mock",
                                        conversationColorName: .default)
        cell.configure(member: member)
        let cellSize = cell.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize)
        return cellSize.height
    }

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cell = cellForLayoutMeasurement(at: indexPath)
        let cellSize = cell.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize)

        let collectionViewWidth = collectionView.width
        let maxRowWidth = collectionViewWidth - Self.hMargin * 2
        let maxCellWidth = maxRowWidth
        let minCellWidth: CGFloat = 20
        let cellWidth = max(min(cellSize.width, maxCellWidth), minCellWidth)
        return CGSize(width: cellWidth, height: cellSize.height)
    }

    func cellForLayoutMeasurement(at indexPath: IndexPath) -> UICollectionViewCell {
        return memberCell(at: indexPath)
    }
}

// MARK: -

extension NewGroupMembersBar: UICollectionViewDataSource {

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return members.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return memberCell(at: indexPath)
    }

    fileprivate func memberCell(at indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NewGroupMemberCell.reuseIdentifier, for: indexPath) as? NewGroupMemberCell else {
            owsFail("Missing or invalid cell.")
        }

        guard let member = members[safe: indexPath.row] else {
            owsFailDebug("Missing member.")
            return cell
        }

        cell.configure(member: member)
        assert(self.delegate != nil)
        cell.delegate = self.delegate
        #if DEBUG
        // These accessibilityIdentifiers won't be stable, but they
        // should work for the purposes of our automated testing.
        cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "new-group-member-bar-\(indexPath.row)")
        #endif
        return cell
    }
}

// MARK: -

extension NewGroupMembersBar: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.row < members.count else {
            // Ignore selection of text field cell.
            return
        }
        guard let member = members[safe: indexPath.row] else {
            owsFailDebug("Missing member.")
            return
        }
        // TODO: I'm clarifying with the design what the correct behavior is here.
    }
}

// MARK: -

public protocol NewGroupMemberCellDelegate: class {
    func removeRecipient(_ recipient: PickedRecipient)
}

// MARK: -

private class NewGroupMemberCell: UICollectionViewCell {

    static let reuseIdentifier = "NewGroupMemberCell"

    private let avatarImageView = AvatarImageView()
    private let textLabel = UILabel(frame: .zero)

    fileprivate weak var delegate: NewGroupMemberCellDelegate?
    fileprivate var member: NewGroupMember?

    static let minAvatarDiameter: UInt = 32
    static let hMargin: CGFloat = 16
    static let vMargin: CGFloat = 6
    static var cellHeight: CGFloat {
        let textHeight = ceil(nameFont.lineHeight + 2 * vMargin)
        return max(CGFloat(minAvatarDiameter), textHeight)
    }
    static var nameFont: UIFont {
        // Don't use dynamic type in these cells.
        return UIFont.ows_dynamicTypeBody2.withSize(15)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.layoutMargins = .zero
        contentView.layoutMargins = .zero
        contentView.backgroundColor = Theme.washColor

        textLabel.font = NewGroupMemberCell.nameFont
        textLabel.textColor = Theme.primaryTextColor
        textLabel.numberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail

        let removeButton = UIButton(type: .custom)
        removeButton.setTemplateImageName("x-24", tintColor: Theme.primaryTextColor)
        // Extend the hot area of the remove button.
        let buttonInset: CGFloat = 5
        removeButton.imageEdgeInsets = UIEdgeInsets(top: buttonInset,
                                                    left: buttonInset,
                                                    bottom: buttonInset,
                                                    right: buttonInset)
        removeButton.addTarget(self, action: #selector(removeButtonWasPressed), for: .touchUpInside)
        let buttonSize = 12 + 2 * buttonInset
        removeButton.autoSetDimensions(to: CGSize(square: buttonSize))

        contentView.addSubview(avatarImageView)
        avatarImageView.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)

        let stackView = UIStackView(arrangedSubviews: [textLabel, removeButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 2)
        stackView.isLayoutMarginsRelativeArrangement = true
        contentView.addSubview(stackView)
        stackView.autoPinLeading(toTrailingEdgeOf: avatarImageView)
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.cornerRadius = contentView.height / 2
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func configure(member: NewGroupMember) {
        self.member = member

        let avatarBuilder = OWSContactAvatarBuilder(address: member.address,
                                                    colorName: member.conversationColorName,
                                                    diameter: Self.minAvatarDiameter)
        avatarImageView.image = avatarBuilder.build()
        textLabel.text = member.shortName
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        member = nil
        avatarImageView.image = nil
        textLabel.text = nil
        delegate = nil
    }

    @objc
    func removeButtonWasPressed() {
        guard let recipient = member?.recipient else {
            owsFailDebug("Missing recipient.")
            return
        }
        delegate?.removeRecipient(recipient)
    }
}
