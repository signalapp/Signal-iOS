//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol AttachmentFormatPickerDelegate: AnyObject {
    func didTapCamera()
    func didTapGif()
    func didTapFile()
    func didTapContact()
    func didTapLocation()
    func didTapPayment()

    var isGroup: Bool { get }
}

class AttachmentFormatPickerView: UICollectionView {
    weak var attachmentFormatPickerDelegate: AttachmentFormatPickerDelegate?

    var itemSize: CGSize = .zero {
        didSet {
            guard oldValue != itemSize else { return }
            updateLayout()
        }
    }

    private let collectionViewFlowLayout = UICollectionViewFlowLayout()

    private var isGroup: Bool {
        guard let attachmentFormatPickerDelegate = attachmentFormatPickerDelegate else {
            owsFailDebug("Missing attachmentFormatPickerDelegate.")
            return false
        }
        return attachmentFormatPickerDelegate.isGroup
    }

    init() {
        super.init(frame: .zero, collectionViewLayout: collectionViewFlowLayout)

        dataSource = self
        delegate = self
        showsHorizontalScrollIndicator = false

        contentInset = UIEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)

        backgroundColor = .clear

        register(AttachmentFormatCell.self, forCellWithReuseIdentifier: AttachmentFormatCell.reuseIdentifier)

        collectionViewFlowLayout.scrollDirection = .horizontal
        collectionViewFlowLayout.minimumLineSpacing = 6

        updateLayout()
    }

    private func updateLayout() {
        AssertIsOnMainThread()

        guard itemSize.height > 0, itemSize.width > 0 else { return }

        collectionViewFlowLayout.itemSize = itemSize
        collectionViewFlowLayout.invalidateLayout()

        reloadData()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum AttachmentType: String, CaseIterable, Dependencies {
    case camera
    case gif
    case file
    case payment
    case contact
    case location

    static var contactCases: [AttachmentType] {
        if payments.shouldShowPaymentsUI {
            return allCases
        } else {
            return everythingExceptPayments
        }
    }

    static var groupCases: [AttachmentType] {
        everythingExceptPayments
    }

    static var everythingExceptPayments: [AttachmentType] {
        return allCases.filter { (value: AttachmentType) in
            value != .payment
        }
    }

    static func cases(isGroup: Bool) -> [AttachmentType] {
        return isGroup ? groupCases : contactCases
    }
}

// MARK: - UICollectionViewDelegate

extension AttachmentFormatPickerView: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch AttachmentType.cases(isGroup: isGroup)[indexPath.row] {
        case .camera:
            attachmentFormatPickerDelegate?.didTapCamera()
        case .contact:
            attachmentFormatPickerDelegate?.didTapContact()
        case .file:
            attachmentFormatPickerDelegate?.didTapFile()
        case .gif:
            attachmentFormatPickerDelegate?.didTapGif()
        case .location:
            attachmentFormatPickerDelegate?.didTapLocation()
        case .payment:
            attachmentFormatPickerDelegate?.didTapPayment()
        }
    }
}

// MARK: - UICollectionViewDataSource

extension AttachmentFormatPickerView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        return AttachmentType.cases(isGroup: isGroup).count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentFormatCell.reuseIdentifier, for: indexPath) as? AttachmentFormatCell else {
            owsFail("cell was unexpectedly nil")
        }

        let type = AttachmentType.cases(isGroup: isGroup)[indexPath.item]
        cell.configure(type: type)
        return cell
    }
}

class AttachmentFormatCell: UICollectionViewCell {

    static let reuseIdentifier = "AttachmentFormatCell"

    let imageView = UIImageView()
    let label = UILabel()

    var attachmentType: AttachmentType?

    override init(frame: CGRect) {

        super.init(frame: frame)

        backgroundColor = Theme.attachmentKeyboardItemBackgroundColor

        clipsToBounds = true
        layer.cornerRadius = 4

        contentView.addSubview(imageView)
        imageView.autoHCenterInSuperview()
        imageView.autoSetDimensions(to: CGSize(square: 32))
        imageView.contentMode = .scaleAspectFit

        label.font = UIFont.dynamicTypeFootnoteClamped.semibold()
        label.textColor = Theme.attachmentKeyboardItemImageColor
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        contentView.addSubview(label)
        label.autoPinEdge(.top, to: .bottom, of: imageView, withOffset: 3)
        label.autoPinWidthToSuperviewMargins()

        // Vertically center things

        let topSpacer = UILayoutGuide()
        let bottomSpacer = UILayoutGuide()
        contentView.addLayoutGuide(topSpacer)
        contentView.addLayoutGuide(bottomSpacer)

        topSpacer.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
        bottomSpacer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor).isActive = true

        imageView.topAnchor.constraint(equalTo: topSpacer.bottomAnchor).isActive = true
        label.bottomAnchor.constraint(equalTo: bottomSpacer.topAnchor).isActive = true
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(type: AttachmentType) {
        self.attachmentType = type

        let imageName: String
        let text: String

        switch type {
        case .camera:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_CAMERA", comment: "A button to open the camera from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentCamera)
        case .contact:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_CONTACT", comment: "A button to select a contact from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentContact)
        case .file:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_FILE", comment: "A button to select a file from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentFile)
        case .gif:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_GIF", comment: "A button to select a GIF from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentGif)
        case .location:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_LOCATION", comment: "A button to select a location from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentLocation)
        case .payment:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_PAYMENT", comment: "A button to select a payment from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentPayment)
        }

        // The light theme images come with a background baked in, so we don't tint them.
        if Theme.isDarkThemeEnabled {
            imageView.setTemplateImageName(imageName, tintColor: Theme.attachmentKeyboardItemImageColor)
        } else {
            imageView.setImage(imageName: imageName)
        }

        label.text = text

        self.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "format-\(type.rawValue)")
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        attachmentType = nil
        imageView.image = nil

        label.textColor = Theme.attachmentKeyboardItemImageColor
        backgroundColor = Theme.attachmentKeyboardItemBackgroundColor
    }
}
