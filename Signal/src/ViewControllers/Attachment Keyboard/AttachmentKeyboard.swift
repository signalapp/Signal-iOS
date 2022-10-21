//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Photos

@objc
protocol AttachmentKeyboardDelegate {
    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment)
    func didTapGalleryButton()
    func didTapCamera()
    func didTapGif()
    func didTapFile()
    func didTapContact()
    func didTapLocation()
    func didTapPayment()
    var isGroup: Bool { get }
}

class AttachmentKeyboard: CustomKeyboard {
    @objc
    weak var delegate: AttachmentKeyboardDelegate?

    private let mainStackView = UIStackView()

    private let recentPhotosCollectionView = RecentPhotosCollectionView()
    private let recentPhotosErrorView = RecentPhotosErrorView()
    private let galleryButton = UIButton()

    private let attachmentFormatPickerView = AttachmentFormatPickerView()

    private lazy var hasRecentsHeightConstraint = attachmentFormatPickerView.autoMatch(
        .height,
        to: .height,
        of: recentPhotosCollectionView,
        withMultiplier: 1,
        relation: .lessThanOrEqual
    )
    private lazy var recentPhotosErrorHeightConstraint = attachmentFormatPickerView.autoMatch(
        .height,
        to: .height,
        of: recentPhotosErrorView,
        withMultiplier: 1,
        relation: .lessThanOrEqual
    )

    private var mediaLibraryAuthorizationStatus: PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            return PHPhotoLibrary.authorizationStatus()
        }
    }

    // MARK: -

    override init() {
        super.init()

        backgroundColor = Theme.backgroundColor

        mainStackView.axis = .vertical
        mainStackView.spacing = 8

        contentView.addSubview(mainStackView)
        mainStackView.autoPinWidthToSuperview()
        mainStackView.autoPinEdge(toSuperviewEdge: .top, withInset: UIDevice.current.isIPad ? 8 : 0)
        mainStackView.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 8)

        setupRecentPhotos()
        setupGalleryButton()
        setupFormatPicker()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Recent Photos

    private func setupRecentPhotos() {
        recentPhotosCollectionView.recentPhotosDelegate = self
        mainStackView.addArrangedSubview(recentPhotosCollectionView)

        mainStackView.addArrangedSubview(recentPhotosErrorView)
        recentPhotosErrorView.isHidden = true
    }

    private func showRecentPhotos() {
        guard recentPhotosCollectionView.hasPhotos else {
            return showRecentPhotosError()
        }

        galleryButton.isHidden = false
        recentPhotosErrorHeightConstraint.isActive = false
        hasRecentsHeightConstraint.isActive = true
        recentPhotosErrorView.isHidden = true
        recentPhotosCollectionView.isHidden = false
    }

    private func showRecentPhotosError() {
        recentPhotosErrorView.hasMediaLibraryAccess = isMediaLibraryAccessGranted

        galleryButton.isHidden = true
        hasRecentsHeightConstraint.isActive = false
        recentPhotosErrorHeightConstraint.isActive = true
        recentPhotosCollectionView.isHidden = true
        recentPhotosErrorView.isHidden = false
    }

    // MARK: Gallery Button

    private func setupGalleryButton() {
        addSubview(galleryButton)
        galleryButton.setTemplateImage(#imageLiteral(resourceName: "photo-album-outline-28"), tintColor: .white)
        galleryButton.setBackgroundImage(UIImage(color: UIColor.black.withAlphaComponent(0.7)), for: .normal)

        galleryButton.autoSetDimensions(to: CGSize(square: 48))
        galleryButton.clipsToBounds = true
        galleryButton.layer.cornerRadius = 24

        galleryButton.autoPinEdge(toSuperviewSafeArea: .leading, withInset: 16)
        galleryButton.autoPinEdge(.bottom, to: .bottom, of: recentPhotosCollectionView, withOffset: -8)

        galleryButton.addTarget(self, action: #selector(didTapGalleryButton), for: .touchUpInside)
    }

    @objc
    private func didTapGalleryButton() {
        delegate?.didTapGalleryButton()
    }

    // MARK: Format Picker

    private func setupFormatPicker() {
        attachmentFormatPickerView.attachmentFormatPickerDelegate = self

        mainStackView.addArrangedSubview(attachmentFormatPickerView)
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            attachmentFormatPickerView.autoSetDimension(.height, toSize: 80)
        }

        attachmentFormatPickerView.setCompressionResistanceLow()
        attachmentFormatPickerView.setContentHuggingLow()
    }

    // MARK: -

    override func willPresent() {
        super.willPresent()
        checkPermissions()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateItemSizes()
    }

    private func updateItemSizes() {
        // The items should always expand to fit the height of their collection view.

        // If we have space we will show two rows of recent photos (e.g. iPad in landscape).
        if recentPhotosCollectionView.height > 250 {
            recentPhotosCollectionView.itemSize = CGSize(square:
                (recentPhotosCollectionView.height - recentPhotosCollectionView.spaceBetweenRows) / 2
            )

        // Otherwise, assume the recent photos take up the full height of the collection view.
        } else {
            recentPhotosCollectionView.itemSize = CGSize(square: recentPhotosCollectionView.height)
        }

        // There is only ever one row for the attachment format picker.
        attachmentFormatPickerView.itemSize = CGSize(square: attachmentFormatPickerView.height)
    }

    private func checkPermissions() {
        switch mediaLibraryAuthorizationStatus {
        case .authorized, .limited:
            showRecentPhotos()
        case .denied, .restricted:
            showRecentPhotosError()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { _ in
                DispatchQueue.main.async { self.checkPermissions() }
            }
        @unknown default:
            showRecentPhotosError()
        }
    }
}

extension AttachmentKeyboard: RecentPhotosDelegate {
    var isMediaLibraryAccessGranted: Bool {
        if #available(iOS 14, *) {
            return [.authorized, .limited].contains(mediaLibraryAuthorizationStatus)
        } else {
            return mediaLibraryAuthorizationStatus == .authorized
        }
    }

    var isMediaLibraryAccessLimited: Bool {
        guard #available(iOS 14, *) else { return false }
        return mediaLibraryAuthorizationStatus == .limited
    }

    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment) {
        delegate?.didSelectRecentPhoto(asset: asset, attachment: attachment)
    }
}

extension AttachmentKeyboard: AttachmentFormatPickerDelegate {
    func didTapCamera() {
        delegate?.didTapCamera()
    }

    func didTapGif() {
        delegate?.didTapGif()
    }

    func didTapFile() {
        delegate?.didTapFile()
    }

    func didTapContact() {
        delegate?.didTapContact()
    }

    func didTapLocation() {
        delegate?.didTapLocation()
    }

    func didTapPayment() {
        delegate?.didTapPayment()
    }

    var isGroup: Bool {
        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return false
        }
        return delegate.isGroup
    }
}

private class RecentPhotosErrorView: UIView {
    var hasMediaLibraryAccess = false {
        didSet {
            guard hasMediaLibraryAccess != oldValue else { return }
            updateMessaging()
        }
    }

    let label = UILabel()
    let buttonWrapper = UIView()

    override init(frame: CGRect) {
        super.init(frame: .zero)

        layoutMargins = UIEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)

        let stackView = UIStackView()

        stackView.addBackgroundView(withBackgroundColor: Theme.attachmentKeyboardItemBackgroundColor, cornerRadius: 4)

        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.distribution = .fill
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let topSpacer = UIView.vStretchingSpacer()
        stackView.addArrangedSubview(topSpacer)

        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textColor = Theme.primaryTextColor
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.textAlignment = .center

        stackView.addArrangedSubview(label)

        let button = OWSFlatButton()
        button.setBackgroundColors(upColor: .ows_accentBlue)
        button.setTitle(title: CommonStrings.openSettingsButton, font: .ows_dynamicTypeBodyClamped, titleColor: .white)
        button.useDefaultCornerRadius()
        button.contentEdgeInsets = UIEdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
        button.setPressedBlock { UIApplication.shared.openSystemSettings() }

        buttonWrapper.addSubview(button)
        button.autoPinHeightToSuperview()
        button.autoHCenterInSuperview()

        stackView.addArrangedSubview(buttonWrapper)

        let bottomSpacer = UIView.vStretchingSpacer()
        stackView.addArrangedSubview(bottomSpacer)

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        updateMessaging()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateMessaging() {
        buttonWrapper.isHidden = hasMediaLibraryAccess
        if hasMediaLibraryAccess {
            label.text = NSLocalizedString(
                "ATTACHMENT_KEYBOARD_NO_PHOTOS",
                comment: "A string indicating to the user that once they take photos, they'll be able to send them from this view."
            )
        } else {
            label.text = NSLocalizedString(
                "ATTACHMENT_KEYBOARD_NO_PHOTO_ACCESS",
                comment: "A string indicating to the user that they'll be able to send photos from this view once they enable photo access."
            )
        }
    }
}
