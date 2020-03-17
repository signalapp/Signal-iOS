//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct NewGroupMember {
    let recipient: PickedRecipient
    let address: SignalServiceAddress
    let displayName: String
}

// MARK: -

public protocol NewGroupSearchBarDelegate: NewGroupMemberCellDelegate {
    func searchBarTextDidChange()
}

// MARK: -

@objc
public class NewGroupSearchBar: UIView {

    weak var delegate: NewGroupSearchBarDelegate?

    var members = [NewGroupMember]() {
        didSet {
            resetContentAndLayout()
            updatePlaceholder()
        }
    }

    private let collectionView: UICollectionView
    private let collectionViewLayout = NewGroupSearchBarLayout()
    private let textField = UITextField()
    private let placeholderLabel = UILabel()

    private enum Sections: Int, CaseIterable {
        case members, input
    }

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
        textField.font = .ows_dynamicTypeBody
        textField.backgroundColor = .clear
        textField.textColor = Theme.primaryTextColor
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        placeholderLabel.font = .ows_dynamicTypeBody
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.textColor = Theme.placeholderColor
        placeholderLabel.text = NSLocalizedString("NEW_GROUP_SEARCH_PLACEHOLDER",
                                                  comment: "The placeholder text for the search input in the 'create new group' view.")

        collectionViewLayout.layoutDelegate = self

        collectionView.dataSource = self
        collectionView.delegate = self

        collectionView.register(NewGroupMemberCell.self, forCellWithReuseIdentifier: NewGroupMemberCell.reuseIdentifier)
        collectionView.register(NewGroupInputCell.self, forCellWithReuseIdentifier: NewGroupInputCell.reuseIdentifierForDisplay)
        collectionView.register(NewGroupInputCell.self, forCellWithReuseIdentifier: NewGroupInputCell.reuseIdentifierForMeasurement)
        collectionView.backgroundColor = Theme.washColor.withAlphaComponent(0.3)

        collectionView.isUserInteractionEnabled = true
        collectionView.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                   action: #selector(didTapCollectionView)))

        addSubview(collectionView)
        collectionView.autoPinEdgesToSuperviewEdges()

        placeholderLabel.isHidden = true
        addSubview(placeholderLabel)
        placeholderLabel.autoPinEdge(toSuperviewEdge: .leading, withInset: NewGroupSearchBarLayout.hMargin)
        placeholderLabel.autoPinEdge(toSuperviewEdge: .trailing, withInset: NewGroupSearchBarLayout.hMargin)
        placeholderLabel.autoPinEdge(toSuperviewEdge: .top, withInset: NewGroupSearchBarLayout.vMargin)
        placeholderLabel.autoPinEdge(toSuperviewEdge: .bottom, withInset: NewGroupSearchBarLayout.vMargin)
    }

    func contentHeight(forWidth width: CGFloat) -> CGFloat {
        if collectionView.width != width {
            // Collection view content measurement doesn't work
            // until collection view has non-zero size. To ensure
            // initial measurement succeeds, update the frame if
            // necessary.
            var frame = collectionView.frame
            frame.size.width = width
            collectionView.frame = frame
        }
        collectionViewLayout.prepare()
        return collectionViewLayout.collectionViewContentSize.height
    }

    private func resetContentAndLayout() {
        AssertIsOnMainThread()

        UIView.performWithoutAnimation {
            collectionView.reloadSections(IndexSet(integer: Sections.members.rawValue))
            collectionViewLayout.invalidateLayout()
            collectionViewLayout.prepare()
        }
    }

    public var placeholder: String? {
        get {
            textField.placeholder
        }
        set {
            textField.placeholder = newValue
        }
    }

    public var searchText: String? {
        get {
            textField.text
        }
        set {
            textField.text = newValue
        }
    }

    public var textFieldAccessibilityIdentifier: String? {
        get {
            textField.accessibilityIdentifier
        }
        set {
            textField.accessibilityIdentifier = newValue
        }
    }

    public override func becomeFirstResponder() -> Bool {
        let result = textField.becomeFirstResponder()
        updatePlaceholder()
        return result
    }

    public override func resignFirstResponder() -> Bool {
        let result = textField.resignFirstResponder()
        updatePlaceholder()
        return result
    }

    func acceptAutocorrectSuggestion() {
        textField.acceptAutocorrectSuggestion()
    }

    @objc
    func textFieldDidChange(_ textField: UITextField) {
        delegate?.searchBarTextDidChange()

        collectionViewLayout.invalidateLayout()

        updatePlaceholder()
    }

    @objc func didTapCollectionView(sender: UIGestureRecognizer) {
        _ = becomeFirstResponder()
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = (textField.isFirstResponder || !members.isEmpty)
    }
}

// MARK: -

extension NewGroupSearchBar: UICollectionViewDataSource {

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let section = Sections(rawValue: section) else {
            owsFail("Unknown value.")
        }
        switch section {
        case .members:
            return members.count
        case .input:
            return 1
        }
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let section = Sections(rawValue: indexPath.section) else {
            owsFail("Unknown value.")
        }
        switch section {
        case .members:
            return memberCell(at: indexPath)
        case .input:
            return inputCellForDisplay(at: indexPath)
        }
    }

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return Sections.allCases.count
    }

    public func inputCellForDisplay(at indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NewGroupInputCell.reuseIdentifierForDisplay,
                                                            for: indexPath) as? NewGroupInputCell else {
                                                                owsFail("Missing or invalid cell.")
        }

        cell.configure(textField: textField)
        #if DEBUG
        // These accessibilityIdentifiers won't be stable, but they
        // should work for the purposes of our automated testing.
        cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "new-group-search-bar-input")
        #endif
        return cell
    }

    public func inputCellForMeasurement(at indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NewGroupInputCell.reuseIdentifierForMeasurement,
                                                            for: indexPath) as? NewGroupInputCell else {
                                                                owsFail("Missing or invalid cell.")
        }
        // Use a throwaway text field.
        let textField = UITextField()
        textField.text = self.textField.text
        cell.configure(textField: textField)
        return cell
    }

    public func memberCell(at indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NewGroupMemberCell.reuseIdentifier, for: indexPath) as? NewGroupMemberCell else {
            owsFail("Missing or invalid cell.")
        }

        guard let member = members[safe: indexPath.row] else {
            owsFailDebug("Missing member.")
            return cell
        }

        cell.configure(member: member)
        cell.delegate = self.delegate
        #if DEBUG
        // These accessibilityIdentifiers won't be stable, but they
        // should work for the purposes of our automated testing.
        cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "new-group-search-bar-\(indexPath.row)")
        #endif
        return cell
    }
}

// MARK: -

extension NewGroupSearchBar: NewGroupSearchBarLayoutDelegate {
    func cellForLayoutMeasurement(at indexPath: IndexPath) -> UICollectionViewCell {
        guard let section = Sections(rawValue: indexPath.section) else {
            owsFail("Unknown value.")
        }
        switch section {
        case .members:
            return memberCell(at: indexPath)
        case .input:
            return inputCellForMeasurement(at: indexPath)
        }
    }
}

// MARK: -

extension NewGroupSearchBar: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let section = Sections(rawValue: indexPath.section) else {
            owsFailDebug("Unknown value.")
            return
        }
        guard section == .members else {
            return
        }
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

    private let textLabel = UILabel(frame: .zero)

    fileprivate weak var delegate: NewGroupMemberCellDelegate?
    fileprivate var member: NewGroupMember?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = .ows_signalBlue
        contentView.layer.cornerRadius = 4

        textLabel.font = .ows_dynamicTypeBody
        textLabel.textColor = .ows_white
        textLabel.numberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail

        let removeButton = UIButton(type: .custom)
        removeButton.setTemplateImageName("x-24", tintColor: .ows_white)
        let buttonInset: CGFloat = 3
        removeButton.imageEdgeInsets = UIEdgeInsets(top: buttonInset,
                                                    left: buttonInset,
                                                    bottom: buttonInset,
                                                    right: buttonInset)
        removeButton.addTarget(self, action: #selector(removeButtonWasPressed), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [textLabel, removeButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.layoutMargins = UIEdgeInsets(top: 3, leading: 6, bottom: 6, trailing: 3)
        stackView.isLayoutMarginsRelativeArrangement = true
        contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func configure(member: NewGroupMember) {
        self.member = member

        textLabel.text = member.displayName
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        member = nil
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

private class NewGroupInputCell: UICollectionViewCell {

    static let reuseIdentifierForDisplay = "NewGroupInputCell.display"
    static let reuseIdentifierForMeasurement = "NewGroupInputCell.measurement"

    private var textField: UITextField?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @available(*, unavailable, message:"Interface Builder is not supported.")
    @objc
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    func configure(textField: UITextField) {

        self.textField = textField

        guard textField.superview != contentView else {
            return
        }
        contentView.addSubview(textField)
        textField.autoPinEdgesToSuperviewEdges()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
    }
}

// MARK: -

// A simple layout similar to flow layout but without wrapping
// between sections.
private protocol NewGroupSearchBarLayoutDelegate: class {
    func cellForLayoutMeasurement(at indexPath: IndexPath) -> UICollectionViewCell
}

// MARK: -

// A simple layout similar to flow layout but without wrapping
// between sections.
private class NewGroupSearchBarLayout: UICollectionViewLayout {

    fileprivate weak var layoutDelegate: NewGroupSearchBarLayoutDelegate?

    private let itemSize: CGSize = .zero
    private let spacing: CGFloat = 0

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

    static let hMargin: CGFloat = 16
    static let vMargin: CGFloat = 10

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
        let hMargin = NewGroupSearchBarLayout.hMargin
        let vMargin = NewGroupSearchBarLayout.vMargin
        let hSpacing: CGFloat = 4
        let vSpacing: CGFloat = 4
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
        var allRows = [[Item]]()
        var nextRow = [Item]()
        var nextCellX: CGFloat = 0
        let sectionCount = collectionView.numberOfSections
        for section in 0..<sectionCount {
            let itemCount = collectionView.numberOfItems(inSection: section)
            for itemIndex in 0..<itemCount {
                let indexPath = IndexPath(row: itemIndex, section: section)
                let cell = layoutDelegate.cellForLayoutMeasurement(at: indexPath)
                let cellSize = cell.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)

                let cellWidth = max(min(cellSize.width, maxCellWidth), minCellWidth)
                var itemFrame = CGRect(x: 0, y: 0, width: cellWidth, height: cellSize.height)
                if !nextRow.isEmpty,
                    nextCellX + itemFrame.width > maxRowWidth {
                    // Carriage Return
                    allRows.append(nextRow)
                    nextRow = [Item]()
                    nextCellX = 0
                }

                // Add item to next row.
                itemFrame.origin.x = nextCellX
                let item = Item(indexPath: indexPath, frame: itemFrame)
                nextRow.append(item)
                nextCellX += itemFrame.width + hSpacing
            }
        }
        if !nextRow.isEmpty {
            allRows.append(nextRow)
        }

        // 2. In a second pass, finalize positioning.
        //
        // * Assign "y" values.
        // * Apply RTL.
        // * Apply margins.
        var allItems = [Item]()
        var nextRowY: CGFloat = 0
        for row in allRows {
            let cellFrames = row.map { $0.frame }
            let maxY = cellFrames.map { $0.maxY }.max()
            guard let rowHeight = maxY else {
                owsFailDebug("Empty row.")
                continue
            }

            allItems += row.map { item in
                var frame = item.frame

                // V-center within row.
                frame.origin.y = nextRowY + (rowHeight - frame.height) * 0.5

                // Apply RTL
                if CurrentAppContext().isRTL {
                    frame.origin.x = maxRowWidth - frame.maxX
                }

                // Apply margins.
                frame.origin.x += hMargin
                frame.origin.y += vMargin

                return Item(indexPath: item.indexPath, frame: frame)
            }

            nextRowY += rowHeight + vSpacing
        }

        guard !allItems.isEmpty else {
            owsFailDebug("No items.")
            contentSize = .zero
            return
        }

        // 3. Update local state.
        let cellFrames = allItems.map { $0.frame }
        let maxX = cellFrames.map { $0.maxX }.max()!
        let maxY = cellFrames.map { $0.maxY }.max()!
        let contentWidth = maxX + hMargin
        let contentHeight = maxY + vMargin

        for item in allItems {
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
