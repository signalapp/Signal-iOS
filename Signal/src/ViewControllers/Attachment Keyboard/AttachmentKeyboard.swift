//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalMessaging
import SignalUI

protocol AttachmentKeyboardDelegate: AnyObject {
    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment)
    func didTapPhotos()
    func didTapGif()
    func didTapFile()
    func didTapContact()
    func didTapLocation()
    func didTapPayment()
    var isGroup: Bool { get }
}

class AttachmentKeyboard: CustomKeyboard {

    weak var delegate: AttachmentKeyboardDelegate?

    private lazy var recentPhotosCollectionView: RecentPhotosCollectionView = {
        let collectionView = RecentPhotosCollectionView()
        collectionView.recentPhotosDelegate = self
        return collectionView
    }()
    private lazy var attachmentFormatPickerView: UIView = {
        let pickerView = AttachmentFormatPickerView(isGroup: delegate?.isGroup ?? false)
        pickerView.attachmentFormatPickerDelegate = self
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            pickerView.autoSetDimension(.height, toSize: AttachmentFormatPickerView.itemSize.height)
        }
        return pickerView
    }()

    // MARK: -

    init(delegate: AttachmentKeyboardDelegate?) {
        self.delegate = delegate

        super.init()

        // TODO: (igor) Temporarily until I figure out how to do translucent background.
        backgroundColor = Theme.backgroundColor

        let stackView = UIStackView(arrangedSubviews: [ recentPhotosCollectionView, attachmentFormatPickerView ])
        stackView.axis = .vertical
        contentView.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
        stackView.autoPinEdge(toSuperviewSafeArea: .bottom)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
                (recentPhotosCollectionView.height - RecentPhotosCollectionView.itemSpacing) / 2
            )
        // Otherwise, assume the recent photos take up the full height of the collection view.
        } else {
            recentPhotosCollectionView.itemSize = CGSize(square: recentPhotosCollectionView.height)
        }
    }

    private func checkPermissions() {
        let authorizationStatus: PHAuthorizationStatus = {
            if #available(iOS 14, *) {
                return PHPhotoLibrary.authorizationStatus(for: .readWrite)
            } else {
                return PHPhotoLibrary.authorizationStatus()
            }
        }()
        guard authorizationStatus != .notDetermined else {
            let handler: (PHAuthorizationStatus) -> Void = { status in
                self.recentPhotosCollectionView.mediaLibraryAuthorizationStatus = status
            }
            if #available(iOS 14, *) {
                PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: handler)
            } else {
                PHPhotoLibrary.requestAuthorization(handler)
            }
            return
        }
        recentPhotosCollectionView.mediaLibraryAuthorizationStatus = authorizationStatus
    }
}

extension AttachmentKeyboard: RecentPhotosDelegate {

    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment) {
        delegate?.didSelectRecentPhoto(asset: asset, attachment: attachment)
    }
}

extension AttachmentKeyboard: AttachmentFormatPickerDelegate {
    func didTapPhotos() {
        delegate?.didTapPhotos()
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
}
