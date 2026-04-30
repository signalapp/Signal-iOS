//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalServiceKit
import SignalUI

protocol AttachmentKeyboardDelegate: AnyObject {
    func didSelectRecentPhoto(asset: PHAsset, attachment: PreviewableAttachment, attachmentLimits: OutgoingAttachmentLimits)
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

    private var topMargin: CGFloat {
        guard #available(iOS 26, *) else { return 12 }
        // There's barely visible border taking space at the top
        // so make the inset 1 dp larger than needed to make Settings button
        // concentric with keyboard panel's corner.
        guard limitedPhotoPermissionsView.isHiddenInStackView else { return 17 }
        return traitCollection.verticalSizeClass == .compact ? 20 : 36
    }

    private var stackViewTopAnchorConstraint: NSLayoutConstraint?

    private func updateStackViewTopMargin() {
        guard let stackViewTopAnchorConstraint else { return }
        stackViewTopAnchorConstraint.constant = topMargin
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
        stackView.setCustomSpacing(16, after: limitedPhotoPermissionsView)
        limitedPhotoPermissionsView.isHiddenInStackView = true
        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        let topEdgeConstraint = stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: topMargin)
        NSLayoutConstraint.activate([
            topEdgeConstraint,
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor),
        ])

        // Variable top inset on iOS 26.
        if #available(iOS 26, *) {
            stackViewTopAnchorConstraint = topEdgeConstraint
            registerForTraitChanges([UITraitVerticalSizeClass.self]) { (self: Self, _) in
                self.updateStackViewTopMargin()
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
            self.updateStackViewTopMargin()
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

    func didSelectRecentPhoto(asset: PHAsset, attachment: PreviewableAttachment, attachmentLimits: OutgoingAttachmentLimits) {
        delegate?.didSelectRecentPhoto(asset: asset, attachment: attachment, attachmentLimits: attachmentLimits)
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
