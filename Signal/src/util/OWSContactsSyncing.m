//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSContactsSyncing.h"
#import "OWSContactsManager.h"
#import "TSAccountManager.h"
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kTSStorageManagerOWSContactsSyncingCollection = @"kTSStorageManagerOWSContactsSyncingCollection";
NSString *const kTSStorageManagerOWSContactsSyncingLastMessageKey =
    @"kTSStorageManagerOWSContactsSyncingLastMessageKey";

@interface OWSContactsSyncing ()

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic) BOOL isRequestInFlight;

@end

@implementation OWSContactsSyncing

- (instancetype)initWithContactsManager:(OWSContactsManager *)contactsManager
                          messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(contactsManager);
    OWSAssert(messageSender);

    _contactsManager = contactsManager;
    _messageSender = messageSender;

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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self sendSyncContactsMessageIfPossible];
    });
}

#pragma mark - Methods

- (void)sendSyncContactsMessageIfNecessary
{
    AssertIsOnMainThread();

    if (self.isRequestInFlight) {
        // De-bounce.  It's okay if we ignore some new changes;
        // `sendSyncContactsMessageIfPossible` is called fairly
        // often so we'll sync soon.
        return;
    }

    OWSSyncContactsMessage *syncContactsMessage =
        [[OWSSyncContactsMessage alloc] initWithContactsManager:self.contactsManager];

    NSData *messageData = [syncContactsMessage buildPlainTextAttachmentData];

    NSData *lastMessageData =
        [[TSStorageManager sharedManager] objectForKey:kTSStorageManagerOWSContactsSyncingLastMessageKey
                                          inCollection:kTSStorageManagerOWSContactsSyncingCollection];

    if (lastMessageData && [lastMessageData isEqual:messageData]) {
        // Ignore redundant contacts sync message.
        return;
    }

    self.isRequestInFlight = YES;

    [self.messageSender sendTemporaryAttachmentData:[syncContactsMessage buildPlainTextAttachmentData]
        contentType:OWSMimeTypeApplicationOctetStream
        inMessage:syncContactsMessage
        success:^{
            DDLogInfo(@"%@ Successfully sent contacts sync message.", self.tag);

            [[TSStorageManager sharedManager] setObject:messageData
                                                 forKey:kTSStorageManagerOWSContactsSyncingLastMessageKey
                                           inCollection:kTSStorageManagerOWSContactsSyncingCollection];

            dispatch_async(dispatch_get_main_queue(), ^{
                self.isRequestInFlight = NO;
            });
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Failed to send contacts sync message with error: %@", self.tag, error);

            dispatch_async(dispatch_get_main_queue(), ^{
                self.isRequestInFlight = NO;
            });
        }];
}

- (void)sendSyncContactsMessageIfPossible
{
    AssertIsOnMainThread();

    if (![self.contactsManager hasAddressBook]) {
        // Don't bother until the contacts manager has finished setup.
        return;
    }

    [[TSAccountManager sharedInstance] ifRegistered:YES
                                           runAsync:^{
                                               dispatch_async(dispatch_get_main_queue(), ^{
                                                   [self sendSyncContactsMessageIfNecessary];
                                               });
                                           }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
