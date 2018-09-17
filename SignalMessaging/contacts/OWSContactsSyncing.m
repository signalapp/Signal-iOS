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

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSProfileManager *profileManager;

@property (nonatomic) BOOL isRequestInFlight;

@end

@implementation OWSContactsSyncing

+ (instancetype)sharedManager
{
    static OWSContactsSyncing *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initDefault];
    });
    return instance;
}

- (instancetype)initDefault
{
    return [self initWithContactsManager:Environment.shared.contactsManager
                         identityManager:OWSIdentityManager.sharedManager
                           messageSender:SSKEnvironment.shared.messageSender
                          profileManager:OWSProfileManager.sharedManager];
}

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                        identityManager:(OWSIdentityManager *)identityManager
                          messageSender:(OWSMessageSender *)messageSender
                         profileManager:(OWSProfileManager *)profileManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertDebug(contactsManager);
    OWSAssertDebug(messageSender);
    OWSAssertDebug(identityManager);

    _contactsManager = contactsManager;
    _identityManager = identityManager;
    _messageSender = messageSender;
    _profileManager = profileManager;

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)signalAccountsDidChange:(id)notification
{
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
    if (self.contactsManager.signalAccounts.count == 0) {
        // Don't bother if the contacts manager has no contacts,
        // e.g. if the contacts manager hasn't finished setup.
        return;
    }

    if ([TSAccountManager sharedInstance].isRegistered) {
        [self sendSyncContactsMessageIfNecessary];
    }
}

@end

NS_ASSUME_NONNULL_END
