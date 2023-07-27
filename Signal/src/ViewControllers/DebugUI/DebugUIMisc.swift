//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
import SignalMessaging
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIMisc: DebugUIPage, Dependencies {

    let name = "Misc."

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()

        if let thread {
            items.append(OWSTableItem(title: "Delete disappearing messages config", actionBlock: {
                self.databaseStorage.write { transaction in
                    let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                    dmConfigurationStore.remove(for: thread, tx: transaction.asV2Write)
                }
            }))
        }

        items += [
            OWSTableItem(title: "Make next app launch fail", actionBlock: {
                CurrentAppContext().appUserDefaults().set(10, forKey: kAppLaunchesAttemptedKey)
                if let frontmostViewController = CurrentAppContext().frontmostViewController() {
                    frontmostViewController.presentToast(text: "Okay, the next app launch will fail!")
                }
            }),

            OWSTableItem(title: "Re-register", actionBlock: {
                OWSActionSheets.showConfirmationAlert(
                    title: "Re-register?",
                    message: "If you proceed, you will not lose any of your current messages, " +
                        "but your account will be deactivated until you complete re-registration.",
                    proceedTitle: "Proceed",
                    proceedAction: { _ in
                        DebugUIMisc.reregister()
                    }
                )
            }),

            OWSTableItem(title: "Show 2FA Reminder", actionBlock: {
                DebugUIMisc.showPinReminder()
            }),
            OWSTableItem(title: "Reset 2FA Repetition Interval", actionBlock: {
                SDSDatabaseStorage.shared.write { transaction in
                    OWS2FAManager.shared.setDefaultRepetitionIntervalWith(transaction)
                }
            }),

            OWSTableItem(title: "Share UIImage", actionBlock: {
                let image = UIImage(color: .red, size: .square(1))
                AttachmentSharing.showShareUI(for: image)
            }),
            OWSTableItem(title: "Share 2 images", actionBlock: {
                DebugUIMisc.shareImages(2)
            }),
            OWSTableItem(title: "Share 2 videos", actionBlock: {
                DebugUIMisc.shareVideos(2)
            }),
            OWSTableItem(title: "Share 2 PDFs", actionBlock: {
                DebugUIMisc.sharePDFs(2)
            }),

            OWSTableItem(title: "Fetch system contacts", actionBlock: {
                SSKEnvironment.shared.contactsManagerImpl.requestSystemContactsOnce()
            }),
            OWSTableItem(title: "Cycle websockets", actionBlock: {
                SSKEnvironment.shared.socketManager.cycleSocket()
            }),
            OWSTableItem(title: "Flag database as corrupted", actionBlock: {
                DebugUIMisc.showFlagDatabaseAsCorruptedUi()
            }),
            OWSTableItem(title: "Flag database as read corrupted", actionBlock: {
                DebugUIMisc.showFlagDatabaseAsReadCorruptedUi()
            }),

            OWSTableItem(title: "Add 1k KV keys", actionBlock: {
                DebugUIMisc.populateRandomKeyValueStores(keyCount: 1 * 1000)
            }),
            OWSTableItem(title: "Add 10k KV keys", actionBlock: {
                DebugUIMisc.populateRandomKeyValueStores(keyCount: 10 * 1000)
            }),
            OWSTableItem(title: "Add 100k KV keys", actionBlock: {
                DebugUIMisc.populateRandomKeyValueStores(keyCount: 100 * 1000)
            }),
            OWSTableItem(title: "Add 1m KV keys", actionBlock: {
                DebugUIMisc.populateRandomKeyValueStores(keyCount: 1000 * 1000)
            }),
            OWSTableItem(title: "Clear Random KV keys", actionBlock: {
                DebugUIMisc.clearRandomKeyValueStores()
            }),

            OWSTableItem(title: "Save plaintext database key", actionBlock: {
                DebugUIMisc.enableExternalDatabaseAccess()
            }),

            OWSTableItem(title: "Update account attributes", actionBlock: {
                TSAccountManager.shared.updateAccountAttributes()
            }),

            OWSTableItem(title: "Check Prekeys", actionBlock: {
                TSPreKeyManager.checkPreKeysImmediately()
            }),
            OWSTableItem(title: "Remove All Prekeys", actionBlock: {
                DebugUIMisc.removeAllPrekeys()
            }),
            OWSTableItem(title: "Remove All Sessions", actionBlock: {
                DebugUIMisc.removeAllSessions()
            }),
            OWSTableItem(title: "Fake PNI pre-key upload failures", actionBlock: {
                TSPreKeyManager.storeFakePreKeyUploadFailures(for: .pni)
            }),
            OWSTableItem(title: "Remove local PNI identity key", actionBlock: {
                DebugUIMisc.removeLocalPniIdentityKey()
            }),
            OWSTableItem(title: "Discard All Profile Keys", actionBlock: {
                DebugUIMisc.discardAllProfileKeys()
            }),

            OWSTableItem(title: "Log all sticker suggestions", actionBlock: {
                DebugUIMisc.logStickerSuggestions()
            }),

            OWSTableItem(title: "Log Local Account", actionBlock: {
                DebugUIMisc.logLocalAccount()
            }),

            OWSTableItem(title: "Log SignalRecipients", actionBlock: {
                DebugUIMisc.logSignalRecipients()
            }),

            OWSTableItem(title: "Log SignalAccounts", actionBlock: {
                DebugUIMisc.logSignalAccounts()
            }),

            OWSTableItem(title: "Log ContactThreads", actionBlock: {
                DebugUIMisc.logContactThreads()
            }),

            OWSTableItem(title: "Clear Profile Key Credentials", actionBlock: {
                DebugUIMisc.clearProfileKeyCredentials()
            }),

            OWSTableItem(title: "Clear Temporal Credentials", actionBlock: {
                DebugUIMisc.clearTemporalCredentials()
            }),

            OWSTableItem(title: "Clear custom reaction emoji (locally)", actionBlock: {
                DebugUIMisc.clearLocalCustomEmoji()
            }),

            OWSTableItem(title: "Clear My Story privacy settings", actionBlock: {
                DebugUIMisc.clearMyStoryPrivacySettings()
            }),

            OWSTableItem(title: "Enable username education prompt", actionBlock: {
                DebugUIMisc.enableUsernameEducation()
            }),

            OWSTableItem(title: "Enable username link tooltip", actionBlock: {
                DebugUIMisc.enableUsernameLinkTooltip()
            }),

            OWSTableItem(title: "Delete all persisted ExperienceUpgrade records", actionBlock: {
                DebugUIMisc.removeAllRecordedExperienceUpgrades()
            }),

            OWSTableItem(title: "Test spoiler animations", actionBlock: {
                DebugUIMisc.showSpoilerAnimationTestController()
            }),

            OWSTableItem(title: "Enable edit send beta prompt", actionBlock: {
                DebugUIMisc.enableEditBetaPromptMessage()
            })
        ]
        return OWSTableSection(title: name, items: items)
    }

    // MARK: Attachment Sharing

    private static func sendAttachment(_ attachment: SignalAttachment, toThread thread: TSThread) {
        guard !attachment.hasError else {
            owsFailDebug("attachment[\(String(describing: attachment.sourceFilename))]: \(String(describing: attachment.errorName))")
            return
        }
        databaseStorage.read { transaction in
            ThreadUtil.enqueueMessage(
                body: nil,
                mediaAttachments: [ attachment ],
                thread: thread,
                transaction: transaction
            )
        }
    }

    private static func shareAssets(_ count: UInt, fromAssetLoaders assetLoaders: [DebugUIMessagesAssetLoader]) {
        DebugUIMessagesAssetLoader.prepareAssetLoaders(assetLoaders) { result in
            switch result {
            case .success:
                DebugUIMisc.shareAssets(count, fromAssetLoaders: assetLoaders)

            case .failure(let error):
                Logger.error("Could not prepare asset loaders. \(error)")
            }
        }
    }

    private static func shareAssets(_ count: UInt, fromPreparedAssetLoaders assetLoaders: [DebugUIMessagesAssetLoader]) {
        let shuffledAssetLoaders = assetLoaders.shuffled()
        let urls: [URL] = shuffledAssetLoaders.compactMap { assetLoader in
            guard let assetFilePath = assetLoader.filePath else {
                owsFailDebug("assetLoader.filePath is nil")
                return nil
            }
            let filePath = OWSFileSystem.temporaryFilePath(fileExtension: assetFilePath.fileExtension)
            do {
                try FileManager.default.copyItem(atPath: assetFilePath, toPath: filePath)
                return URL(fileURLWithPath: filePath)
            } catch {
                Logger.error("Error while copying asset at [\(assetFilePath)]: \(error)")
                return nil
            }
        }
        Logger.verbose("urls: \(urls)")
        AttachmentSharing.showShareUI(for: urls, sender: nil, completion: nil)
    }

    private static func shareImages(_ count: UInt) {
        shareAssets(count, fromAssetLoaders: [
            DebugUIMessagesAssetLoader.jpegInstance,
            DebugUIMessagesAssetLoader.tinyPngInstance
        ])
    }

    private static func shareVideos(_ count: UInt) {
        shareAssets(count, fromAssetLoaders: [ DebugUIMessagesAssetLoader.mp4Instance ])
    }

    private static func sharePDFs(_ count: UInt) {
        shareAssets(count, fromAssetLoaders: [ DebugUIMessagesAssetLoader.tinyPdfInstance ])
    }

    // MARK: KVS

    private static func randomKeyValueStore() -> SDSKeyValueStore {
        SDSKeyValueStore(collection: "randomKeyValueStore")
    }

    private static func populateRandomKeyValueStores(keyCount: UInt) {
        let store = randomKeyValueStore()

        let kBatchSize: UInt = 1000
        let batchCount: UInt = keyCount / kBatchSize
        Logger.verbose("keyCount: \(keyCount)")
        Logger.verbose("batchCount: \(batchCount)")
        for batchIndex in 0..<batchCount {
            Logger.verbose("batchIndex: \(batchIndex) / \(batchCount)")

            autoreleasepool {
                databaseStorage.write { transaction in
                    // Set three values at a time.
                    for _ in 0..<kBatchSize / 3 {
                        let value = Randomness.generateRandomBytes(4096)
                        store.setData(value, key: UUID().uuidString, transaction: transaction)
                        store.setString(UUID().uuidString, key: UUID().uuidString, transaction: transaction)
                        store.setBool(Bool.random(), key: UUID().uuidString, transaction: transaction)
                    }
                }
            }
        }
    }

    private static func clearRandomKeyValueStores() {
        let store = randomKeyValueStore()
        databaseStorage.write { transcation in
            store.removeAll(transaction: transcation)
        }
    }

    // MARK: -

    private static func reregister() {
        Logger.info("Re-registering.")
        RegistrationUtils.reregister(fromViewController: SignalApp.shared.conversationSplitViewController!)
    }

    private static func enableExternalDatabaseAccess() {
        guard Platform.isSimulator else {
            OWSActionSheets.showErrorAlert(message: "Must be running in the simulator")
            return
        }
        OWSActionSheets.showConfirmationAlert(
            title: "⚠️⚠️⚠️ Warning!!! ⚠️⚠️⚠️",
            message: "This will save your database key in plaintext and severely weaken the security of " +
                "all data. Make sure you're using a test account with data you don't care about.",
            proceedTitle: "I'm okay with this",
            proceedStyle: .destructive,
            proceedAction: { _ in
                // This should be caught above. Fatal assert just in case.
                owsAssert(OWSIsTestableBuild() && Platform.isSimulator)

                // Note: These static strings go hand-in-hand with Scripts/sqlclient.py
                let payload = [ "key": GRDBDatabaseStorageAdapter.debugOnly_keyData?.hexadecimalString ]
                let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)

                let groupDir = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath(), isDirectory: true)
                let destURL = groupDir.appendingPathComponent("dbPayload.txt")
                try! payloadData.write(to: destURL, options: .atomic)
            }
        )
    }

    private static func removeAllPrekeys() {
        databaseStorage.write { transaction in
            let signalProtoclStoreManager = DependenciesBridge.shared.signalProtocolStoreManager
            let signalProtocolStoreACI = signalProtoclStoreManager.signalProtocolStore(for: .aci)
            signalProtocolStoreACI.signedPreKeyStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStoreACI.preKeyStore.removeAll(tx: transaction.asV2Write)

            let signalProtocolStorePNI = signalProtoclStoreManager.signalProtocolStore(for: .pni)
            signalProtocolStorePNI.signedPreKeyStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStorePNI.preKeyStore.removeAll(tx: transaction.asV2Write)
        }
    }

    private static func removeAllSessions() {
        databaseStorage.write { transaction in
            let signalProtoclStoreManager = DependenciesBridge.shared.signalProtocolStoreManager

            let signalProtocolStoreACI = signalProtoclStoreManager.signalProtocolStore(for: .aci)
            signalProtocolStoreACI.sessionStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStoreACI.signedPreKeyStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStoreACI.preKeyStore.removeAll(tx: transaction.asV2Write)

            let signalProtocolStorePNI = signalProtoclStoreManager.signalProtocolStore(for: .pni)
            signalProtocolStorePNI.sessionStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStorePNI.signedPreKeyStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStorePNI.preKeyStore.removeAll(tx: transaction.asV2Write)
        }
    }

    private static func removeLocalPniIdentityKey() {
        databaseStorage.write { transaction in
            identityManager.storeIdentityKeyPair(nil, for: .pni, transaction: transaction)
        }
    }

    private static func discardAllProfileKeys() {
        databaseStorage.write { transaction in
            OWSProfileManager.discardAllProfileKeys(with: transaction)
        }
    }

    private static func logStickerSuggestions() {
        var emojiSet = Set<String>()
        databaseStorage.read { transaction in
            StickerManager.installedStickerPacks(transaction: transaction).forEach { stickerPack in
                stickerPack.items.forEach { item in
                    let emojiString = item.emojiString
                    if !emojiString.isEmpty {
                        Logger.verbose("emojiString: \(emojiString)")
                        emojiSet.insert(emojiString)
                    }
                }
            }
        }
        let combinedEmojiString = emojiSet.sorted().joined(separator: " ")
        Logger.verbose("emoji: \(combinedEmojiString)")
    }

    private static func logLocalAccount() {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }
        if let uuid = localAddress.uuid {
            Logger.verbose("localAddress uuid: \(uuid)")
        }
        if let phoneNumber = localAddress.phoneNumber {
            Logger.verbose("localAddress phoneNumber: \(phoneNumber)")
        }
    }

    private static func logSignalRecipients() {
        Self.databaseStorage.read { tx in
            SignalRecipient.anyEnumerate(transaction: tx, batchingPreference: .batched(32)) { signalRecipient, _ in
                Logger.verbose("SignalRecipient: \(signalRecipient.addressComponentsDescription)")
            }
        }
    }

    private static func logSignalAccounts() {
        Self.databaseStorage.read { transaction in
            SignalAccount.anyEnumerate(transaction: transaction, batchingPreference: .batched(32)) { (signalAccount, _) in
                Logger.verbose("SignalAccount: \(signalAccount.addressComponentsDescription)")
            }
        }
    }

    private static func logContactThreads() {
        Self.databaseStorage.read { transaction in
            TSContactThread.anyEnumerate(transaction: transaction, batchSize: 32) { (thread, _) in
                guard let thread = thread as? TSContactThread else {
                    return
                }
                Logger.verbose("TSContactThread: \(thread.addressComponentsDescription)")
            }
        }
    }

    private static func clearProfileKeyCredentials() {
        Self.databaseStorage.write { transaction in
            Self.versionedProfiles.clearProfileKeyCredentials(transaction: transaction)
        }
    }

    private static func clearTemporalCredentials() {
        Self.databaseStorage.write { transaction in
            Self.groupsV2.clearTemporalCredentials(transaction: transaction)
        }
    }

    private static func clearLocalCustomEmoji() {
        Self.databaseStorage.write { transaction in
            ReactionManager.setCustomEmojiSet(nil, transaction: transaction)
        }
    }

    private static func showFlagDatabaseAsCorruptedUi() {
        OWSActionSheets.showConfirmationAlert(
            title: "Are you sure?",
            message: "This will flag your database as corrupted, which may mean all your data is lost. Are you sure you want to continue?",
            proceedTitle: "Corrupt my database",
            proceedStyle: .destructive
        ) { _ in
            DatabaseCorruptionState.flagDatabaseAsCorrupted(
                userDefaults: CurrentAppContext().appUserDefaults()
            )
            owsFail("Crashing due to (intentional) database corruption")
        }
    }

    private static func showFlagDatabaseAsReadCorruptedUi() {
        OWSActionSheets.showConfirmationAlert(
            title: "Are you sure?",
            message: "This will flag your database as possibly corrupted. It will not trigger a recovery on next startup. However, if you select the 'Make next app launch fail', the startup following the crash will funnel into the database recovery flow.",
            proceedTitle: "Mark database corrupted on read",
            proceedStyle: .destructive
        ) { _ in
            DatabaseCorruptionState.flagDatabaseAsReadCorrupted(
                userDefaults: CurrentAppContext().appUserDefaults()
            )
        }
    }

    private static func clearMyStoryPrivacySettings() {
        Self.databaseStorage.write { transaction in
            guard let myStoryThread = TSPrivateStoryThread.getMyStory(transaction: transaction) else {
                return
            }
            // Set to all connections which is the default.
            myStoryThread.updateWithStoryViewMode(
                .blockList,
                addresses: [],
                updateStorageService: false, /* storage service updated below */
                transaction: transaction
            )
            StoryManager.setHasSetMyStoriesPrivacy(false, transaction: transaction, shouldUpdateStorageService: true)
        }
    }

    private static func enableUsernameEducation() {
        databaseStorage.write { tx in
            DependenciesBridge.shared.usernameEducationManager.setShouldShowUsernameEducation(
                true,
                tx: tx.asV2Write
            )
        }
    }

    private static func enableUsernameLinkTooltip() {
        databaseStorage.write { tx in
            DependenciesBridge.shared.usernameEducationManager.setShouldShowUsernameLinkTooltip(
                true,
                tx: tx.asV2Write
            )
        }
    }

    private static func removeAllRecordedExperienceUpgrades() {
        databaseStorage.write { transaction in
            ExperienceUpgrade.anyRemoveAllWithInstantiation(transaction: transaction)
        }
    }

    private static func showPinReminder() {
        let viewController = PinReminderViewController()
        UIApplication.shared.frontmostViewController!.present(viewController, animated: true)
    }

    private static func showSpoilerAnimationTestController() {
        let viewController = SpoilerAnimationTestController()
        UIApplication.shared.frontmostViewController!.present(viewController, animated: true)
    }

    private static func enableEditBetaPromptMessage() {
        databaseStorage.write { tx in
            DependenciesBridge.shared.editManager.setShouldShowEditSendBetaConfirmation(
                true,
                tx: tx.asV2Write
            )
        }
    }
}

#endif
