//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsSyncing.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSProfileManager.h"
#import <SignalServiceKit/DataSource.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/YapDatabaseConnection+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSPrimaryStorageOWSContactsSyncingCollection = @"kTSStorageManagerOWSContactsSyncingCollection";
NSString *const kOWSPrimaryStorageOWSContactsSyncingLastMessageKey
    = @"kTSStorageManagerOWSContactsSyncingLastMessageKey";

@interface OWSContactsSyncing ()

@property (nonatomic, readonly) dispatch_queue_t serialQueue;

@property (nonatomic) BOOL isRequestInFlight;

@end

@implementation OWSContactsSyncing

+ (instancetype)sharedManager
{
    OWSAssertDebug(Environment.shared.contactsSyncing);

    return Environment.shared.contactsSyncing;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileKeyDidChange:)
                                                 name:kNSNotificationName_ProfileKeyDidChange
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Dependencies

- (OWSContactsManager *)contactsManager {
    OWSAssertDebug(Environment.shared.contactsManager);

    return Environment.shared.contactsManager;
}

- (OWSIdentityManager *)identityManager {
    OWSAssertDebug(SSKEnvironment.shared.identityManager);

    return SSKEnvironment.shared.identityManager;
}

- (OWSMessageSender *)messageSender {
    OWSAssertDebug(SSKEnvironment.shared.messageSender);

    return SSKEnvironment.shared.messageSender;
}

- (OWSProfileManager *)profileManager {
    OWSAssertDebug(SSKEnvironment.shared.profileManager);

    return SSKEnvironment.shared.profileManager;
}

#pragma mark -

- (void)signalAccountsDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfPossible];
}

- (void)profileKeyDidChange:(id)notification {
    OWSAssertIsOnMainThread();

    [self sendSyncContactsMessageIfPossible];
}

- (YapDatabaseConnection *)editingDatabaseConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadWriteConnection;
}

#pragma mark - Methods

- (void)sendSyncContactsMessageIfNecessary
{
    OWSAssertIsOnMainThread();

    if (!self.serialQueue) {
        _serialQueue = dispatch_queue_create("org.whispersystems.contacts.syncing", DISPATCH_QUEUE_SERIAL);
    }

    dispatch_async(self.serialQueue, ^{

        if (self.isRequestInFlight) {
            // De-bounce.  It's okay if we ignore some new changes;
            // `sendSyncContactsMessageIfPossible` is called fairly
            // often so we'll sync soon.
            return;
        }

        OWSSyncContactsMessage *syncContactsMessage =
            [[OWSSyncContactsMessage alloc] initWithSignalAccounts:self.contactsManager.signalAccounts
                                                   identityManager:self.identityManager
                                                    profileManager:self.profileManager];

        __block NSData *_Nullable messageData;
        __block NSData *_Nullable lastMessageData;
        [self.editingDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            messageData = [syncContactsMessage buildPlainTextAttachmentDataWithTransaction:transaction];
            lastMessageData = [transaction objectForKey:kOWSPrimaryStorageOWSContactsSyncingLastMessageKey
                                           inCollection:kOWSPrimaryStorageOWSContactsSyncingCollection];
        }];

        if (!messageData) {
            OWSFailDebug(@"Failed to serialize contacts sync message.");
            return;
        }

        if (lastMessageData && [lastMessageData isEqual:messageData]) {
            // Ignore redundant contacts sync message.
            return;
        }

        self.isRequestInFlight = YES;

        DataSource *dataSource = [DataSourceValue dataSourceWithSyncMessageData:messageData];
        [self.messageSender enqueueTemporaryAttachment:dataSource
            contentType:OWSMimeTypeApplicationOctetStream
            inMessage:syncContactsMessage
            success:^{
                OWSLogInfo(@"Successfully sent contacts sync message.");

                [self.editingDatabaseConnection setObject:messageData
                                                   forKey:kOWSPrimaryStorageOWSContactsSyncingLastMessageKey
                                             inCollection:kOWSPrimaryStorageOWSContactsSyncingCollection];

                dispatch_async(self.serialQueue, ^{
                    self.isRequestInFlight = NO;
                });
            }
            failure:^(NSError *error) {
                OWSLogError(@"Failed to send contacts sync message with error: %@", error);

                dispatch_async(self.serialQueue, ^{
                    self.isRequestInFlight = NO;
                });
            }];
    });
}

- (void)sendSyncContactsMessageIfPossible
{
    OWSAssertIsOnMainThread();

    if (!self.contactsManager.isSetup) {
        // Don't bother if the contacts manager hasn't finished setup.
        return;
    }

    if ([TSAccountManager sharedInstance].isRegistered) {
        [self sendSyncContactsMessageIfNecessary];
    }
}

@end

NS_ASSUME_NONNULL_END
