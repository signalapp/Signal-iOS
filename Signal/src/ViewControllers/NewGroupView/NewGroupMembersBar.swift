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
    private let collectionViewLayout = NewGroupMembersBarLayout()

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

    private func configure() {
        collectionViewLayout.layoutDelegate = self

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
        collectionViewLayout.prepare()
        return collectionViewLayout.collectionViewContentSize.height
    }

    func scrollToRecipient(_ recipient: PickedRecipient) {
        guard let index = members.firstIndex(where: { $0.recipient == recipient }) else {
            owsFailDebug("Missing member.")
            return
        }
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0),
                                    at: .centeredHorizontally,
                                    animated: true)
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
        configure(cell: cell, indexPath: indexPath)
        return cell
    }

    fileprivate func configure(cell: NewGroupMemberCell, indexPath: IndexPath) {
        guard let member = members[safe: indexPath.row] else {
            owsFailDebug("Missing member.")
            return
        }

        cell.configure(member: member)
        assert(self.delegate != nil)
        cell.delegate = self.delegate
        #if DEBUG
        // These accessibilityIdentifiers won't be stable, but they
        // should work for the purposes of our automated testing.
        cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "new-group-member-bar-\(indexPath.row)")
        #endif
    }
}

// MARK: -

extension NewGroupMembersBar: UICollectionViewDelegate {
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
    static let vMargin: CGFloat = 6
    static let removeButtonXSize: CGFloat = 12
    static let removeButtonInset: CGFloat = 5
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
        removeButton.imageEdgeInsets = UIEdgeInsets(top: Self.removeButtonInset,
                                                    left: Self.removeButtonInset,
                                                    bottom: Self.removeButtonInset,
                                                    right: Self.removeButtonInset)
        removeButton.addTarget(self, action: #selector(removeButtonWasPressed), for: .touchUpInside)
        let buttonSize = Self.removeButtonXSize + 2 * Self.removeButtonInset
        removeButton.autoSetDimensions(to: CGSize(square: buttonSize))
        removeButton.setContentHuggingHigh()

        avatarImageView.autoSetDimensions(to: CGSize(square: CGFloat(Self.minAvatarDiameter)))
        avatarImageView.setContentHuggingHigh()
        contentView.addSubview(avatarImageView)
        avatarImageView.autoPinEdge(toSuperviewEdge: .leading)
        avatarImageView.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        avatarImageView.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)

        let stackView = UIStackView(arrangedSubviews: [
            textLabel,
            removeButton
        ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeInsets(top: Self.vMargin, leading: 4, bottom: Self.vMargin, trailing: 2)
        stackView.isLayoutMarginsRelativeArrangement = true
        contentView.addSubview(stackView)
        stackView.autoPinLeading(toTrailingEdgeOf: avatarImageView)
        stackView.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)
        stackView.setContentHuggingHorizontalLow()
        stackView.setCompressionResistanceHorizontalLow()
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

// MARK: -

extension NewGroupMembersBar: NewGroupMembersBarLayoutDelegate {
    func cellForLayoutMeasurement(at indexPath: IndexPath) -> UICollectionViewCell {
        let cell = NewGroupMemberCell()
        configure(cell: cell, indexPath: indexPath)
        return cell
    }
}

// MARK: -

private protocol NewGroupMembersBarLayoutDelegate: class {
    func cellForLayoutMeasurement(at indexPath: IndexPath) -> UICollectionViewCell
}

// MARK: -

// A simple horizontal layout.
private class NewGroupMembersBarLayout: UICollectionViewLayout {

    fileprivate weak var layoutDelegate: NewGroupMembersBarLayoutDelegate?

    private var itemAttributesMap = [UICollectionViewLayoutAttributes]()

    private var contentSize: CGSize = .zero

    // MARK: Initializers and Factory Methods

    public override init() {
        super.init()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: Methods

    override func invalidateLayout() {
        super.invalidateLayout()

        itemAttributesMap.removeAll()
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)

        itemAttributesMap.removeAll()
    }

    static let hMargin: CGFloat = 12
    static let vMargin: CGFloat = 6

    override func prepare() {
        super.prepare()

        guard let collectionView = collectionView else {
            owsFailDebug("Missing collectionView.")
            contentSize = .zero
            return
        }
        guard let layoutDelegate = self.layoutDelegate else {
            owsFailDebug("Missing layoutDelegate.")
            contentSize = .zero
            return
        }
        let hMargin = Self.hMargin
        let vMargin = Self.vMargin
        let hSpacing: CGFloat = 8
        let collectionViewWidth = collectionView.width
        guard collectionViewWidth > hMargin * 2 else {
            contentSize = .zero
            return
        }
        let maxRowWidth = collectionViewWidth - hMargin * 2
        let maxCellWidth = maxRowWidth
        let minCellWidth: CGFloat = 20

        struct Item {
            let indexPath: IndexPath
            var frame: CGRect
        }

        // 1. Measure all cells and assign to rows with "x" values.
        //    NOTE: this pass ignores margins.
        var items = [Item]()
        var nextCellX: CGFloat = 0
        let sectionCount = collectionView.numberOfSections
        for section in 0..<sectionCount {
            let itemCount = collectionView.numberOfItems(inSection: section)
            for itemIndex in 0..<itemCount {
                let indexPath = IndexPath(row: itemIndex, section: section)
                let cell = layoutDelegate.cellForLayoutMeasurement(at: indexPath)
                // We use layoutFittingExpandedSize to ensure we get a proper
                // measurement for the input cell, whose contents are scrollable.
                let cellSize = cell.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                let cellWidth = max(min(cellSize.width, maxCellWidth), minCellWidth)
                var itemFrame = CGRect(x: 0, y: 0, width: cellWidth, height: cellSize.height)

                itemFrame.origin.x = nextCellX
                let item = Item(indexPath: indexPath, frame: itemFrame)
                items.append(item)
                nextCellX += itemFrame.width + hSpacing
            }
        }
        guard !items.isEmpty else {
            self.contentSize = .zero
            return
        }

        // 2. Find max cell height.
        let cellHeights: [CGFloat] = items.map { $0.frame.height }
        let maxCellHeight = cellHeights.max()!

        // 3. In a second pass, finalize positioning.
        //
        // * Assign "y" values.
        // * Apply RTL.
        // * Apply margins.
        items = items.map { item in
            var frame = item.frame

            // V-center within row.
            frame.origin.y = (maxCellHeight - frame.height) * 0.5

            // Apply RTL
            if CurrentAppContext().isRTL {
                frame.origin.x = maxRowWidth - frame.maxX
            }

            // Apply margins.
            frame.origin.x += hMargin
            frame.origin.y += vMargin

            return Item(indexPath: item.indexPath, frame: frame)
        }

        // 4. Update local state.
        let cellFrames = items.map { $0.frame }
        let maxX = cellFrames.map { $0.maxX }.max()!
        let maxY = cellFrames.map { $0.maxY }.max()!
        let contentWidth = maxX + hMargin
        let contentHeight = maxY + vMargin

        for item in items {
            let itemAttributes = UICollectionViewLayoutAttributes(forCellWith: item.indexPath)
            itemAttributes.frame = item.frame
            itemAttributesMap.append(itemAttributes)
        }

        contentSize = CGSize(width: contentWidth, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return itemAttributesMap.filter { itemAttributes in
            return itemAttributes.frame.intersects(rect)
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return itemAttributesMap[safe: indexPath.row]
    }

    override var collectionViewContentSize: CGSize {
        return contentSize
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = collectionView else {
            return false
        }
        return collectionView.width != newBounds.size.width
    }
}
