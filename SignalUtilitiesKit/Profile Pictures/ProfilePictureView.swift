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
    
    private lazy var imageView = getImageView()
    private lazy var additionalImageView = getImageView()
    
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
        // Set up image view
        addSubview(imageView)
        imageView.pin(.leading, to: .leading, of: self)
        imageView.pin(.top, to: .top, of: self)
        
        let imageViewSize = CGFloat(Values.mediumProfilePictureSize)
        imageViewWidthConstraint = imageView.set(.width, to: imageViewSize)
        imageViewHeightConstraint = imageView.set(.height, to: imageViewSize)
        
        // Set up additional image view
        addSubview(additionalImageView)
        additionalImageView.pin(.trailing, to: .trailing, of: self)
        additionalImageView.pin(.bottom, to: .bottom, of: self)
        
        let additionalImageViewSize = CGFloat(Values.smallProfilePictureSize)
        additionalImageViewWidthConstraint = additionalImageView.set(.width, to: additionalImageViewSize)
        additionalImageViewHeightConstraint = additionalImageView.set(.height, to: additionalImageViewSize)
        additionalImageView.layer.cornerRadius = additionalImageViewSize / 2
    }
    
    // FIXME: Remove this once we refactor the ConversationVC to Swift (use the HomeViewModel approach)
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
            openGroupProfilePicture: viewModel.openGroupProfilePictureData.map { UIImage(data: $0) },
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
        openGroupProfilePicture: UIImage? = nil,
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
            imageView.backgroundColor = UIColor(rgbHex: 0x353535)
            imageView.layer.cornerRadius = (self.size / 2)
            imageViewWidthConstraint.constant = self.size
            imageViewHeightConstraint.constant = self.size
            additionalImageView.isHidden = true
            additionalImageView.image = nil
            additionalImageView.layer.cornerRadius = (self.size / 2)
            return
        }
        guard !publicKey.isEmpty || openGroupProfilePicture != nil else { return }
        
        func getProfilePicture(of size: CGFloat, for publicKey: String, profile: Profile?) -> (image: UIImage, isTappable: Bool) {
            if let profile: Profile = profile, let profileData: Data = ProfileManager.profileAvatar(profile: profile), let image: YYImage = YYImage(data: profileData) {
                return (image, true)
            }
            
            return (
                Identicon.generatePlaceholderIcon(
                    seed: publicKey,
                    text: (profile?.displayName(for: threadVariant))
                        .defaulting(to: publicKey),
                    size: size
                ),
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
                additionalImageView.isHidden = false
                
                if let additionalProfile: Profile = additionalProfile {
                    additionalImageView.image = getProfilePicture(
                        of: targetSize,
                        for: additionalProfile.id,
                        profile: additionalProfile
                    ).image
                }
                
            default:
                targetSize = self.size
                imageViewWidthConstraint.constant = targetSize
                imageViewHeightConstraint.constant = targetSize
                additionalImageView.isHidden = true
                additionalImageView.image = nil
        }
        
        // Set the image
        if let openGroupProfilePicture: UIImage = openGroupProfilePicture {
            imageView.image = openGroupProfilePicture
            hasTappableProfilePicture = true
        }
        else {
            let (image, isTappable): (UIImage, Bool) = getProfilePicture(
                of: targetSize,
                for: publicKey,
                profile: profile
            )
            imageView.image = image
            hasTappableProfilePicture = isTappable
        }
        
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = Colors.unimportant
        imageView.layer.cornerRadius = (targetSize / 2)
        additionalImageView.layer.cornerRadius = (targetSize / 2)
    }
    
    // MARK: - Convenience
    
    private func getImageView() -> YYAnimatedImageView {
        let result = YYAnimatedImageView()
        result.layer.masksToBounds = true
        result.backgroundColor = Colors.unimportant
        result.contentMode = .scaleAspectFill
        
        return result
    }
    
    @objc public func getProfilePicture() -> UIImage? {
        return (hasTappableProfilePicture ? imageView.image : nil)
    }
}
