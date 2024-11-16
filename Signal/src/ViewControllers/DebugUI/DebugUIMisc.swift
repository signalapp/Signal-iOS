//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIMisc: NSObject, DebugUIPage {

    let name = "Misc."

    private let appReadiness: AppReadinessSetter?

    init(appReadiness: AppReadinessSetter?) {
        self.appReadiness = appReadiness
    }

    func section(thread: TSThread?) -> OWSTableSection? {
        var items = [OWSTableItem]()

        if let thread {
            items.append(OWSTableItem(title: "Delete disappearing messages config", actionBlock: {
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                    dmConfigurationStore.remove(for: thread, tx: transaction.asV2Write)
                }
            }))
        }

        items += [
            OWSTableItem(title: "Corrupt username", actionBlock: {
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    DependenciesBridge.shared.localUsernameManager.setLocalUsernameCorrupted(tx: tx.asV2Write)
                }
            }),

            OWSTableItem(title: "Reenable disabled inactive linked device reminder megaphones", actionBlock: {
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    DependenciesBridge.shared.inactiveLinkedDeviceFinder
                        .reenablePermanentlyDisabledFinders(tx: tx.asV2Write)
                }
            })
        ]

        if let appReadiness {
            items.append(OWSTableItem(title: "Re-register", actionBlock: { [appReadiness] in
                OWSActionSheets.showConfirmationAlert(
                    title: "Re-register?",
                    message: "If you proceed, you will not lose any of your current messages, " +
                    "but your account will be deactivated until you complete re-registration.",
                    proceedTitle: "Proceed",
                    proceedAction: { _ in
                        DebugUIMisc.reregister(appReadiness: appReadiness)
                    }
                )
            }))
        }

        items += [
            OWSTableItem(title: "Show 2FA Reminder", actionBlock: {
                DebugUIMisc.showPinReminder()
            }),
            OWSTableItem(title: "Reset 2FA Repetition Interval", actionBlock: {
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    SSKEnvironment.shared.ows2FAManagerRef.setDefaultRepetitionInterval(transaction: transaction)
                }
            }),

            OWSTableItem(title: "Share UIImage", actionBlock: {
                let image = UIImage.image(color: .red, size: .square(1))
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
                SSKEnvironment.shared.contactManagerImplRef.requestSystemContactsOnce()
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
                Task {
                    try? await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
                }
            }),

            OWSTableItem(title: "Check Prekeys", actionBlock: {
                guard let preKeyManagerImpl = DependenciesBridge.shared.preKeyManager as? PreKeyManagerImpl else {
                    return
                }
                SSKEnvironment.shared.databaseStorageRef.read { tx in
                    preKeyManagerImpl.checkPreKeysImmediately(tx: tx.asV2Read)
                }
            }),
            OWSTableItem(title: "Remove All Prekeys", actionBlock: {
                DebugUIMisc.removeAllPrekeys()
            }),
            OWSTableItem(title: "Remove All Sessions", actionBlock: {
                DebugUIMisc.removeAllSessions()
            }),
            OWSTableItem(title: "Remove local PNI identity key", actionBlock: {
                DebugUIMisc.removeLocalPniIdentityKey()
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

            OWSTableItem(title: "Clear Profile Key Credentials", actionBlock: {
                DebugUIMisc.clearProfileKeyCredentials()
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

            OWSTableItem(title: "Mark flip cam button tooltip as unread", actionBlock: {
                let flipCamTooltipManager = FlipCameraTooltipManager(db: DependenciesBridge.shared.db)
                flipCamTooltipManager.markTooltipAsUnread()
            }),

            OWSTableItem(title: "Enable DeleteForMeSyncMessage info sheet", actionBlock: {
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    DeleteForMeInfoSheetCoordinator.fromGlobals()
                        .forceEnableInfoSheet(tx: tx.asV2Write)
                }
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
        ThreadUtil.enqueueMessage(
            body: nil,
            mediaAttachments: [ attachment ],
            thread: thread
        )
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

    private static func randomKeyValueStore() -> KeyValueStore {
        KeyValueStore(collection: "randomKeyValueStore")
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
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    // Set three values at a time.
                    for _ in 0..<kBatchSize / 3 {
                        let value = Randomness.generateRandomBytes(4096)
                        store.setData(value, key: UUID().uuidString, transaction: transaction.asV2Write)
                        store.setString(UUID().uuidString, key: UUID().uuidString, transaction: transaction.asV2Write)
                        store.setBool(Bool.random(), key: UUID().uuidString, transaction: transaction.asV2Write)
                    }
                }
            }
        }
    }

    private static func clearRandomKeyValueStores() {
        let store = randomKeyValueStore()
        SSKEnvironment.shared.databaseStorageRef.write { transcation in
            store.removeAll(transaction: transcation.asV2Write)
        }
    }

    // MARK: -

    private static func reregister(appReadiness: AppReadinessSetter) {
        Logger.info("Re-registering.")
        RegistrationUtils.reregister(
            fromViewController: SignalApp.shared.conversationSplitViewController!,
            appReadiness: appReadiness
        )
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
                debugOnly_savePlaintextDbKey()
            }
        )
    }

    static func debugOnly_savePlaintextDbKey() {
#if TESTABLE_BUILD && targetEnvironment(simulator)
        // Note: These static strings go hand-in-hand with Scripts/sqlclient.py
        let payload = [ "key": SSKEnvironment.shared.databaseStorageRef.keyFetcher.debugOnly_keyData()?.hexadecimalString ]
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)

        let groupDir = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath(), isDirectory: true)
        let destURL = groupDir.appendingPathComponent("dbPayload.txt")
        try! payloadData.write(to: destURL, options: .atomic)
#else
        // This should be caught above. Fatal assert just in case.
        owsFail("Can't savePlaintextDbKey")
#endif
    }

    private static func removeAllPrekeys() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
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
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            let signalProtoclStoreManager = DependenciesBridge.shared.signalProtocolStoreManager

            let signalProtocolStoreACI = signalProtoclStoreManager.signalProtocolStore(for: .aci)
            signalProtocolStoreACI.sessionStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStoreACI.signedPreKeyStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStoreACI.preKeyStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStoreACI.kyberPreKeyStore.removeAll(tx: transaction.asV2Write)

            let signalProtocolStorePNI = signalProtoclStoreManager.signalProtocolStore(for: .pni)
            signalProtocolStorePNI.sessionStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStorePNI.signedPreKeyStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStorePNI.preKeyStore.removeAll(tx: transaction.asV2Write)
            signalProtocolStorePNI.kyberPreKeyStore.removeAll(tx: transaction.asV2Write)
        }
    }

    private static func removeLocalPniIdentityKey() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            let identityManager = DependenciesBridge.shared.identityManager
            identityManager.setIdentityKeyPair(nil, for: .pni, tx: transaction.asV2Write)
        }
    }

    private static func logStickerSuggestions() {
        var emojiSet = Set<String>()
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
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
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
            owsFailDebug("Missing localAddress.")
            return
        }
        if let serviceId = localAddress.serviceId {
            Logger.verbose("localAddress serviceId: \(serviceId)")
        }
        if let phoneNumber = localAddress.phoneNumber {
            Logger.verbose("localAddress phoneNumber: \(phoneNumber)")
        }
    }

    private static func logSignalRecipients() {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            SignalRecipient.anyEnumerate(transaction: tx, batchingPreference: .batched(32)) { signalRecipient, _ in
                Logger.verbose("SignalRecipient: \(signalRecipient.addressComponentsDescription)")
            }
        }
    }

    private static func clearProfileKeyCredentials() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            SSKEnvironment.shared.versionedProfilesRef.clearProfileKeyCredentials(transaction: transaction)
        }
    }

    private static func clearLocalCustomEmoji() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
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
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
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
            StoryManager.setHasSetMyStoriesPrivacy(false, shouldUpdateStorageService: true, transaction: transaction)
        }
    }

    private static func enableUsernameEducation() {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            DependenciesBridge.shared.usernameEducationManager.setShouldShowUsernameEducation(
                true,
                tx: tx.asV2Write
            )
        }
    }

    private static func enableUsernameLinkTooltip() {
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            DependenciesBridge.shared.usernameEducationManager.setShouldShowUsernameLinkTooltip(
                true,
                tx: tx.asV2Write
            )
        }
    }

    private static func removeAllRecordedExperienceUpgrades() {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
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
}

#endif
