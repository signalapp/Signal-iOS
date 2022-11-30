// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

class SettingsViewModel: SessionTableViewModel<SettingsViewModel.NavButton, SettingsViewModel.Section, SettingsViewModel.Item> {
    // MARK: - Config
    
    enum NavState {
        case standard
        case editing
    }
    
    enum NavButton: Equatable {
        case close
        case qrCode
        case cancel
        case done
    }
    
    public enum Section: SessionTableSection {
        case profileInfo
        case menus
        case footer
    }
    
    public enum Item: Differentiable {
        case profileInfo
        case path
        case privacy
        case notifications
        case conversations
        case messageRequests
        case appearance
        case inviteAFriend
        case recoveryPhrase
        case help
        case clearData
    }
    
    // MARK: - Variables
    
    private let userSessionId: String
    private lazy var imagePickerHandler: ImagePickerHandler = ImagePickerHandler(viewModel: self)
    fileprivate var oldDisplayName: String
    private var editedDisplayName: String?
    
    // MARK: - Initialization
    
    override init() {
        self.userSessionId = getUserHexEncodedPublicKey()
        self.oldDisplayName = Profile.fetchOrCreateCurrentUser().name
        
        super.init()
    }
    
    // MARK: - Navigation
    
    lazy var navState: AnyPublisher<NavState, Never> = {
        isEditing
            .map { isEditing in (isEditing ? .editing : .standard) }
            .removeDuplicates()
            .prepend(.standard)     // Initial value
            .eraseToAnyPublisher()
    }()

    override var leftNavItems: AnyPublisher<[NavItem]?, Never> {
       navState
           .map { navState -> [NavItem] in
               switch navState {
                   case .standard:
                       return [
                            NavItem(
                                id: .close,
                                image: UIImage(named: "X")?
                                    .withRenderingMode(.alwaysTemplate),
                                style: .plain,
                                accessibilityIdentifier: "Close button"
                            ) { [weak self] in self?.dismissScreen() }
                       ]
                       
                   case .editing:
                       return [
                           NavItem(
                               id: .cancel,
                               systemItem: .cancel,
                               accessibilityIdentifier: "Cancel button"
                           ) { [weak self] in
                               self?.setIsEditing(false)
                               self?.editedDisplayName = self?.oldDisplayName
                           }
                       ]
               }
           }
           .eraseToAnyPublisher()
    }
    
    override var rightNavItems: AnyPublisher<[NavItem]?, Never> {
       navState
           .map { [weak self] navState -> [NavItem] in
               switch navState {
                   case .standard:
                       return [
                            NavItem(
                                id: .qrCode,
                                image: UIImage(named: "QRCode")?
                                    .withRenderingMode(.alwaysTemplate),
                                style: .plain,
                                accessibilityIdentifier: "Show QR code button",
                                action: { [weak self] in
                                    self?.transitionToScreen(QRCodeVC())
                                }
                            )
                       ]
                       
                   case .editing:
                       return [
                            NavItem(
                                id: .done,
                                systemItem: .done,
                                accessibilityIdentifier: "Done button"
                            ) { [weak self] in
                                let updatedNickname: String = (self?.editedDisplayName ?? "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                guard !updatedNickname.isEmpty else {
                                    self?.transitionToScreen(
                                        ConfirmationModal(
                                            info: ConfirmationModal.Info(
                                                title: "vc_settings_display_name_missing_error".localized(),
                                                cancelTitle: "BUTTON_OK".localized(),
                                                cancelStyle: .alert_text
                                            )
                                        ),
                                        transitionType: .present
                                    )
                                    return
                                }
                                guard !ProfileManager.isToLong(profileName: updatedNickname) else {
                                    self?.transitionToScreen(
                                        ConfirmationModal(
                                            info: ConfirmationModal.Info(
                                                title: "vc_settings_display_name_too_long_error".localized(),
                                                cancelTitle: "BUTTON_OK".localized(),
                                                cancelStyle: .alert_text
                                            )
                                        ),
                                        transitionType: .present
                                    )
                                    return
                                }
                                
                                self?.setIsEditing(false)
                                self?.oldDisplayName = updatedNickname
                                self?.updateProfile(
                                    name: updatedNickname,
                                    profilePicture: nil,
                                    profilePictureFilePath: nil,
                                    isUpdatingDisplayName: true,
                                    isUpdatingProfilePicture: false
                                )
                            }
                       ]
               }
           }
           .eraseToAnyPublisher()
    }
    
    // MARK: - Content
    
    override var title: String { "vc_settings_title".localized() }
    
    private var _settingsData: [SectionModel] = []
    public override var settingsData: [SectionModel] { _settingsData }
    
    public override var observableSettingsData: ObservableData { _observableSettingsData }
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    private lazy var _observableSettingsData: ObservableData = ValueObservation
        .trackingConstantRegion { db -> [SectionModel] in
            let userPublicKey: String = getUserHexEncodedPublicKey(db)
            let profile: Profile = Profile.fetchOrCreateCurrentUser(db)
            
            return [
                SectionModel(
                    model: .profileInfo,
                    elements: [
                        SessionCell.Info(
                            id: .profileInfo,
                            leftAccessory: .threadInfo(
                                threadViewModel: SessionThreadViewModel(
                                    threadId: profile.id,
                                    threadIsNoteToSelf: true,
                                    contactProfile: profile
                                ),
                                style: SessionCell.Accessory.ThreadInfoStyle(
                                    separatorTitle: "your_session_id".localized(),
                                    descriptionStyle: .monoLarge,
                                    descriptionActions: [
                                        SessionCell.Accessory.ThreadInfoStyle.Action(
                                            title: "copy".localized(),
                                            run: { [weak self] button in
                                                self?.copySessionId(profile.id, button: button)
                                            }
                                        ),
                                        SessionCell.Accessory.ThreadInfoStyle.Action(
                                            title: "share".localized(),
                                            run: { [weak self] _ in
                                                self?.shareSessionId(profile.id)
                                            }
                                        )
                                    ]
                                ),
                                avatarTapped: { [weak self] in self?.updateProfilePicture() },
                                titleTapped: { [weak self] in self?.setIsEditing(true) },
                                titleChanged: { [weak self] text in self?.editedDisplayName = text }
                            ),
                            title: profile.displayName(),
                            shouldHaveBackground: false
                        )
                    ]
                ),
                SectionModel(
                    model: .menus,
                    elements: [
                        SessionCell.Info(
                            id: .path,
                            leftAccessory: .customView {
                                // Need to ensure this view is the same size as the icons so
                                // wrap it in a larger view
                                let result: UIView = UIView()
                                let pathView: PathStatusView = PathStatusView(size: .large)
                                result.addSubview(pathView)
                                
                                result.set(.width, to: IconSize.medium.size)
                                result.set(.height, to: IconSize.medium.size)
                                pathView.center(in: result)
                                
                                return result
                            },
                            title: "vc_path_title".localized(),
                            onTap: { [weak self] in self?.transitionToScreen(PathVC()) }
                        ),
                        SessionCell.Info(
                            id: .privacy,
                            leftAccessory: .icon(
                                UIImage(named: "icon_privacy")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "vc_settings_privacy_button_title".localized(),
                            onTap: { [weak self] in
                                self?.transitionToScreen(
                                    SessionTableViewController(viewModel: PrivacySettingsViewModel())
                                )
                            }
                        ),
                        SessionCell.Info(
                            id: .notifications,
                            leftAccessory: .icon(
                                UIImage(named: "icon_speaker")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "vc_settings_notifications_button_title".localized(),
                            onTap: { [weak self] in
                                self?.transitionToScreen(
                                    SessionTableViewController(viewModel: NotificationSettingsViewModel())
                                )
                            }
                        ),
                        SessionCell.Info(
                            id: .conversations,
                            leftAccessory: .icon(
                                UIImage(named: "icon_msg")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "CONVERSATION_SETTINGS_TITLE".localized(),
                            onTap: { [weak self] in
                                self?.transitionToScreen(
                                    SessionTableViewController(viewModel: ConversationSettingsViewModel())
                                )
                            }
                        ),
                        SessionCell.Info(
                            id: .messageRequests,
                            leftAccessory: .icon(
                                UIImage(named: "icon_msg_req")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "MESSAGE_REQUESTS_TITLE".localized(),
                            onTap: { [weak self] in
                                self?.transitionToScreen(MessageRequestsViewController())
                            }
                        ),
                        SessionCell.Info(
                            id: .appearance,
                            leftAccessory: .icon(
                                UIImage(named: "icon_apperance")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "APPEARANCE_TITLE".localized(),
                            onTap: { [weak self] in
                                self?.transitionToScreen(AppearanceViewController())
                            }
                        ),
                        SessionCell.Info(
                            id: .inviteAFriend,
                            leftAccessory: .icon(
                                UIImage(named: "icon_invite")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "vc_settings_invite_a_friend_button_title".localized(),
                            onTap: { [weak self] in
                                let invitation: String = "Hey, I've been using Session to chat with complete privacy and security. Come join me! Download it at https://getsession.org/. My Session ID is \(profile.id) !"
                                
                                self?.transitionToScreen(
                                    UIActivityViewController(
                                        activityItems: [ invitation ],
                                        applicationActivities: nil
                                    ),
                                    transitionType: .present
                                )
                            }
                        ),
                        SessionCell.Info(
                            id: .recoveryPhrase,
                            leftAccessory: .icon(
                                UIImage(named: "icon_recovery")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "vc_settings_recovery_phrase_button_title".localized(),
                            onTap: { [weak self] in
                                self?.transitionToScreen(SeedModal(), transitionType: .present)
                            }
                        ),
                        SessionCell.Info(
                            id: .help,
                            leftAccessory: .icon(
                                UIImage(named: "icon_help")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "HELP_TITLE".localized(),
                            onTap: { [weak self] in
                                self?.transitionToScreen(
                                    SessionTableViewController(viewModel: HelpViewModel())
                                )
                            }
                        ),
                        SessionCell.Info(
                            id: .clearData,
                            leftAccessory: .icon(
                                UIImage(named: "icon_bin")?
                                    .withRenderingMode(.alwaysTemplate)
                            ),
                            title: "vc_settings_clear_all_data_button_title".localized(),
                            tintColor: .danger,
                            onTap: { [weak self] in
                                self?.transitionToScreen(NukeDataModal(), transitionType: .present)
                            }
                        )
                    ]
                )
            ]
        }
        .removeDuplicates()
        .publisher(in: Storage.shared)
    
    public override var footerView: AnyPublisher<UIView?, Never> {
        Just(VersionFooterView())
            .eraseToAnyPublisher()
    }
    
    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }
    
    private func updateProfilePicture() {
        let actionSheet: UIAlertController = UIAlertController(
            title: "Update Profile Picture",
            message: nil,
            preferredStyle: .actionSheet
        )
        actionSheet.addAction(UIAlertAction(
            title: "MEDIA_FROM_LIBRARY_BUTTON".localized(),
            style: .default,
            handler: { [weak self] _ in
                self?.showPhotoLibraryForAvatar()
            }
        ))
        actionSheet.addAction(UIAlertAction(title: "cancel".localized(), style: .cancel, handler: nil))
        
        self.transitionToScreen(actionSheet, transitionType: .present)
    }
    
    private func showPhotoLibraryForAvatar() {
        Permissions.requestLibraryPermissionIfNeeded { [weak self] in
            DispatchQueue.main.async {
                let picker: UIImagePickerController = UIImagePickerController()
                picker.sourceType = .photoLibrary
                picker.mediaTypes = [ "public.image" ]
                picker.delegate = self?.imagePickerHandler
                
                self?.transitionToScreen(picker, transitionType: .present)
            }
        }
    }
    
    fileprivate func updateProfile(
        name: String,
        profilePicture: UIImage?,
        profilePictureFilePath: String?,
        isUpdatingDisplayName: Bool,
        isUpdatingProfilePicture: Bool
    ) {
        let imageFilePath: String? = (
            profilePictureFilePath ??
            ProfileManager.profileAvatarFilepath(id: self.userSessionId)
        )
        
        let viewController = ModalActivityIndicatorViewController(canCancel: false) { [weak self] modalActivityIndicator in
            ProfileManager.updateLocal(
                queue: DispatchQueue.global(qos: .default),
                profileName: name,
                image: profilePicture,
                imageFilePath: imageFilePath,
                success: { db, updatedProfile in
                    if isUpdatingDisplayName {
                        UserDefaults.standard[.lastDisplayNameUpdate] = Date()
                    }

                    if isUpdatingProfilePicture {
                        UserDefaults.standard[.lastProfilePictureUpdate] = Date()
                    }

                    try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()

                    // Wait for the database transaction to complete before updating the UI
                    db.afterNextTransaction { _ in
                        DispatchQueue.main.async {
                            modalActivityIndicator.dismiss(completion: {})
                        }
                    }
                },
                failure: { [weak self] error in
                    DispatchQueue.main.async {
                        modalActivityIndicator.dismiss {
                            let isMaxFileSizeExceeded: Bool = (error == .avatarUploadMaxFileSizeExceeded)
                            
                            self?.transitionToScreen(
                                ConfirmationModal(
                                    info: ConfirmationModal.Info(
                                        title: (isMaxFileSizeExceeded ?
                                            "Maximum File Size Exceeded" :
                                            "Couldn't Update Profile"
                                        ),
                                        explanation: (isMaxFileSizeExceeded ?
                                            "Please select a smaller photo and try again" :
                                            "Please check your internet connection and try again"
                                        ),
                                        cancelTitle: "BUTTON_OK".localized(),
                                        cancelStyle: .alert_text
                                    )
                                ),
                                transitionType: .present
                            )
                        }
                    }
                }
            )
        }
        
        self.transitionToScreen(viewController, transitionType: .present)
    }
    
    private func copySessionId(_ sessionId: String, button: SessionButton?) {
        UIPasteboard.general.string = sessionId
        
        guard let button: SessionButton = button else { return }
        
        // Ensure we are on the main thread just in case
        DispatchQueue.main.async {
            button.isUserInteractionEnabled = false
            
            UIView.transition(
                with: button,
                duration: 0.25,
                options: .transitionCrossDissolve,
                animations: {
                    button.setTitle("copied".localized(), for: .normal)
                },
                completion: { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) {
                        button.isUserInteractionEnabled = true
                    
                        UIView.transition(
                            with: button,
                            duration: 0.25,
                            options: .transitionCrossDissolve,
                            animations: {
                                button.setTitle("copy".localized(), for: .normal)
                            },
                            completion: nil
                        )
                    }
                }
            )
        }
    }
    
    private func shareSessionId(_ sessionId: String) {
        let shareVC = UIActivityViewController(
            activityItems: [ sessionId ],
            applicationActivities: nil
        )
        
        self.transitionToScreen(shareVC, transitionType: .present)
    }
}

// MARK: - ImagePickerHandler

class ImagePickerHandler: NSObject, UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    private let viewModel: SettingsViewModel
    
    // MARK: - Initialization
    
    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard
            let imageUrl: URL = info[.imageURL] as? URL,
            let rawAvatar: UIImage = info[.originalImage] as? UIImage
        else {
            picker.presentingViewController?.dismiss(animated: true)
            return
        }
        let name: String = self.viewModel.oldDisplayName
        
        picker.presentingViewController?.dismiss(animated: true) { [weak self] in
            // Check if the user selected an animated image (if so then don't crop, just
            // set the avatar directly
            guard
                let resourceValues: URLResourceValues = (try? imageUrl.resourceValues(forKeys: [.typeIdentifierKey])),
                let type: Any = resourceValues.allValues.first?.value,
                let typeString: String = type as? String,
                MIMETypeUtil.supportedAnimatedImageUTITypes().contains(typeString)
            else {
                let viewController: CropScaleImageViewController = CropScaleImageViewController(
                    srcImage: rawAvatar,
                    successCompletion: { resultImage in
                        self?.viewModel.updateProfile(
                            name: name,
                            profilePicture: resultImage,
                            profilePictureFilePath: nil,
                            isUpdatingDisplayName: false,
                            isUpdatingProfilePicture: true
                        )
                    }
                )
                self?.viewModel.transitionToScreen(viewController, transitionType: .present)
                return
            }
            
            self?.viewModel.updateProfile(
                name: name,
                profilePicture: nil,
                profilePictureFilePath: imageUrl.path,
                isUpdatingDisplayName: false,
                isUpdatingProfilePicture: true
            )
        }
    }
}
