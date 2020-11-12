//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncContactsMessage.h"
#import "Contact.h"
#import "ContactsManagerProtocol.h"
#import "OWSContactsOutputStream.h"
#import "OWSIdentityManager.h"
#import "ProfileManagerProtocol.h"
#import "ProtoUtils.h"
#import "SSKEnvironment.h"
#import "SignalAccount.h"
#import "TSAccountManager.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import "OWSPrimaryStorage.h"

@import Contacts;

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

#pragma mark - Dependencies

- (id<ContactsManagerProtocol>)contactsManager {
    return SSKEnvironment.shared.contactsManager;
}

- (TSAccountManager *)tsAccountManager {
    return TSAccountManager.sharedInstance;
}

#pragma mark -

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    NSError *error;
    if (self.attachmentIds.count > 1) {
        OWSLogError(@"Expected sync contact message to have one or zero attachments, but found %lu.", (unsigned long)self.attachmentIds.count);
    }

    SSKProtoSyncMessageContactsBuilder *contactsBuilder;
    if (self.attachmentIds.count == 0) {
        SSKProtoAttachmentPointerBuilder *attachmentProtoBuilder = [SSKProtoAttachmentPointer builderWithId:0];
        SSKProtoAttachmentPointer *attachmentProto = [attachmentProtoBuilder buildAndReturnError:&error];
        contactsBuilder = [SSKProtoSyncMessageContacts builder];
        [contactsBuilder setBlob:attachmentProto];
        __block NSData *data;
        [OWSPrimaryStorage.sharedManager.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            data = [self buildPlainTextAttachmentDataWithTransaction:transaction];
        }];
        [contactsBuilder setData:data];
    } else {
        SSKProtoAttachmentPointer *attachmentProto = [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject];
        if (attachmentProto == nil) {
            OWSFailDebug(@"Couldn't build protobuf.");
            return nil;
        }
        contactsBuilder = [SSKProtoSyncMessageContacts builder];
        [contactsBuilder setBlob:attachmentProto];
    }
    [contactsBuilder setIsComplete:YES];
    
    SSKProtoSyncMessageContacts *contactsProto = [contactsBuilder buildAndReturnError:&error];
    if (error || contactsProto == nil) {
        OWSFailDebug(@"Couldn't build protobuf due to error: %@.", error);
        return nil;
    }
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setContacts:contactsProto];
    
    return syncMessageBuilder;
}

- (nullable NSData *)buildPlainTextAttachmentDataWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSMutableArray<SignalAccount *> *signalAccounts = [self.signalAccounts mutableCopy];

    // TODO use temp file stream to avoid loading everything into memory at once
    // First though, we need to re-engineer our attachment process to accept streams (encrypting with stream,
    // and uploading with streams).
    NSOutputStream *dataOutputStream = [NSOutputStream outputStreamToMemory];
    [dataOutputStream open];
    OWSContactsOutputStream *contactsOutputStream =
        [[OWSContactsOutputStream alloc] initWithOutputStream:dataOutputStream];

    for (SignalAccount *signalAccount in signalAccounts) {
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
                                 contactsManager:self.contactsManager
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
