//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DebugUIMisc.h"
#import "DebugUIMessagesAssetLoader.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalServiceKit/OWSCountryMetadata.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/UIImage+OWS.h>
#import <SignalUI/AttachmentSharing.h>
#import <SignalUI/OWSTableViewController.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIMisc

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Misc.";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];

    [items addObject:[OWSTableItem itemWithTitle:@"Clear hasDismissedOffers"
                                     actionBlock:^{
                                         [DebugUIMisc clearHasDismissedOffers];
                                     }]];

    [items addObject:[OWSTableItem
                         itemWithTitle:@"Delete disappearing messages config"
                           actionBlock:^{
                               DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
                                   OWSDisappearingMessagesConfiguration *_Nullable config =
                                       [thread disappearingMessagesConfigurationWithTransaction:transaction];
                                   if (config) {
                                       [config anyRemoveWithTransaction:transaction];
                                   }
                               });
                           }]];

    __block __weak OWSTableItem *makeNextAppLaunchFailItemRef;
    [items addObject:[OWSTableItem itemWithTitle:@"Make next app launch fail"
                                     actionBlock:^{
                                         [[CurrentAppContext() appUserDefaults] setInteger:10
                                                                                    forKey:kAppLaunchesAttemptedKey];
                                         [makeNextAppLaunchFailItemRef.tableViewController
                                             presentToastWithText:@"Okay, the next app launch will fail!"
                                                      extraVInset:0];
                                     }]];
    makeNextAppLaunchFailItemRef = items.lastObject;

    [items addObject:[OWSTableItem
                         itemWithTitle:@"Re-register"
                           actionBlock:^{
                               [OWSActionSheets
                                   showConfirmationAlertWithTitle:@"Re-register?"
                                                          message:@"If you proceed, you will not lose any of your "
                                                                  @"current messages, but your account will be "
                                                                  @"deactivated until you complete re-registration."
                                                     proceedTitle:@"Proceed"
                                                     proceedStyle:ActionSheetActionStyleDefault
                                                    proceedAction:^(ActionSheetAction *_Nonnull action) {
                                                        [DebugUIMisc reregister];
                                                    }];
                           }]];


    __weak DebugUIMisc *weakSelf = self;
    [items addObject:[OWSTableItem itemWithTitle:@"Show 2FA Reminder" actionBlock:^() { [weakSelf showPinReminder]; }]];

    [items addObject:[OWSTableItem
                         itemWithTitle:@"Reset 2FA Repetition Interval"
                           actionBlock:^() {
                               DatabaseStorageWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
                                   [OWS2FAManager.shared setDefaultRepetitionIntervalWithTransaction:transaction];
                               });
                           }]];

    [items addObject:[OWSTableItem subPageItemWithText:@"Share UIImage"
                                           actionBlock:^(UIViewController *viewController) {
                                               UIImage *image = [UIImage imageWithColor:UIColor.redColor
                                                                                   size:CGSizeMake(1.f, 1.f)];
                                               [AttachmentSharing showShareUIForUIImage:image];
                                           }]];
    [items addObject:[OWSTableItem subPageItemWithText:@"Share 2 Images"
                                           actionBlock:^(UIViewController *viewController) {
                                               [DebugUIMisc shareImages:2];
                                           }]];
    [items addObject:[OWSTableItem subPageItemWithText:@"Share 2 Videos"
                                           actionBlock:^(UIViewController *viewController) {
                                               [DebugUIMisc shareVideos:2];
                                           }]];
    [items addObject:[OWSTableItem subPageItemWithText:@"Share 2 PDFs"
                                           actionBlock:^(UIViewController *viewController) {
                                               [DebugUIMisc sharePDFs:2];
                                           }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Fetch system contacts"
                           actionBlock:^() { [Environment.shared.contactsManagerImpl requestSystemContactsOnce]; }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Cycle websockets"
                                     actionBlock:^() {
                                         [SSKEnvironment.shared.socketManager cycleSocket];
                                     }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Flag database as corrupted"
                                     actionBlock:^() { [DebugUIMisc showFlagDatabaseAsCorruptedUi]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Add 1k KV keys"
                                     actionBlock:^() {
                                         [DebugUIMisc populateRandomKeyValueStores:1 * 1000];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Add 10k KV keys"
                                     actionBlock:^() {
                                         [DebugUIMisc populateRandomKeyValueStores:10 * 1000];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Add 100k KV keys"
                                     actionBlock:^() {
                                         [DebugUIMisc populateRandomKeyValueStores:100 * 1000];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Add 1m KV keys"
                                     actionBlock:^() {
                                         [DebugUIMisc populateRandomKeyValueStores:1000 * 1000];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Clear Random KV keys"
                                     actionBlock:^() { [DebugUIMisc clearRandomKeyValueStores]; }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Delete all threads without leaving groups or removing interactions"
                                     actionBlock:^{
                                         DatabaseStorageWrite(
                                             SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
                                                 [TSThread anyRemoveAllWithoutInstantationWithTransaction:transaction];
                                             });
                                     }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Save plaintext database key"
                                     actionBlock:^() { [DebugUIMisc enableExternalDatabaseAccess]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Update account attributes"
                                     actionBlock:^() { [TSAccountManager.shared updateAccountAttributes]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Check Prekeys"
                                     actionBlock:^() { [TSPreKeyManager checkPreKeysImmediately]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Remove All Prekeys"
                                     actionBlock:^() { [DebugUIMisc removeAllPrekeys]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Remove All Sessions"
                                     actionBlock:^() { [DebugUIMisc removeAllSessions]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Fake PNI pre-key upload failures"
                                     actionBlock:^() {
                                         [TSPreKeyManager storeFakePreKeyUploadFailuresForIdentity:OWSIdentityPNI];
                                     }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Remove local PNI identity key"
                                     actionBlock:^() { [DebugUIMisc removeLocalPniIdentityKey]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Discard All Profile Keys"
                                     actionBlock:^() { [DebugUIMisc discardAllProfileKeys]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Log all sticker suggestions"
                                     actionBlock:^() { [DebugUIMisc logStickerSuggestions]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Create chat colors"
                                     actionBlock:^() { [DebugUIMisc createChatColors]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Log Local Account"
                                     actionBlock:^() { [DebugUIMisc logLocalAccount]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Log SignalRecipients"
                                     actionBlock:^() { [DebugUIMisc logSignalRecipients]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Log SignalAccounts"
                                     actionBlock:^() { [DebugUIMisc logSignalAccounts]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Log ContactThreads"
                                     actionBlock:^() { [DebugUIMisc logContactThreads]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Clear Profile Key Credentials"
                                     actionBlock:^() { [DebugUIMisc clearProfileKeyCredentials]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Clear Temporal Credentials"
                                     actionBlock:^() { [DebugUIMisc clearTemporalCredentials]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Clear custom reaction emoji (locally)"
                                     actionBlock:^() { [DebugUIMisc clearLocalCustomEmoji]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Clear My Story privacy settings"
                                     actionBlock:^() { [DebugUIMisc clearMyStoryPrivacySettings]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Enable username education prompt"
                                     actionBlock:^() { [DebugUIMisc enableUsernameEducation]; }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Delete all persisted ExperienceUpgrade records"
                                     actionBlock:^() { [DebugUIMisc removeAllRecordedExperienceUpgrades]; }]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)removeAllPrekeys
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        SignalProtocolStore *signalProtocolStore = [self signalProtocolStoreForIdentity:OWSIdentityACI];
        [signalProtocolStore.signedPreKeyStore removeAll:transaction];
        [signalProtocolStore.preKeyStore removeAll:transaction];

        signalProtocolStore = [self signalProtocolStoreForIdentity:OWSIdentityPNI];
        [signalProtocolStore.signedPreKeyStore removeAll:transaction];
        [signalProtocolStore.preKeyStore removeAll:transaction];
    });
}

+ (void)removeAllSessions
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        SignalProtocolStore *signalProtocolStore = [self signalProtocolStoreForIdentity:OWSIdentityACI];
        [signalProtocolStore.sessionStore removeAllWithTransaction:transaction];
        [signalProtocolStore.signedPreKeyStore removeAll:transaction];
        [signalProtocolStore.preKeyStore removeAll:transaction];
    });
}

+ (void)removeLocalPniIdentityKey
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.identityManager storeIdentityKeyPair:nil forIdentity:OWSIdentityPNI transaction:transaction];
    });
}

+ (void)discardAllProfileKeys
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [OWSProfileManager discardAllProfileKeysWithTransaction:transaction];
    });
}

+ (void)reregister
{
    OWSLogInfo(@"re-registering.");

    [RegistrationUtils reregisterFromViewController:[SignalApp.shared conversationSplitViewController]];
}

+ (void)clearHasDismissedOffers
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        NSMutableArray<TSContactThread *> *contactThreads = [NSMutableArray new];
        [TSThread anyEnumerateWithTransaction:transaction
                                        block:^(TSThread *thread, BOOL *stop) {
                                            if (thread.isGroupThread) {
                                                return;
                                            }
                                            TSContactThread *contactThread = (TSContactThread *)thread;
                                            [contactThreads addObject:contactThread];
                                        }];

        for (TSContactThread *contactThread in contactThreads) {
            if (contactThread.hasDismissedOffers) {
                [contactThread anyUpdateContactThreadWithTransaction:transaction
                                                               block:^(TSContactThread *thread) {
                                                                   thread.hasDismissedOffers = NO;
                                                               }];
            }
        }
    });
}

+ (void)sendAttachment:(SignalAttachment *)attachment thread:(TSThread *)thread
{
    if (!attachment || [attachment hasError]) {
        OWSFailDebug(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
        return;
    }
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        [ThreadUtil enqueueMessageWithBody:nil
                          mediaAttachments:@[ attachment ]
                                    thread:thread
                          quotedReplyModel:nil
                          linkPreviewDraft:nil
              persistenceCompletionHandler:nil
                               transaction:transaction];
    }];
}

+ (void)shareAssets:(NSUInteger)count
   fromAssetLoaders:(NSArray<DebugUIMessagesAssetLoader *> *)assetLoaders
{
    [DebugUIMessagesAssetLoader prepareAssetLoaders:assetLoaders
        success:^{
            [self shareAssets:count fromPreparedAssetLoaders:assetLoaders];
        }
        failure:^{
            OWSLogError(@"Could not prepare asset loaders.");
        }];
}

+ (void)shareAssets:(NSUInteger)count fromPreparedAssetLoaders:(NSArray<DebugUIMessagesAssetLoader *> *)assetLoaders
{
    __block NSMutableArray<NSURL *> *urls = [NSMutableArray new];
    for (NSUInteger i = 0;i < count;i++) {
        DebugUIMessagesAssetLoader *assetLoader = assetLoaders[arc4random_uniform((uint32_t) assetLoaders.count)];
        NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:assetLoader.filePath.pathExtension];
        NSError *error;
        [[NSFileManager defaultManager] copyItemAtPath:assetLoader.filePath toPath:filePath error:&error];
        OWSAssertDebug(!error);
        [urls addObject:[NSURL fileURLWithPath:filePath]];
    }
    OWSLogVerbose(@"urls: %@", urls);
    [AttachmentSharing showShareUIForURLs:urls
                                   sender:nil
                               completion:^{
                                   urls = nil;
                               }];
}

+ (void)shareImages:(NSUInteger)count
{
    [self shareAssets:count
        fromAssetLoaders:@[
            [DebugUIMessagesAssetLoader jpegInstance],
            [DebugUIMessagesAssetLoader tinyPngInstance],
        ]];
}

+ (void)shareVideos:(NSUInteger)count
{
    [self shareAssets:count
        fromAssetLoaders:@[
            [DebugUIMessagesAssetLoader mp4Instance],
        ]];
}

+ (void)sharePDFs:(NSUInteger)count
{
    [self shareAssets:count
        fromAssetLoaders:@[
            [DebugUIMessagesAssetLoader tinyPdfInstance],
        ]];
}

+ (SDSKeyValueStore *)randomKeyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"randomKeyValueStore"];
}

+ (void)populateRandomKeyValueStores:(NSUInteger)keyCount
{
    SDSKeyValueStore *store = self.randomKeyValueStore;

    const NSUInteger kBatchSize = 1000;
    const NSUInteger batchCount = keyCount / kBatchSize;
    OWSLogVerbose(@"keyCount: %i", (int)keyCount);
    OWSLogVerbose(@"batchCount: %i", (int)batchCount);
    for (NSUInteger batchIndex = 0; batchIndex < batchCount; batchIndex++) {
        OWSLogVerbose(@"batchIndex: %i / %i", (int)batchIndex, (int)batchCount);

        @autoreleasepool {
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                // Set three values at a time.
                for (NSUInteger keyIndex = 0; keyIndex < kBatchSize; keyIndex += 3) {
                    NSData *value = [Randomness generateRandomBytes:4096];
                    [store setData:value key:NSUUID.UUID.UUIDString transaction:transaction];
                    
                    [store setString:NSUUID.UUID.UUIDString key:NSUUID.UUID.UUIDString transaction:transaction];
                    
                    [store setBool:true key:NSUUID.UUID.UUIDString transaction:transaction];
                }
            });
        }
    }
}

+ (void)clearRandomKeyValueStores
{
    SDSKeyValueStore *store = self.randomKeyValueStore;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [store removeAllWithTransaction:transaction];
    });
}

+ (void)enableExternalDatabaseAccess
{
    if (!Platform.isSimulator) {
        [OWSActionSheets showErrorAlertWithMessage:@"Must be running in the simulator"];
        return;
    }
    [OWSActionSheets
        showConfirmationAlertWithTitle:@"⚠️⚠️⚠️ Warning!!! ⚠️⚠️⚠️"
                               message:
                                   @"This will save your database key in plaintext and severely weaken the security of "
                                   @"all data. Make sure you're using a test account with data you don't care about."
                          proceedTitle:@"I'm okay with this"
                          proceedStyle:ActionSheetActionStyleDestructive
                         proceedAction:^(ActionSheetAction *action) {
                             // This should be caught above. Fatal assert just in case.
                             OWSAssert(OWSIsTestableBuild() && Platform.isSimulator);

                             // Note: These static strings go hand-in-hand with Scripts/sqlclient.py
                             NSDictionary *payload =
                                 @ { @"key" : [GRDBDatabaseStorageAdapter.debugOnly_keyData hexadecimalString] };
                             NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload
                                                                                   options:NSJSONWritingPrettyPrinted
                                                                                     error:nil];

                             NSURL *groupDir = [NSURL fileURLWithPath:OWSFileSystem.appSharedDataDirectoryPath
                                                          isDirectory:YES];
                             NSURL *destURL = [groupDir URLByAppendingPathComponent:@"dbPayload.txt"];
                             [payloadData writeToURL:destURL atomically:YES];
                         }];
}

+ (void)logStickerSuggestions
{
    NSMutableSet<NSString *> *emojiSet = [NSMutableSet new];
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        for (StickerPack *stickerPack in [StickerManager installedStickerPacksWithTransaction:transaction]) {
            
            for (StickerPackItem *item in stickerPack.items) {
                if (item.emojiString.length > 0) {
                    OWSLogVerbose(@"emojiString: %@", item.emojiString);
                    [emojiSet addObject:item.emojiString];
                }
            }
        }
    }];
    OWSLogVerbose(@"emoji: %@",
        [[emojiSet.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]);
}

+ (void)createChatColors
{
    DatabaseStorageWrite(SDSDatabaseStorage.shared,
        ^(SDSAnyWriteTransaction *transaction) { [ChatColors createFakeChatColorsWithTransaction:transaction]; });
}

@end

NS_ASSUME_NONNULL_END

#endif
