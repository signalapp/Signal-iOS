// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import PromiseKit
import SignalCoreKit
import SessionUtilitiesKit

public struct ProfileManager {
    // The max bytes for a user's profile name, encoded in UTF8.
    // Before encrypting and submitting we NULL pad the name data to this length.
    private static let nameDataLength: UInt = 26
    public static let maxAvatarDiameter: CGFloat = 640
    
    private static var profileAvatarCache: Atomic<[String: UIImage]> = Atomic([:])
    private static var currentAvatarDownloads: Atomic<Set<String>> = Atomic([])
    
    // MARK: - Functions
    
    public static func isToLong(profileName: String) -> Bool {
        return ((profileName.data(using: .utf8)?.count ?? 0) > nameDataLength)
    }
    
    public static func profileAvatar(_ db: Database? = nil, id: String) -> UIImage? {
        guard let db: Database = db else {
            return GRDBStorage.shared.read { db in profileAvatar(db, id: id) }
        }
        guard let profile: Profile = try? Profile.fetchOne(db, id: id) else { return nil }
        
        return profileAvatar(profile: profile)
    }
    
    public static func profileAvatar(profile: Profile) -> UIImage? {
        if let profileFileName: String = profile.profilePictureFileName, !profileFileName.isEmpty {
            return loadProfileAvatar(for: profileFileName)
        }
        
        if let profilePictureUrl: String = profile.profilePictureUrl, !profilePictureUrl.isEmpty {
            downloadAvatar(for: profile)
        }
        
        return nil
    }
    
    private static func loadProfileAvatar(for fileName: String) -> UIImage? {
        if let cachedImage: UIImage = profileAvatarCache.wrappedValue[fileName] {
            return cachedImage
        }
        
        guard
            !fileName.isEmpty,
            let data: Data = loadProfileData(with: fileName),
            data.isValidImage,
            let image: UIImage = UIImage(data: data)
        else {
            return nil
        }
    
        profileAvatarCache.mutate { $0[fileName] = image }
        return image
    }
    
    private static func loadProfileData(with fileName: String) -> Data? {
        let filePath: String = ProfileManager.profileAvatarFilepath(filename: fileName)
        
        return try? Data(contentsOf: URL(fileURLWithPath: filePath))
    }
    
    // MARK: - Profile Encryption
    
    private static func encryptProfileData(data: Data, key: OWSAES256Key) -> Data? {
        guard key.keyData.count == kAES256_KeyByteLength else { return nil }
        
        return Cryptography.encryptAESGCMProfileData(plainTextData: data, key: key)
    }
    
    private static func decryptProfileData(data: Data, key: OWSAES256Key) -> Data? {
        guard key.keyData.count == kAES256_KeyByteLength else { return nil }
        
        return Cryptography.decryptAESGCMProfileData(encryptedData: data, key: key)
    }
    
    // MARK: - File Paths
    
    public static let sharedDataProfileAvatarsDirPath: String = {
        URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
            .appendingPathComponent("ProfileAvatars")
            .path
    }()
    
    private static let profileAvatarsDirPath: String = {
        let path: String = ProfileManager.sharedDataProfileAvatarsDirPath
        OWSFileSystem.ensureDirectoryExists(path)
        
        return path
    }()
    
    public static func profileAvatarFilepath(filename: String) -> String {
        guard !filename.isEmpty else { return "" }
        
        return URL(fileURLWithPath: sharedDataProfileAvatarsDirPath)
            .appendingPathComponent(filename)
            .path
    }
    
    public static func resetProfileStorage() {
        try? FileManager.default.removeItem(atPath: ProfileManager.profileAvatarsDirPath)
    }
    
    // MARK: - Other Users' Profiles
    
    public static func downloadAvatar(for profile: Profile, funcName: String = #function) {
        guard !currentAvatarDownloads.wrappedValue.contains(profile.id) else {
            // Download already in flight; ignore
            return
        }
        guard
            let profileUrlStringAtStart: String = profile.profilePictureUrl,
            let profileUrlAtStart: URL = URL(string: profileUrlStringAtStart)
        else {
            SNLog("Skipping downloading avatar for \(profile.id) because url is not set")
            return
        }
        guard
            let fileId: Int64 = Int64(profileUrlAtStart.lastPathComponent),
            let profileKeyAtStart: OWSAES256Key = profile.profileEncryptionKey,
            profileKeyAtStart.keyData.count > 0
        else {
            return
        }
        
        let fileName: String = UUID().uuidString.appendingFileExtension("jpg")
        let filePath: String = ProfileManager.profileAvatarFilepath(filename: fileName)
        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: funcName)
        
        DispatchQueue.global(qos: .default).async {
            OWSLogger.verbose("downloading profile avatar: \(profile.id)")
            currentAvatarDownloads.mutate { $0.insert(profile.id) }
            
            let useOldServer: Bool = (profileUrlStringAtStart.contains(FileServerAPI.oldServer))
            
            FileServerAPI
                .download(fileId, useOldServer: useOldServer)
                .done { data in
                    currentAvatarDownloads.mutate { $0.remove(profile.id) }
                    
                    GRDBStorage.shared.write { db in
                        guard let latestProfile: Profile = try Profile.fetchOne(db, id: profile.id) else {
                            return
                        }
                        
                        guard
                            let latestProfileKey: OWSAES256Key = latestProfile.profileEncryptionKey,
                            !latestProfileKey.keyData.isEmpty,
                            latestProfileKey == profileKeyAtStart
                        else {
                            OWSLogger.warn("Ignoring avatar download for obsolete user profile.")
                            return
                        }
                        
                        guard profileUrlStringAtStart == latestProfile.profilePictureUrl else {
                            OWSLogger.warn("Avatar url has changed during download.")
                            
                            if latestProfile.profilePictureUrl?.isEmpty == false {
                                self.downloadAvatar(for: latestProfile)
                            }
                            return
                        }
                        
                        guard let decryptedData: Data = decryptProfileData(data: data, key: profileKeyAtStart) else {
                            OWSLogger.warn("Avatar data for \(profile.id) could not be decrypted.")
                            return
                        }
                        
                        try? decryptedData.write(to: URL(fileURLWithPath: filePath), options: [.atomic])
                        
                        guard let image: UIImage = UIImage(contentsOfFile: filePath) else {
                            OWSLogger.warn("Avatar image for \(profile.id) could not be loaded.")
                            return
                        }
                        
                        try? latestProfile
                            .with(profilePictureFileName: .update(fileName))
                            .update(db)
                        profileAvatarCache.mutate { $0[fileName] = image }
                    }
                    
                    // Redundant but without reading 'backgroundTask' it will warn that the variable
                    // isn't used
                    if backgroundTask != nil { backgroundTask = nil }
                }
                .retainUntilComplete()
        }
    }
    
    // MARK: - Current User Profile
    
    public static func updateLocal(
        queue: DispatchQueue,
        profileName: String,
        avatarImage: UIImage?,
        requiredSync: Bool,
        success: ((Database, Profile) throws -> ())? = nil,
        failure: ((ProfileManagerError) -> ())? = nil
    ) {
        queue.async {
            // If the profile avatar was updated or removed then encrypt with a new profile key
            // to ensure that other users know that our profile picture was updated
            let newProfileKey: OWSAES256Key = OWSAES256Key.generateRandom()
            
            guard let avatarImage: UIImage = avatarImage else {
                // If we have no image then we need to make sure to remove it from the profile
                GRDBStorage.shared.writeAsync { db in
                    let existingProfile: Profile = Profile.fetchOrCreateCurrentUser(db)
                    
                    OWSLogger.verbose(existingProfile.profilePictureUrl != nil ?
                        "Updating local profile on service with cleared avatar." :
                        "Updating local profile on service with no avatar."
                    )
                    
                    let updatedProfile: Profile = try existingProfile
                        .with(
                            name: profileName,
                            profilePictureUrl: nil,
                            profilePictureFileName: nil,
                            profileEncryptionKey: (existingProfile.profilePictureUrl != nil ?
                                .update(newProfileKey) :
                                .existing
                            )
                        )
                        .saved(db)
                    
                    // Remove any cached avatar image value
                    if let fileName: String = existingProfile.profilePictureFileName {
                        profileAvatarCache.mutate { $0[fileName] = nil }
                    }
                    
                    SNLog("Successfully updated service with profile.")
                    
                    try success?(db, updatedProfile)
                }
                return
            }

            // If we have a new avatar image, we must first:
            //
            // * Encode it to JPEG.
            // * Write it to disk.
            // * Encrypt it
            // * Upload it to asset service
            // * Send asset service info to Signal Service
            OWSLogger.verbose("Updating local profile on service with new avatar.")
            let maxAvatarBytes: UInt = (5 * 1000 * 1000)
            var image: UIImage = avatarImage

            if image.size.width != maxAvatarDiameter || image.size.height != maxAvatarDiameter {
                // To help ensure the user is being shown the same cropping of their avatar as
                // everyone else will see, we want to be sure that the image was resized before this point.
                SNLog("Avatar image should have been resized before trying to upload")
                image = image.resizedImage(toFillPixelSize: CGSize(width: maxAvatarDiameter, height: maxAvatarDiameter))
            }

            guard let data: Data = image.jpegData(compressionQuality: 0.95) else {
                SNLog("Updating service with profile failed.")
                failure?(.avatarWriteFailed)
                return
            }
            
            guard data.count <= maxAvatarBytes else {
                // Our avatar dimensions are so small that it's incredibly unlikely we wouldn't
                // be able to fit our profile photo (eg. generating pure noise at our resolution
                // compresses to ~200k)
                SNLog("Suprised to find profile avatar was too large. Was it scaled properly? image: \(image)")
                SNLog("Updating service with profile failed.")
                failure?(.avatarImageTooLarge)
                return
            }
            
            let fileName: String = UUID().uuidString.appendingFileExtension("jpg")
            let filePath: String = ProfileManager.profileAvatarFilepath(filename: fileName)
            
            // Write the avatar to disk
            do { try data.write(to: URL(fileURLWithPath: filePath), options: [.atomic]) }
            catch {
                SNLog("Updating service with profile failed.")
                failure?(.avatarWriteFailed)
                return
            }
            
            // Encrypt the avatar for upload
            guard let encryptedAvatarData: Data = encryptProfileData(data: data, key: newProfileKey) else {
                SNLog("Updating service with profile failed.")
                failure?(.avatarEncryptionFailed)
                return
            }
            
            // Upload the avatar to the FileServer
            FileServerAPI
                .upload(encryptedAvatarData)
                .done(on: queue) { fileId in
                    let downloadUrl: String = "\(FileServerAPI.server)/files/\(fileId)"
                    UserDefaults.standard[.lastProfilePictureUpload] = Date()
                    
                    GRDBStorage.shared.writeAsync { db in
                        let profile: Profile = try Profile
                            .fetchOrCreateCurrentUser(db)
                            .with(
                                name: profileName,
                                profilePictureUrl: .update(downloadUrl),
                                profilePictureFileName: .update(fileName),
                                profileEncryptionKey: .update(newProfileKey)
                            )
                            .saved(db)
                        
                        // Update the cached avatar image value
                        profileAvatarCache.mutate { $0[fileName] = avatarImage }
                        
                        SNLog("Successfully updated service with profile.")
                        try success?(db, profile)
                    }
                }
                .recover(on: queue) { error in
                    SNLog("Updating service with profile failed.")
                    
                    let isMaxFileSizeExceeded: Bool = ((error as? HTTP.Error) == HTTP.Error.maxFileSizeExceeded)
                    failure?(isMaxFileSizeExceeded ?
                        .avatarUploadMaxFileSizeExceeded :
                        .avatarUploadFailed
                    )
                }
                .retainUntilComplete()
        }
    }
}
