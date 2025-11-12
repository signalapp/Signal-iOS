//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalServiceKit
import SignalUI

protocol AttachmentKeyboardDelegate: AnyObject {
    func didSelectRecentPhoto(asset: PHAsset, attachment: SignalAttachment)
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

    // MARK: -

    init(delegate: AttachmentKeyboardDelegate?) {
        self.delegate = delegate

        super.init()

        let topInset: CGFloat
        if #available(iOS 26, *), BuildFlags.iOS26SDKIsAvailable {
            topInset = 40
            backgroundColor = .clear
        } else {
            topInset = 12
            backgroundColor = UIColor.Signal.background
        }

        let stackView = UIStackView(arrangedSubviews: [
            limitedPhotoPermissionsView,
            recentPhotosCollectionView,
            attachmentFormatPickerView,
        ])
        stackView.axis = .vertical
        stackView.setCustomSpacing(12, after: limitedPhotoPermissionsView)
        limitedPhotoPermissionsView.isHiddenInStackView = true
        contentView.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPinEdge(toSuperviewEdge: .top, withInset: topInset)
        stackView.autoPinEdge(toSuperviewSafeArea: .bottom)
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

    func didTapPoll() {
        delegate?.didTapPoll()
    }
}
