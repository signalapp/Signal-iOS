//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit
import SignalUI
import UIKit

protocol AttachmentFormatPickerDelegate: AnyObject {
    func didTapPhotos()
    func didTapGif()
    func didTapFile()
    func didTapContact()
    func didTapLocation()
    func didTapPayment()
}

class AttachmentFormatPickerView: UICollectionView {
    weak var attachmentFormatPickerDelegate: AttachmentFormatPickerDelegate?

    static let itemSize = CGSize(width: 76, height: 122)

    private let collectionViewFlowLayout: UICollectionViewFlowLayout = {
        let layout = RTLEnabledCollectionViewFlowLayout()
        layout.itemSize = AttachmentFormatPickerView.itemSize
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 12
        return layout
    }()

    private let isGroup: Bool

    init(isGroup: Bool) {
        self.isGroup = isGroup

        super.init(frame: .zero, collectionViewLayout: collectionViewFlowLayout)

        delegate = self
        dataSource = self

        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        let horizontalInset = OWSTableViewController2.defaultHOuterMargin
        contentInset = UIEdgeInsets(top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
        register(AttachmentFormatCell.self, forCellWithReuseIdentifier: AttachmentFormatCell.reuseIdentifier)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private enum AttachmentType: String, CaseIterable, Dependencies {
    case photo
    case gif
    case file
    case payment
    case contact
    case location

    private static var contactCases: [AttachmentType] {
        if payments.shouldShowPaymentsUI {
            return allCases
        } else {
            return everythingExceptPayments
        }
    }

    private static var groupCases: [AttachmentType] {
        everythingExceptPayments
    }

    private static var everythingExceptPayments: [AttachmentType] {
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
        case .photo:
            attachmentFormatPickerDelegate?.didTapPhotos()
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

private class AttachmentFormatCell: UICollectionViewCell {

    static let reuseIdentifier = "AttachmentFormatCell"

    private lazy var imageViewPillBox: UIView = {
        let pillView = PillView()
        pillView.backgroundColor = UIColor(dynamicProvider: { _ in
            Theme.isDarkThemeEnabled ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.08)
        })
        pillView.autoSetDimension(.height, toSize: 50)
        return pillView
    }()
    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .center
        return imageView
    }()
    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeFootnoteClamped.semibold()
        label.textColor = Theme.secondaryTextAndIconColor
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageViewPillBox.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        let stackView = UIStackView(arrangedSubviews: [imageViewPillBox, textLabel])
        stackView.axis = .vertical
        stackView.spacing = 8

        contentView.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPinHeightToSuperview(relation: .lessThanOrEqual)
        stackView.autoAlignAxis(toSuperviewAxis: .horizontal)
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(type: AttachmentType) {
        let imageName: String
        let text: String

        switch type {
        case .photo:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_PHOTOS", comment: "A button to open the photo picker from the Attachment Keyboard")
            imageName = "album-tilt-28"
        case .contact:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_CONTACT", comment: "A button to select a contact from the Attachment Keyboard")
            imageName = "person-circle-28"
        case .file:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_FILE", comment: "A button to select a file from the Attachment Keyboard")
            imageName = "file-28"
        case .gif:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_GIF", comment: "A button to select a GIF from the Attachment Keyboard")
            imageName = "gif-28"
        case .location:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_LOCATION", comment: "A button to select a location from the Attachment Keyboard")
            imageName = "location-28"
        case .payment:
            text = OWSLocalizedString("ATTACHMENT_KEYBOARD_PAYMENT", comment: "A button to select a payment from the Attachment Keyboard")
            imageName = "payment-28"
        }

        textLabel.text = text
        imageView.image = UIImage(imageLiteralResourceName: imageName)
        imageView.tintColor = Theme.isDarkThemeEnabled ? .white : .black
        accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "format-\(type.rawValue)")
    }
}
