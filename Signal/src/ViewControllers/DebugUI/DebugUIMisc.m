//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "DebugUIMisc.h"
#import "DebugUIMessagesAssetLoader.h"
#import "OWSBackup.h"
#import "OWSCountryMetadata.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <AxolotlKit/PreKeyBundle.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/AttachmentSharing.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SSKSessionStore.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/UIImage+OWS.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@interface OWSStorage (DebugUI)

- (NSData *)databasePassword;

@end

#pragma mark -

@implementation DebugUIMisc

#pragma mark - Dependencies

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Misc.";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];
    [items addObject:[OWSTableItem itemWithTitle:@"Enable Manual Censorship Circumvention"
                                     actionBlock:^{
                                         [DebugUIMisc setManualCensorshipCircumventionEnabled:YES];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Disable Manual Censorship Circumvention"
                                     actionBlock:^{
                                         [DebugUIMisc setManualCensorshipCircumventionEnabled:NO];
                                     }]];
    [items addObject:[OWSTableItem
                         itemWithTitle:@"Clear experience upgrades (works once per launch)"
                           actionBlock:^{
                               [DebugUIMisc.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                                   [ExperienceUpgrade anyRemoveAllWithoutInstantationWithTransaction:transaction];
                               }];
                           }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Clear hasDismissedOffers"
                                     actionBlock:^{
                                         [DebugUIMisc clearHasDismissedOffers];
                                     }]];

    [items addObject:[OWSTableItem
                         itemWithTitle:@"Delete disappearing messages config"
                           actionBlock:^{
                               [DebugUIMisc.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                                   OWSDisappearingMessagesConfiguration *_Nullable config =
                                       [thread disappearingMessagesConfigurationWithTransaction:transaction];
                                   if (config) {
                                       [config anyRemoveWithTransaction:transaction];
                                   }
                               }];
                           }]];

    [items addObject:[OWSTableItem
                         itemWithTitle:@"Re-register"
                           actionBlock:^{
                               [OWSAlerts
                                   showConfirmationAlertWithTitle:@"Re-register?"
                                                          message:@"If you proceed, you will not lose any of your "
                                                                  @"current messages, but your account will be "
                                                                  @"deactivated until you complete re-registration."
                                                     proceedTitle:@"Proceed"
                                                    proceedAction:^(UIAlertAction *_Nonnull action) {
                                                        [DebugUIMisc reregister];
                                                    }];
                           }]];


    if (thread) {
        [items addObject:[OWSTableItem itemWithTitle:@"Send Encrypted Database"
                                         actionBlock:^{
                                             [DebugUIMisc sendEncryptedDatabase:thread];
                                         }]];
        [items addObject:[OWSTableItem itemWithTitle:@"Send Unencrypted Database"
                                         actionBlock:^{
                                             [DebugUIMisc sendUnencryptedDatabase:thread];
                                         }]];
    }

    [items addObject:[OWSTableItem itemWithTitle:@"Show 2FA Reminder"
                                     actionBlock:^() {
                                         UIViewController *reminderVC;
                                         if (SSKFeatureFlags.pinsForEveryone) {
                                             reminderVC = [OWSPinReminderViewController new];
                                         } else {
                                             reminderVC = [OWS2FAReminderViewController wrappedInNavController];
                                             reminderVC.modalPresentationStyle = UIModalPresentationFullScreen;
                                         }

                                         [[[UIApplication sharedApplication] frontmostViewController]
                                             presentViewController:reminderVC
                                                          animated:YES
                                                        completion:nil];
                                     }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Reset 2FA Repetition Interval"
                                     actionBlock:^() {
                                         [OWS2FAManager.sharedManager setDefaultRepetitionInterval];
                                     }]];

    [items addObject:[OWSTableItem subPageItemWithText:@"Share UIImage"
                                           actionBlock:^(UIViewController *viewController) {
                                               UIImage *image =
                                               [UIImage imageWithColor:UIColor.redColor size:CGSizeMake(1.f, 1.f)];
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
                         itemWithTitle:@"Increment Database Extension Versions"
                           actionBlock:^() {
                               if (SSKFeatureFlags.storageMode == StorageModeYdb) {
                                   for (NSString *extensionName in OWSPrimaryStorage.shared.registeredExtensionNames) {
                                       [OWSStorage incrementVersionOfDatabaseExtension:extensionName];
                                   }
                               }
                           }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Fetch system contacts"
                                     actionBlock:^() {
                                         [Environment.shared.contactsManager requestSystemContactsOnce];
                                     }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Cycle websockets"
                                     actionBlock:^() {
                                         [SSKEnvironment.shared.socketManager cycleSocket];
                                     }]];

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
                                     actionBlock:^() {
                                         [DebugUIMisc clearRandomKeyValueStores];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Save one of each model"
                                     actionBlock:^() {
                                         [DebugUIMisc saveOneOfEachModel];
                                     }]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)reregister
{
    OWSLogInfo(@"re-registering.");

    if (![[TSAccountManager sharedInstance] resetForReregistration]) {
        OWSFailDebug(@"could not reset for re-registration.");
        return;
    }

    [Environment.shared.preferences unsetRecordedAPNSTokens];

    UIViewController *viewController = [[OnboardingController new] initialViewController];
    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:viewController];
    navigationController.navigationBarHidden = YES;

    [UIApplication sharedApplication].delegate.window.rootViewController = navigationController;
}

+ (void)setManualCensorshipCircumventionEnabled:(BOOL)isEnabled
{
    OWSCountryMetadata *countryMetadata = nil;
    NSString *countryCode = OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode;
    if (countryCode) {
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
    }

    if (!countryMetadata) {
        countryCode = [PhoneNumber defaultCountryCode];
        if (countryCode) {
            countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
        }
    }

    if (!countryMetadata) {
        countryCode = @"US";
        countryMetadata = [OWSCountryMetadata countryMetadataForCountryCode:countryCode];
    }

    OWSAssertDebug(countryMetadata);
    OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode = countryCode;
    OWSSignalService.sharedInstance.isCensorshipCircumventionManuallyActivated = isEnabled;
}

+ (void)clearHasDismissedOffers
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
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
    }];
}

+ (void)sendEncryptedDatabase:(TSThread *)thread
{
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"sqlite"];
    NSString *fileName = filePath.lastPathComponent;

    __block BOOL success;
    [self.databaseStorage
        writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            NSError *error;
            success = [[NSFileManager defaultManager] copyItemAtPath:OWSPrimaryStorage.databaseFilePath
                                                              toPath:filePath
                                                               error:&error];
            if (!success || error) {
                OWSFailDebug(@"Could not copy database file: %@.", error);
                success = NO;
            }
        }];

    if (!success) {
        return;
    }

    NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:fileName.pathExtension];
    NSError *error;
    _Nullable id<DataSource> dataSource = [DataSourcePath dataSourceWithFilePath:filePath
                                                      shouldDeleteOnDeallocation:YES
                                                                           error:&error];
    OWSAssertDebug(dataSource != nil);
    [dataSource setSourceFilename:fileName];
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType];
    NSData *databasePassword = [OWSPrimaryStorage.shared databasePassword];
    attachment.captionText = [databasePassword hexadecimalString];
    [self sendAttachment:attachment thread:thread];
}

+ (void)sendAttachment:(SignalAttachment *)attachment thread:(TSThread *)thread
{
    if (!attachment || [attachment hasError]) {
        OWSFailDebug(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
        return;
    }
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        [ThreadUtil enqueueMessageWithText:nil
                          mediaAttachments:@[ attachment ]
                                  inThread:thread
                          quotedReplyModel:nil
                          linkPreviewDraft:nil
                               transaction:transaction];
    }];
}

+ (void)sendUnencryptedDatabase:(TSThread *)thread
{
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"sqlite"];
    NSString *fileName = filePath.lastPathComponent;

    NSError *error = [OWSPrimaryStorage.shared.newDatabaseConnection backupToPath:filePath];
    if (error != nil) {
        OWSFailDebug(@"Could not copy database file: %@.", error);
        return;
    }

    NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:fileName.pathExtension];
    _Nullable id<DataSource> dataSource = [DataSourcePath dataSourceWithFilePath:filePath
                                                      shouldDeleteOnDeallocation:YES
                                                                           error:&error];
    if (dataSource == nil) {
        OWSFailDebug(@"Could not create dataSource: %@.", error);
        return;
    }

    [dataSource setSourceFilename:fileName];
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType];
    [self sendAttachment:attachment thread:thread];
}

+ (void)shareAssets:(NSUInteger)count
   fromAssetLoaders:(NSArray<DebugUIMessagesAssetLoader *> *)assetLoaders
{
    [DebugUIMessagesAssetLoader prepareAssetLoaders:assetLoaders
                                            success:^{
                                                      [self shareAssets:count
                                               fromPreparedAssetLoaders:assetLoaders];
                                                      }
                                            failure:^{
                                                OWSLogError(@"Could not prepare asset loaders.");
                                                      }];
}

+ (void)shareAssets:(NSUInteger)count
   fromPreparedAssetLoaders:(NSArray<DebugUIMessagesAssetLoader *> *)assetLoaders
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
    [AttachmentSharing showShareUIForURLs:urls completion:^{
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

+ (void)populateRandomKeyValueStores:(NSUInteger)keyCount
{
    const NSUInteger kBatchSize = 1000;
    const NSUInteger batchCount = keyCount / kBatchSize;
    OWSLogVerbose(@"keyCount: %i", (int)keyCount);
    OWSLogVerbose(@"batchCount: %i", (int)batchCount);
    for (NSUInteger batchIndex = 0; batchIndex < batchCount; batchIndex++) {
        OWSLogVerbose(@"batchIndex: %i / %i", (int)batchIndex, (int)batchCount);

        @autoreleasepool {
            [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                SDSKeyValueStore *store = [OWSBlockingManager keyValueStore];

                // Set three values at a time.
                for (NSUInteger keyIndex = 0; keyIndex < kBatchSize; keyIndex += 3) {
                    NSData *value = [Randomness generateRandomBytes:4096];
                    [store setData:value key:NSUUID.UUID.UUIDString transaction:transaction];

                    [store setString:NSUUID.UUID.UUIDString key:NSUUID.UUID.UUIDString transaction:transaction];

                    [store setBool:true key:NSUUID.UUID.UUIDString transaction:transaction];
                }
            }];
        }
    }
}

+ (void)clearRandomKeyValueStores
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SDSKeyValueStore *store = [OWSBlockingManager keyValueStore];
        [store removeAllWithTransaction:transaction];
    }];
}

+ (void)saveOneOfEachModel
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        SignalServiceAddress *address1 = [[SignalServiceAddress alloc] initWithUuid:NSUUID.UUID phoneNumber:nil];
        SignalServiceAddress *address2 = [[SignalServiceAddress alloc] initWithUuid:NSUUID.UUID phoneNumber:nil];

        // TSThread
        TSContactThread *thread = [TSContactThread getOrCreateThreadWithContactAddress:address1
                                                                           transaction:transaction];
        // TSInteraction
        [[[TSIncomingMessage alloc] initIncomingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                            inThread:thread
                                                       authorAddress:address2
                                                      sourceDeviceId:0
                                                         messageBody:@"Exemplar"
                                                       attachmentIds:@[]
                                                    expiresInSeconds:0
                                                       quotedMessage:nil
                                                        contactShare:nil
                                                         linkPreview:nil
                                                      messageSticker:nil
                                                     serverTimestamp:nil
                                                     wasReceivedByUD:NO
                                                   isViewOnceMessage:NO] anyInsertWithTransaction:transaction];

        StickerPackInfo *stickerPackInfo =
            [[StickerPackInfo alloc] initWithPackId:[Randomness generateRandomBytes:16]
                                            packKey:[Randomness generateRandomBytes:(int)StickerManager.packKeyLength]];
        StickerInfo *stickerInfo = [[StickerInfo alloc] initWithPackId:stickerPackInfo.packId
                                                               packKey:stickerPackInfo.packKey
                                                             stickerId:0];
        // InstalledSticker
        [[[InstalledSticker alloc] initWithInfo:stickerInfo emojiString:nil] anyInsertWithTransaction:transaction];
        // StickerPack
        [[[StickerPack alloc] initWithInfo:stickerPackInfo
                                     title:@"some title"
                                    author:nil
                                     cover:[[StickerPackItem alloc] initWithStickerId:0 emojiString:@""]
                                  stickers:@[
                                      [[StickerPackItem alloc] initWithStickerId:1 emojiString:@""],
                                      [[StickerPackItem alloc] initWithStickerId:2 emojiString:@""],
                                  ]] anyInsertWithTransaction:transaction];
        // KnownStickerPack
        [[[KnownStickerPack alloc] initWithInfo:stickerPackInfo] anyInsertWithTransaction:transaction];
        // OWSMessageDecryptJob
        //
        // TODO: Generate real envelope data.
        [[[OWSMessageDecryptJob alloc] initWithEnvelopeData:[Randomness generateRandomBytes:16]]
            anyInsertWithTransaction:transaction];
        // TSRecipientReadReceipt
        [[[TSRecipientReadReceipt alloc] initWithSentTimestamp:[NSDate ows_millisecondTimeStamp]]
            anyInsertWithTransaction:transaction];
        // OWSMessageContentJob
        //
        // TODO: Generate real envelope data.
        [[[OWSMessageContentJob alloc] initWithEnvelopeData:[Randomness generateRandomBytes:16]
                                              plaintextData:nil
                                            wasReceivedByUD:NO] anyInsertWithTransaction:transaction];
        // TSAttachment
        [[[TSAttachmentPointer alloc] initWithServerId:12345
                                                   key:[Randomness generateRandomBytes:16]
                                                digest:nil
                                             byteCount:1024
                                           contentType:OWSMimeTypePdf
                                        sourceFilename:nil
                                               caption:nil
                                        albumMessageId:nil
                                        attachmentType:TSAttachmentTypeDefault
                                             mediaSize:CGSizeMake(1, 10)] anyInsertWithTransaction:transaction];
        [[[TSAttachmentStream alloc] initWithContentType:OWSMimeTypePdf
                                               byteCount:1024
                                          sourceFilename:nil
                                                 caption:nil
                                          albumMessageId:nil
                                         shouldAlwaysPad:YES] anyInsertWithTransaction:transaction];
        // ExperienceUpgrade
        //
        // We don't bother.

        // TestModel
        [[[TestModel alloc] init] anyInsertWithTransaction:transaction];
        // OWSUserProfile
        [[OWSUserProfile getOrBuildUserProfileForAddress:address1
                                             transaction:transaction] updateWithUsername:nil transaction:transaction];
        // OWSBackupFragment
        [[[OWSBackupFragment alloc] initWithUniqueId:@"some backup"] anyInsertWithTransaction:transaction];
        // OWSRecipientIdentity
        [[[OWSRecipientIdentity alloc] initWithAccountId:NSUUID.UUID.UUIDString
                                             identityKey:[Randomness generateRandomBytes:16]
                                         isFirstKnownKey:YES
                                               createdAt:[NSDate new]
                                       verificationState:OWSVerificationStateDefault]
            anyInsertWithTransaction:transaction];
        // SignalAccount
        [[[SignalAccount alloc] initWithSignalServiceAddress:address1] anyInsertWithTransaction:transaction];
        // OWSDisappearingMessagesConfiguration
        [[OWSDisappearingMessagesConfiguration fetchOrBuildDefaultWithThread:thread transaction:transaction]
            anyInsertWithTransaction:transaction];
        // SignalRecipient
        [[[SignalRecipient alloc] initWithAddress:address1] anyInsertWithTransaction:transaction];
        // OWSContactQuery
        [[[OWSContactQuery alloc] initWithUniqueId:NSUUID.UUID.UUIDString
                                       lastQueried:[NSDate new]
                                             nonce:[Randomness generateRandomBytes:16]]
            anyInsertWithTransaction:transaction];
        // OWSUnknownDBObject
        //
        // We don't bother.

        // OWSDevice
        [[[OWSDevice alloc] initWithUniqueId:NSUUID.UUID.UUIDString
                                   createdAt:[NSDate new]
                                    deviceId:1
                                  lastSeenAt:[NSDate new]
                                        name:nil] anyInsertWithTransaction:transaction];
        // OWSLinkedDeviceReadReceipt
        [[[OWSLinkedDeviceReadReceipt alloc] initWithSenderAddress:address1
                                                messageIdTimestamp:[NSDate ows_millisecondTimeStamp]
                                                     readTimestamp:[NSDate ows_millisecondTimeStamp]]
            anyInsertWithTransaction:transaction];

        // SSKJobRecord
        [[[SSKMessageDecryptJobRecord alloc] initWithEnvelopeData:[Randomness generateRandomBytes:16]
                                                            label:SSKMessageDecryptJobQueue.jobRecordLabel]
            anyInsertWithTransaction:transaction];
        NSError *_Nullable error;
        TSOutgoingMessage *queuedMessage =
            [[TSOutgoingMessage alloc] initOutgoingMessageWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                               inThread:thread
                                                            messageBody:@"some body"
                                                          attachmentIds:[NSMutableArray new]
                                                       expiresInSeconds:0
                                                        expireStartedAt:0
                                                         isVoiceMessage:NO
                                                       groupMetaMessage:TSGroupMetaMessageUnspecified
                                                          quotedMessage:nil
                                                           contactShare:nil
                                                            linkPreview:nil
                                                         messageSticker:nil
                                                      isViewOnceMessage:NO];
        [queuedMessage anyInsertWithTransaction:transaction];
        [[[SSKMessageSenderJobRecord alloc] initWithMessage:queuedMessage
                                  removeMessageAfterSending:NO
                                                      label:MessageSenderJobQueue.jobRecordLabel
                                                transaction:transaction
                                                      error:&error] anyInsertWithTransaction:transaction];
        OWSAssertDebug(error == nil);
        [[[OWSBroadcastMediaMessageJobRecord alloc]
            initWithAttachmentIdMap:[NSMutableDictionary new]
                              label:BroadcastMediaMessageJobQueue.jobRecordLabel] anyInsertWithTransaction:transaction];
        [[[OWSSessionResetJobRecord alloc] initWithContactThread:thread label:OWSSessionResetJobQueue.jobRecordLabel]
            anyInsertWithTransaction:transaction];
    }];
}

@end

NS_ASSUME_NONNULL_END

#endif
