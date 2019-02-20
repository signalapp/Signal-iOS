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
#import <SignalMessaging/AttachmentSharing.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSPrimaryStorage+SessionStore.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/UIImage+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSStorage (DebugUI)

- (NSData *)databasePassword;

@end

#pragma mark -

@implementation DebugUIMisc

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
    [items addObject:[OWSTableItem itemWithTitle:@"Clear experience upgrades (works once per launch)"
                                     actionBlock:^{
                                         [ExperienceUpgrade removeAllObjectsInCollection];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Clear hasDismissedOffers"
                                     actionBlock:^{
                                         [DebugUIMisc clearHasDismissedOffers];
                                     }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Delete disappearing messages config"
                                     actionBlock:^{
                                         [[OWSPrimaryStorage sharedManager].newDatabaseConnection readWriteWithBlock:^(
                                             YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                                             OWSDisappearingMessagesConfiguration *config =
                                                 [OWSDisappearingMessagesConfiguration
                                                     fetchOrBuildDefaultWithThreadId:thread.uniqueId
                                                                         transaction:transaction];
                                             [config removeWithTransaction:transaction];
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
                                         OWSNavigationController *navController =
                                             [OWS2FAReminderViewController wrappedInNavController];
                                         [[[UIApplication sharedApplication] frontmostViewController]
                                             presentViewController:navController
                                                          animated:YES
                                                        completion:nil];
                                     }]];

    [items addObject:[OWSTableItem itemWithTitle:@"Reset 2FA Repetition Interval"
                                     actionBlock:^() {
                                         [OWS2FAManager.sharedManager setDefaultRepetitionInterval];
                                     }]];

#ifdef DEBUG
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
#endif

    [items
        addObject:[OWSTableItem
                      itemWithTitle:@"Increment Database Extension Versions"
                        actionBlock:^() {
                            for (NSString *extensionName in OWSPrimaryStorage.sharedManager.registeredExtensionNames) {
                                [OWSStorage incrementVersionOfDatabaseExtension:extensionName];
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
    [OWSPrimaryStorage.dbReadWriteConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            NSMutableArray<TSContactThread *> *contactThreads = [NSMutableArray new];
            [transaction
                enumerateKeysAndObjectsInCollection:[TSThread collection]
                                         usingBlock:^(NSString *_Nonnull key, id _Nonnull object, BOOL *_Nonnull stop) {
                                             TSThread *thread = object;
                                             if (thread.isGroupThread) {
                                                 return;
                                             }
                                             TSContactThread *contactThread = object;
                                             [contactThreads addObject:contactThread];
                                         }];
            for (TSContactThread *contactThread in contactThreads) {
                if (contactThread.hasDismissedOffers) {
                    contactThread.hasDismissedOffers = NO;
                    [contactThread saveWithTransaction:transaction];
                }
            }
        }];
}

+ (void)sendEncryptedDatabase:(TSThread *)thread
{
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"sqlite"];
    NSString *fileName = filePath.lastPathComponent;

    __block BOOL success;
    [OWSPrimaryStorage.sharedManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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
    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithFilePath:filePath shouldDeleteOnDeallocation:YES];
    [dataSource setSourceFilename:fileName];
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType];
    NSData *databasePassword = [OWSPrimaryStorage.sharedManager databasePassword];
    attachment.captionText = [databasePassword hexadecimalString];
    if (!attachment || [attachment hasError]) {
        OWSFailDebug(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
        return;
    }
    [ThreadUtil enqueueMessageWithAttachment:attachment inThread:thread quotedReplyModel:nil];
}

+ (void)sendUnencryptedDatabase:(TSThread *)thread
{
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"sqlite"];
    NSString *fileName = filePath.lastPathComponent;

    NSError *error = [OWSPrimaryStorage.sharedManager.newDatabaseConnection backupToPath:filePath];
    if (error) {
        OWSFailDebug(@"Could not copy database file: %@.", error);
        return;
    }

    NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:fileName.pathExtension];
    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithFilePath:filePath shouldDeleteOnDeallocation:YES];
    [dataSource setSourceFilename:fileName];
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType];
    if (!attachment || [attachment hasError]) {
        OWSFailDebug(@"attachment[%@]: %@", [attachment sourceFilename], [attachment errorName]);
        return;
    }
    [ThreadUtil enqueueMessageWithAttachment:attachment inThread:thread quotedReplyModel:nil];
}

#ifdef DEBUG

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

#endif

@end

NS_ASSUME_NONNULL_END
