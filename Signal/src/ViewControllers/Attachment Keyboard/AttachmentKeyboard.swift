//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit

@objc
protocol AttachmentKeyboardDelegate {
    func didSelectRecentPhoto(_ attachment: SignalAttachment)
    func didTapGalleryButton()
}

class AttachmentKeyboard: CustomKeyboard {
    @objc
    weak var delegate: AttachmentKeyboardDelegate?

    private let mainStackView = UIStackView()

    private let recentPhotosCollectionView = RecentPhotosCollectionView()
    private let recentPhotosErrorView = RecentPhotosErrorView()
    private let galleryButton = UIButton()

    private let bottomView = UIView()

    private lazy var hasRecentsBottomConstraint = bottomView.autoMatch(
        .height,
        to: .height,
        of: recentPhotosCollectionView,
        withMultiplier: 1,
        relation: .lessThanOrEqual
    )
    private lazy var recentPhotosErrorBottomConstraint = bottomView.autoMatch(
        .height,
        to: .height,
        of: recentPhotosErrorView,
        withMultiplier: 1,
        relation: .lessThanOrEqual
    )

    private var mediaLibraryAuthorizationStatus: PHAuthorizationStatus {
        return PHPhotoLibrary.authorizationStatus()
    }

    // MARK: -

    override init() {
        super.init()

        backgroundColor = Theme.backgroundColor

        mainStackView.axis = .vertical
        mainStackView.spacing = 8

        contentView.addSubview(mainStackView)
        mainStackView.autoPinWidthToSuperview()
        mainStackView.autoPinEdge(toSuperviewEdge: .top)
        mainStackView.autoPinEdge(toSuperviewSafeArea: .bottom, withInset: 8)

        setupRecentPhotos()
        setupGalleryButton()
        setupTypePicker()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Recent Photos

    func setupRecentPhotos() {
        recentPhotosCollectionView.recentPhotosDelegate = self
        mainStackView.addArrangedSubview(recentPhotosCollectionView)

        mainStackView.addArrangedSubview(recentPhotosErrorView)
        recentPhotosErrorView.isHidden = true
    }

    func showRecentPhotos() {
        guard recentPhotosCollectionView.hasPhotos else {
            return showRecentPhotosError()
        }

        galleryButton.isHidden = false
        recentPhotosErrorBottomConstraint.isActive = false
        hasRecentsBottomConstraint.isActive = true
        recentPhotosErrorView.isHidden = true
        recentPhotosCollectionView.isHidden = false

        recentPhotosCollectionView.updateLayout()
    }

    func showRecentPhotosError() {
        recentPhotosErrorView.hasMediaLibraryAccess = isMediaLibraryAccessGranted

        galleryButton.isHidden = true
        hasRecentsBottomConstraint.isActive = false
        recentPhotosErrorBottomConstraint.isActive = true
        recentPhotosCollectionView.isHidden = true
        recentPhotosErrorView.isHidden = false
    }

    // MARK: Gallery Button

    func setupGalleryButton() {
        addSubview(galleryButton)
        galleryButton.setTemplateImage(#imageLiteral(resourceName: "photo-outline-28"), tintColor: .white)
        galleryButton.setBackgroundImage(UIImage(color: UIColor.black.withAlphaComponent(0.7)), for: .normal)

        galleryButton.autoSetDimensions(to: CGSize(width: 48, height: 48))
        galleryButton.clipsToBounds = true
        galleryButton.layer.cornerRadius = 24

        galleryButton.autoPinEdge(toSuperviewSafeArea: .leading, withInset: 16)
        galleryButton.autoPinEdge(.bottom, to: .bottom, of: recentPhotosCollectionView, withOffset: -8)

        galleryButton.addTarget(self, action: #selector(didTapGalleryButton), for: .touchUpInside)
    }

    @objc func didTapGalleryButton() {
        delegate?.didTapGalleryButton()
    }

    // MARK: Type Picker

    func setupTypePicker() {
        // TODO: Actually build this.

        mainStackView.addArrangedSubview(bottomView)
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            bottomView.autoSetDimension(.height, toSize: 80)
        }

        bottomView.setCompressionResistanceLow()
        bottomView.setContentHuggingLow()
        bottomView.addRedBorder()
    }

    // MARK: -

    override func resizeToSystemKeyboard() {
        super.resizeToSystemKeyboard()

        // If we're resizing while visible, make sure to update
        // the collection view to fit.
        guard isFirstResponder else { return }

        recentPhotosCollectionView.updateLayout()
    }

    override func wasPresented() {
        super.wasPresented()

        checkPermissionsAndLayout()
    }

    func checkPermissionsAndLayout() {
        switch mediaLibraryAuthorizationStatus {
        case .authorized:
            showRecentPhotos()
        case .denied, .restricted:
            showRecentPhotosError()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { _ in
                self.checkPermissionsAndLayout()
            }
        @unknown default:
            showRecentPhotosError()
            break
        }
    }
}

extension AttachmentKeyboard: RecentPhotosDelegate {
    var isMediaLibraryAccessGranted: Bool {
        return mediaLibraryAuthorizationStatus == .authorized
    }

    func didSelectRecentPhoto(_ attachment: SignalAttachment) {
        delegate?.didSelectRecentPhoto(attachment)
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
        label.textColor = Theme.primaryColor
        label.font = .ows_dynamicTypeSubheadlineClamped
        label.textAlignment = .center

        stackView.addArrangedSubview(label)

        let button = OWSFlatButton()
        button.setBackgroundColors(upColor: .ows_signalBlue)
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
