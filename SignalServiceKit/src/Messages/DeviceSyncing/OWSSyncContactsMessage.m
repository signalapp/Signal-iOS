//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncContactsMessage.h"
#import "Contact.h"
#import "ContactsManagerProtocol.h"
#import "NSDate+OWS.h"
#import "OWSContactsOutputStream.h"
#import "OWSIdentityManager.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "SignalAccount.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncContactsMessage ()

@property (nonatomic, readonly) NSArray<SignalAccount *> *signalAccounts;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;
@property (nonatomic, readonly) id<ProfileManagerProtocol> profileManager;

@end

@implementation OWSSyncContactsMessage

- (instancetype)initWithSignalAccounts:(NSArray<SignalAccount *> *)signalAccounts
                       identityManager:(OWSIdentityManager *)identityManager
                        profileManager:(id<ProfileManagerProtocol>)profileManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _signalAccounts = signalAccounts;
    _identityManager = identityManager;
    _profileManager = profileManager;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    if (self.attachmentIds.count != 1) {
        OWSLogError(@"expected sync contact message to have exactly one attachment, but found %lu",
            (unsigned long)self.attachmentIds.count);
    }

    SSKProtoAttachmentPointer *_Nullable attachmentProto =
        [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject];
    if (!attachmentProto) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }

    SSKProtoSyncMessageContactsBuilder *contactsBuilder =
        [SSKProtoSyncMessageContactsBuilder new];
    [contactsBuilder setBlob:attachmentProto];
    [contactsBuilder setIsComplete:YES];

    NSError *error;
    SSKProtoSyncMessageContacts *_Nullable contactsProto = [contactsBuilder buildAndReturnError:&error];
    if (error || !contactsProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessageBuilder new];
    [syncMessageBuilder setContacts:contactsProto];
    return syncMessageBuilder;
}

- (nullable NSData *)buildPlainTextAttachmentDataWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    id<ContactsManagerProtocol> contactsManager = SSKEnvironment.shared.contactsManager;

    // TODO use temp file stream to avoid loading everything into memory at once
    // First though, we need to re-engineer our attachment process to accept streams (encrypting with stream,
    // and uploading with streams).
    NSOutputStream *dataOutputStream = [NSOutputStream outputStreamToMemory];
    [dataOutputStream open];
    OWSContactsOutputStream *contactsOutputStream =
        [[OWSContactsOutputStream alloc] initWithOutputStream:dataOutputStream];

    for (SignalAccount *signalAccount in self.signalAccounts) {
        OWSRecipientIdentity *_Nullable recipientIdentity =
            [self.identityManager recipientIdentityForRecipientId:signalAccount.recipientId];
        NSData *_Nullable profileKeyData = [self.profileManager profileKeyDataForRecipientId:signalAccount.recipientId];


        OWSDisappearingMessagesConfiguration *_Nullable disappearingMessagesConfiguration;
        NSString *conversationColorName;
        
        TSContactThread *_Nullable contactThread = [TSContactThread getThreadWithContactId:signalAccount.recipientId transaction:transaction];
        if (contactThread) {
            conversationColorName = contactThread.conversationColorName;
            disappearingMessagesConfiguration = [contactThread disappearingMessagesConfigurationWithTransaction:transaction];
        } else {
            conversationColorName = [TSThread stableColorNameForNewConversationWithString:signalAccount.recipientId];
        }

        [contactsOutputStream writeSignalAccount:signalAccount
                               recipientIdentity:recipientIdentity
                                  profileKeyData:profileKeyData
                                 contactsManager:contactsManager
                           conversationColorName:conversationColorName
               disappearingMessagesConfiguration:disappearingMessagesConfiguration];
    }

    [dataOutputStream close];

    if (contactsOutputStream.hasError) {
        OWSFailDebug(@"Could not write contacts sync stream.");
        return nil;
    }

    return [dataOutputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
}

@end

NS_ASSUME_NONNULL_END
