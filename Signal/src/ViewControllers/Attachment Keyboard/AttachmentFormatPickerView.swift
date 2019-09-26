//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol AttachmentFormatPickerDelegate: class {
    func didTapCamera(withPhotoCapture: PhotoCapture?)
    func didTapGif()
    func didTapFile()
    func didTapContact()
    func didTapLocation()
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
    private var photoCapture: PhotoCapture?

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

    deinit {
        stopCameraPreview()
    }

    func startCameraPreview() {
        guard photoCapture == nil else { return }

        let photoCapture = PhotoCapture()
        self.photoCapture = photoCapture

        photoCapture.startVideoCapture().done { [weak self] in
            self?.reloadData()
        }.retainUntilComplete()
    }

    func stopCameraPreview() {
        photoCapture?.stopCapture().retainUntilComplete()
        photoCapture = nil
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

enum AttachmentType: String, CaseIterable {
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
            // Since we're trying to pass on our prepared capture session to
            // the camera view, nil it out so we don't try and stop it here.
            let photoCapture = self.photoCapture
            self.photoCapture = nil
            attachmentFormatPickerDelegate?.didTapCamera(withPhotoCapture: photoCapture)
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
        cell.configure(type: type, cameraPreview: photoCapture?.previewView)
        return cell
    }
}

class AttachmentFormatCell: UICollectionViewCell {

    static let reuseIdentifier = "AttachmentFormatCell"

    let imageView = UIImageView()
    let label = UILabel()

    var attachmentType: AttachmentType?
    weak var cameraPreview: CapturePreviewView?

    private var hasCameraAccess: Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    override init(frame: CGRect) {

        super.init(frame: frame)

        backgroundColor = Theme.attachmentKeyboardItemBackgroundColor

        clipsToBounds = true
        layer.cornerRadius = 4

        contentView.addSubview(imageView)
        imageView.autoHCenterInSuperview()
        imageView.autoSetDimensions(to: CGSize(width: 32, height: 32))
        imageView.contentMode = .scaleAspectFit

        label.font = UIFont.ows_dynamicTypeFootnoteClamped.ows_semibold()
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

    public func configure(type: AttachmentType, cameraPreview: CapturePreviewView?) {
        self.attachmentType = type
        self.cameraPreview = cameraPreview

        let imageName: String
        let text: String

        switch type {
        case .camera:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_CAMERA", comment: "A button to open the camera from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentCamera)
        case .contact:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_CONTACT", comment: "A button to select a contact from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentContact)
        case .file:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_FILE", comment: "A button to select a file from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentFile)
        case .gif:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_GIF", comment: "A button to select a GIF from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentGif)
        case .location:
            text = NSLocalizedString("ATTACHMENT_KEYBOARD_LOCATION", comment: "A button to select a location from the Attachment Keyboard")
            imageName = Theme.iconName(.attachmentLocation)
        }

        // The light theme images come with a background baked in, so we don't tint them.
        if Theme.isDarkThemeEnabled {
            imageView.setTemplateImageName(imageName, tintColor: Theme.attachmentKeyboardItemImageColor)
        } else {
            imageView.setImage(imageName: imageName)
        }

        label.text = text

        self.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "format-\(type.rawValue)")

        showLiveCameraIfAvailable()
    }

    func showLiveCameraIfAvailable() {
        guard case .camera? = attachmentType, hasCameraAccess else { return }

        // If we have access to the camera, we'll want to show it eventually.
        // Style this in prepration for that.

        imageView.setTemplateImageName("camera-outline-32", tintColor: .white)
        label.textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.4)

        guard let cameraPreview = cameraPreview else { return }

        contentView.insertSubview(cameraPreview, belowSubview: imageView)
        cameraPreview.autoPinEdgesToSuperviewEdges()
        cameraPreview.contentMode = .scaleAspectFill
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        attachmentType = nil
        imageView.image = nil

        label.textColor = Theme.attachmentKeyboardItemImageColor
        backgroundColor = Theme.attachmentKeyboardItemBackgroundColor

        if let cameraPreview = cameraPreview, cameraPreview.superview == contentView {
            cameraPreview.removeFromSuperview()
        }
    }
}
