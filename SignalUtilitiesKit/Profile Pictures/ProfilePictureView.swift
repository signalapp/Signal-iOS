// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import YYImage
import SessionUIKit
import SessionMessagingKit

@objc(LKProfilePictureView)
public final class ProfilePictureView: UIView {
    private var hasTappableProfilePicture: Bool = false
    @objc public var size: CGFloat = 0 // Not an implicitly unwrapped optional due to Obj-C limitations
    
    // Constraints
    private var imageViewWidthConstraint: NSLayoutConstraint!
    private var imageViewHeightConstraint: NSLayoutConstraint!
    private var additionalImageViewWidthConstraint: NSLayoutConstraint!
    private var additionalImageViewHeightConstraint: NSLayoutConstraint!
    
    // MARK: - Components
    
    private lazy var imageContainerView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.clipsToBounds = true
        result.backgroundColor = Colors.unimportant
        
        return result
    }()
    
    private lazy var imageView: UIImageView = {
        let result: UIImageView = UIImageView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.contentMode = .scaleAspectFill
        result.isHidden = true
        
        return result
    }()
    
    private lazy var animatedImageView: YYAnimatedImageView = {
        let result: YYAnimatedImageView = YYAnimatedImageView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.contentMode = .scaleAspectFill
        result.isHidden = true
        
        return result
    }()
    
    private lazy var additionalImageContainerView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.clipsToBounds = true
        result.backgroundColor = Colors.unimportant
        result.layer.cornerRadius = (Values.smallProfilePictureSize / 2)
        result.isHidden = true
        
        return result
    }()
    
    private lazy var additionalProfilePlaceholderImageView: UIImageView = {
        let result: UIImageView = UIImageView(
            image: UIImage(systemName: "person.fill")?.withRenderingMode(.alwaysTemplate)
        )
        result.translatesAutoresizingMaskIntoConstraints = false
        result.contentMode = .scaleAspectFill
        result.tintColor = Colors.text
        result.isHidden = true
        
        return result
    }()
    
    private lazy var additionalImageView: UIImageView = {
        let result: UIImageView = UIImageView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.contentMode = .scaleAspectFill
        result.tintColor = Colors.text
        result.isHidden = true
        
        return result
    }()
    
    private lazy var additionalAnimatedImageView: YYAnimatedImageView = {
        let result: YYAnimatedImageView = YYAnimatedImageView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.contentMode = .scaleAspectFill
        result.isHidden = true
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        let imageViewSize = CGFloat(Values.mediumProfilePictureSize)
        let additionalImageViewSize = CGFloat(Values.smallProfilePictureSize)
        
        addSubview(imageContainerView)
        addSubview(additionalImageContainerView)
        
        imageContainerView.pin(.leading, to: .leading, of: self)
        imageContainerView.pin(.top, to: .top, of: self)
        imageViewWidthConstraint = imageContainerView.set(.width, to: imageViewSize)
        imageViewHeightConstraint = imageContainerView.set(.height, to: imageViewSize)
        additionalImageContainerView.pin(.trailing, to: .trailing, of: self)
        additionalImageContainerView.pin(.bottom, to: .bottom, of: self)
        additionalImageViewWidthConstraint = additionalImageContainerView.set(.width, to: additionalImageViewSize)
        additionalImageViewHeightConstraint = additionalImageContainerView.set(.height, to: additionalImageViewSize)
        
        imageContainerView.addSubview(imageView)
        imageContainerView.addSubview(animatedImageView)
        additionalImageContainerView.addSubview(additionalImageView)
        additionalImageContainerView.addSubview(additionalAnimatedImageView)
        additionalImageContainerView.addSubview(additionalProfilePlaceholderImageView)
        
        imageView.pin(to: imageContainerView)
        animatedImageView.pin(to: imageContainerView)
        additionalImageView.pin(to: additionalImageContainerView)
        additionalAnimatedImageView.pin(to: additionalImageContainerView)
        
        additionalProfilePlaceholderImageView.pin(.top, to: .top, of: additionalImageContainerView, withInset: 3)
        additionalProfilePlaceholderImageView.pin(.left, to: .left, of: additionalImageContainerView)
        additionalProfilePlaceholderImageView.pin(.right, to: .right, of: additionalImageContainerView)
        additionalProfilePlaceholderImageView.pin(.bottom, to: .bottom, of: additionalImageContainerView, withInset: 3)
    }
    
    // FIXME: Remove this once we refactor the OWSConversationSettingsViewController to Swift (use the HomeViewModel approach)
    @objc(updateForThreadId:)
    public func update(forThreadId threadId: String?) {
        guard
            let threadId: String = threadId,
            let viewModel: SessionThreadViewModel = Storage.shared.read({ db -> SessionThreadViewModel? in
                let userPublicKey: String = getUserHexEncodedPublicKey(db)
                
                return try SessionThreadViewModel
                    .conversationSettingsProfileQuery(threadId: threadId, userPublicKey: userPublicKey)
                    .fetchOne(db)
            })
        else { return }
        
        update(
            publicKey: viewModel.threadId,
            profile: viewModel.profile,
            additionalProfile: viewModel.additionalProfile,
            threadVariant: viewModel.threadVariant,
            openGroupProfilePictureData: viewModel.openGroupProfilePictureData,
            useFallbackPicture: (
                viewModel.threadVariant == .openGroup &&
                viewModel.openGroupProfilePictureData == nil
            ),
            showMultiAvatarForClosedGroup: true
        )
    }

    public func update(
        publicKey: String = "",
        profile: Profile? = nil,
        additionalProfile: Profile? = nil,
        threadVariant: SessionThread.Variant,
        openGroupProfilePictureData: Data? = nil,
        useFallbackPicture: Bool = false,
        showMultiAvatarForClosedGroup: Bool = false
    ) {
        AssertIsOnMainThread()
        guard !useFallbackPicture else {
            switch self.size {
                case Values.smallProfilePictureSize..<Values.mediumProfilePictureSize: imageView.image = #imageLiteral(resourceName: "SessionWhite16")
                case Values.mediumProfilePictureSize..<Values.largeProfilePictureSize: imageView.image = #imageLiteral(resourceName: "SessionWhite24")
                default: imageView.image = #imageLiteral(resourceName: "SessionWhite40")
            }
            
            imageView.contentMode = .center
            imageView.isHidden = false
            animatedImageView.isHidden = true
            imageContainerView.backgroundColor = UIColor(rgbHex: 0x353535)
            imageContainerView.layer.cornerRadius = (self.size / 2)
            imageViewWidthConstraint.constant = self.size
            imageViewHeightConstraint.constant = self.size
            additionalImageContainerView.isHidden = true
            animatedImageView.image = nil
            additionalImageView.image = nil
            additionalAnimatedImageView.image = nil
            additionalImageView.isHidden = true
            additionalAnimatedImageView.isHidden = true
            additionalProfilePlaceholderImageView.isHidden = true
            return
        }
        guard !publicKey.isEmpty || openGroupProfilePictureData != nil else { return }
        
        func getProfilePicture(of size: CGFloat, for publicKey: String, profile: Profile?) -> (image: UIImage?, animatedImage: YYImage?, isTappable: Bool) {
            if let profile: Profile = profile, let profileData: Data = ProfileManager.profileAvatar(profile: profile) {
                let format: ImageFormat = profileData.guessedImageFormat
                
                let image: UIImage? = (format == .gif || format == .webp ?
                    nil :
                    UIImage(data: profileData)
                )
                let animatedImage: YYImage? = (format != .gif && format != .webp ?
                    nil :
                    YYImage(data: profileData)
                )
                
                if image != nil || animatedImage != nil {
                    return (image, animatedImage, true)
                }
            }
            
            return (
                Identicon.generatePlaceholderIcon(
                    seed: publicKey,
                    text: (profile?.displayName(for: threadVariant))
                        .defaulting(to: publicKey),
                    size: size
                ),
                nil,
                false
            )
        }
        
        // Calulate the sizes (and set the additional image content)
        let targetSize: CGFloat
        
        switch (threadVariant, showMultiAvatarForClosedGroup) {
            case (.closedGroup, true):
                if self.size == 40 {
                    targetSize = 32
                }
                else if self.size == Values.largeProfilePictureSize {
                    targetSize = 56
                }
                else {
                    targetSize = Values.smallProfilePictureSize
                }
                
                imageViewWidthConstraint.constant = targetSize
                imageViewHeightConstraint.constant = targetSize
                additionalImageViewWidthConstraint.constant = targetSize
                additionalImageViewHeightConstraint.constant = targetSize
                additionalImageContainerView.isHidden = false
                
                if let additionalProfile: Profile = additionalProfile {
                    let (image, animatedImage, _): (UIImage?, YYImage?, Bool) = getProfilePicture(
                        of: targetSize,
                        for: additionalProfile.id,
                        profile: additionalProfile
                    )
                    
                    // Set the images and show the appropriate imageView (non-animated should be
                    // visible if there is no image)
                    additionalImageView.image = image
                    additionalAnimatedImageView.image = animatedImage
                    additionalImageView.isHidden = (animatedImage != nil)
                    additionalAnimatedImageView.isHidden = (animatedImage == nil)
                    additionalProfilePlaceholderImageView.isHidden = true
                }
                else {
                    additionalImageView.isHidden = true
                    additionalAnimatedImageView.isHidden = true
                    additionalProfilePlaceholderImageView.isHidden = false
                }
                
            default:
                targetSize = self.size
                imageViewWidthConstraint.constant = targetSize
                imageViewHeightConstraint.constant = targetSize
                additionalImageContainerView.isHidden = true
                additionalImageView.image = nil
                additionalImageView.isHidden = true
                additionalAnimatedImageView.image = nil
                additionalAnimatedImageView.isHidden = true
                additionalProfilePlaceholderImageView.isHidden = true
        }
        
        // Set the image
        if let openGroupProfilePictureData: Data = openGroupProfilePictureData {
            let format: ImageFormat = openGroupProfilePictureData.guessedImageFormat
            
            let image: UIImage? = (format == .gif || format == .webp ?
                nil :
                UIImage(data: openGroupProfilePictureData)
            )
            let animatedImage: YYImage? = (format != .gif && format != .webp ?
                nil :
                YYImage(data: openGroupProfilePictureData)
            )
            
            imageView.image = image
            animatedImageView.image = animatedImage
            imageView.isHidden = (animatedImage != nil)
            animatedImageView.isHidden = (animatedImage == nil)
            hasTappableProfilePicture = true
        }
        else {
            let (image, animatedImage, isTappable): (UIImage?, YYImage?, Bool) = getProfilePicture(
                of: targetSize,
                for: publicKey,
                profile: profile
            )
            imageView.image = image
            animatedImageView.image = animatedImage
            imageView.isHidden = (animatedImage != nil)
            animatedImageView.isHidden = (animatedImage == nil)
            hasTappableProfilePicture = isTappable
        }
        
        imageView.contentMode = .scaleAspectFill
        animatedImageView.contentMode = .scaleAspectFill
        imageContainerView.backgroundColor = Colors.unimportant
        imageContainerView.layer.cornerRadius = (targetSize / 2)
        additionalImageContainerView.layer.cornerRadius = (targetSize / 2)
    }
    
    // MARK: - Convenience
    
    @objc public func getProfilePicture() -> UIImage? {
        return (hasTappableProfilePicture ? imageView.image : nil)
    }
}
