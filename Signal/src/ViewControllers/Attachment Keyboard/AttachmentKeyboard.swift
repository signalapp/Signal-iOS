//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalServiceKit
import SignalUI

protocol AttachmentKeyboardDelegate: AnyObject {
    func didSelectRecentPhoto(asset: PHAsset, attachment: PreviewableAttachment)
    func didTapPhotos()
    func didTapGif()
    func didTapFile()
    func didTapContact()
    func didTapLocation()
    func didTapPayment()
    func didTapPoll()
    var isGroup: Bool { get }
}

class AttachmentKeyboard: CustomKeyboard {

    weak var delegate: AttachmentKeyboardDelegate?

    private lazy var recentPhotosCollectionView: RecentPhotosCollectionView = {
        let collectionView = RecentPhotosCollectionView()
        collectionView.recentPhotosDelegate = self
        return collectionView
    }()
    private lazy var attachmentFormatPickerView: AttachmentFormatPickerView = {
        let pickerView = AttachmentFormatPickerView(isGroup: delegate?.isGroup ?? false)
        pickerView.attachmentFormatPickerDelegate = self
        pickerView.setContentHuggingVerticalHigh()
        pickerView.setCompressionResistanceVerticalHigh()
        return pickerView
    }()

    private lazy var limitedPhotoPermissionsView = LimitedPhotoPermissionsView()

    private var topInset: CGFloat {
        guard #available(iOS 26, *) else { return 12 }
        return traitCollection.verticalSizeClass == .compact ? 20 : 36
    }

    // MARK: -

    init(delegate: AttachmentKeyboardDelegate?) {
        self.delegate = delegate

        super.init()

        backgroundColor = if #available(iOS 26, *) { .clear } else { .Signal.background }

        let stackView = UIStackView(arrangedSubviews: [
            limitedPhotoPermissionsView,
            recentPhotosCollectionView,
            attachmentFormatPickerView,
        ])
        stackView.axis = .vertical
        stackView.setCustomSpacing(12, after: limitedPhotoPermissionsView)
        limitedPhotoPermissionsView.isHiddenInStackView = true
        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        let topEdgeConstraint = stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: topInset)
        NSLayoutConstraint.activate([
            topEdgeConstraint,
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor),
        ])

        // Variable top inset on iOS 26.
        if #available(iOS 26, *) {
            registerForTraitChanges([ UITraitVerticalSizeClass.self ]) { (self: Self, _) in
                topEdgeConstraint.constant = self.topInset
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    override func willPresent() {
        super.willPresent()
        checkPermissions()
        recentPhotosCollectionView.prepareForPresentation()
        attachmentFormatPickerView.prepareForPresentation()
    }

    override func wasPresented() {
        super.wasPresented()
        recentPhotosCollectionView.performPresentationAnimation()
        attachmentFormatPickerView.performPresentationAnimation()
    }

    private func checkPermissions() {
        let setAuthorizationStatus: (PHAuthorizationStatus) -> Void = { status in
            self.recentPhotosCollectionView.mediaLibraryAuthorizationStatus = status
            let isLimited = switch status {
            case .limited:
                true
            case .notDetermined, .restricted, .denied, .authorized:
                false
            @unknown default:
                false
            }
            self.attachmentFormatPickerView.shouldLeaveSpaceForPermissions = isLimited
            self.limitedPhotoPermissionsView.isHiddenInStackView = !isLimited
        }
        let authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus != .notDetermined else {
            PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: setAuthorizationStatus)
            return
        }
        setAuthorizationStatus(authorizationStatus)
    }
}

extension AttachmentKeyboard: RecentPhotosDelegate {

    func didSelectRecentPhoto(asset: PHAsset, attachment: PreviewableAttachment) {
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

    func didTapPoll() {
        delegate?.didTapPoll()
    }
}
