//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol AttachmentFormatPickerDelegate: class {
    func didTapCamera()
    func didTapGif()
    func didTapFile()
    func didTapContact()
    func didTapLocation()
}

class AttachmentFormatPickerView: UICollectionView {
    weak var attachmentFormatPickerDelegate: AttachmentFormatPickerDelegate?

    private var itemSize: CGSize {
        return CGSize(width: frame.height, height: frame.height)
    }

    private let collectionViewFlowLayout = UICollectionViewFlowLayout()

    override var bounds: CGRect {
        didSet {
            guard oldValue != bounds else { return }
            updateLayout()
        }
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

        guard frame.height > 0 else { return }

        // The items should always expand to fit the height of the collection view.
        // We'll always just have one row of items.
        collectionViewFlowLayout.itemSize = itemSize
        collectionViewFlowLayout.invalidateLayout()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum AttachmentType: CaseIterable {
    case camera
    case gif
    case file
    case contact
    case location
}

// MARK: - UICollectionViewDelegate

extension AttachmentFormatPickerView: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch AttachmentType.allCases[indexPath.row] {
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
        }
    }
}

// MARK: - UICollectionViewDataSource

extension AttachmentFormatPickerView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        return AttachmentType.allCases.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentFormatCell.reuseIdentifier, for: indexPath) as? AttachmentFormatCell else {
            owsFail("cell was unexpectedly nil")
        }

        let type = AttachmentType.allCases[indexPath.item]
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
        imageView.autoSetDimensions(to: CGSize(width: 32, height: 32))
        imageView.contentMode = .scaleAspectFit

        label.font = UIFont.ows_dynamicTypeFootnoteClamped.ows_semiBold()
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
        notImplemented()
    }

    public func configure(type: AttachmentType) {
        self.attachmentType = type

        let imageName: String
        let text: String

        switch type {
        case .camera:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_CAMERA", comment: "A button to open the camera from the Attachment Keyboard")
            imageName = "camera-outline-32"
        case .contact:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_CONTACT", comment: "A button to select a contact from the Attachment Keyboard")
            imageName = "contact-outline-32"
        case .file:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_FILE", comment: "A button to select a file from the Attachment Keyboard")
            imageName = "file-outline-32"
        case .gif:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_GIF", comment: "A button to select a GIF from the Attachment Keyboard")
            imageName = "gif-outline-32"
        case .location:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_LOCATION", comment: "A button to select a location from the Attachment Keyboard")
            imageName = "location-outline-32"
        }

        // The light theme images come with a background baked in, so we don't tint them.
        if Theme.isDarkThemeEnabled {
            imageView.setTemplateImageName(imageName, tintColor: Theme.attachmentKeyboardItemImageColor)
        } else {
            imageView.setImage(imageName: imageName + "-with-background")
        }

        label.text = text
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        attachmentType = nil
        imageView.image = nil
    }
}
