//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncContactsMessage.h"
#import "Contact.h"
#import "ContactsManagerProtocol.h"
#import "OWSContactsOutputStream.h"
#import "OWSIdentityManager.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "SignalAccount.h"
#import "TSAccountManager.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSContactThread.h"
#import <Contacts/Contacts.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncContactsMessage ()

@property (nonatomic, readonly) NSArray<SignalAccount *> *signalAccounts;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;
@property (nonatomic, readonly) id<ProfileManagerProtocol> profileManager;

@end

@implementation OWSSyncContactsMessage

- (instancetype)initWithThread:(TSThread *)thread
                signalAccounts:(NSArray<SignalAccount *> *)signalAccounts
               identityManager:(OWSIdentityManager *)identityManager
                profileManager:(id<ProfileManagerProtocol>)profileManager
{
    self = [super initWithThread:thread];
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
    return TSAccountManager.shared;
}

#pragma mark -

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (self.attachmentIds.count != 1) {
        OWSLogError(@"expected sync contact message to have exactly one attachment, but found %lu",
            (unsigned long)self.attachmentIds.count);
    }

    SSKProtoAttachmentPointer *_Nullable attachmentProto =
        [TSAttachmentStream buildProtoForAttachmentId:self.attachmentIds.firstObject transaction:transaction];
    if (!attachmentProto) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }

    SSKProtoSyncMessageContactsBuilder *contactsBuilder = [SSKProtoSyncMessageContacts builderWithBlob:attachmentProto];
    [contactsBuilder setIsComplete:YES];

    NSError *error;
    SSKProtoSyncMessageContacts *_Nullable contactsProto = [contactsBuilder buildAndReturnError:&error];
    if (error || !contactsProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setContacts:contactsProto];
    return syncMessageBuilder;
}

- (nullable NSData *)buildPlainTextAttachmentDataWithTransaction:(SDSAnyReadTransaction *)transaction
{
    NSMutableArray<SignalAccount *> *signalAccounts = [self.signalAccounts mutableCopy];

    SignalServiceAddress *_Nullable localAddress = [TSAccountManager localAddressWithTransaction:transaction];
    OWSAssertDebug(localAddress.isValid);
    if (localAddress) {
        BOOL hasLocalAddress = NO;
        for (SignalAccount *signalAccount in signalAccounts) {
            hasLocalAddress |= signalAccount.recipientAddress.isLocalAddress;
        }
        if (!hasLocalAddress) {
            // OWSContactsOutputStream requires all signalAccount to have a contact.
            Contact *contact = [[Contact alloc] initWithSystemContact:[CNContact new]];
            SignalAccount *signalAccount = [[SignalAccount alloc] initWithSignalServiceAddress:localAddress
                                                                                       contact:contact
                                                                      multipleAccountLabelText:nil];
            [signalAccounts addObject:signalAccount];
        }
    }

    // TODO use temp file stream to avoid loading everything into memory at once
    // First though, we need to re-engineer our attachment process to accept streams (encrypting with stream,
    // and uploading with streams).
    NSOutputStream *dataOutputStream = [NSOutputStream outputStreamToMemory];
    [dataOutputStream open];
    OWSContactsOutputStream *contactsOutputStream =
        [[OWSContactsOutputStream alloc] initWithOutputStream:dataOutputStream];

    for (SignalAccount *signalAccount in signalAccounts) {
        OWSRecipientIdentity *_Nullable recipientIdentity =
            [self.identityManager recipientIdentityForAddress:signalAccount.recipientAddress transaction:transaction];
        NSData *_Nullable profileKeyData =
            [self.profileManager profileKeyDataForAddress:signalAccount.recipientAddress transaction:transaction];

        OWSDisappearingMessagesConfiguration *_Nullable disappearingMessagesConfiguration;
        NSString *conversationColorName;

        TSContactThread *_Nullable contactThread =
            [TSContactThread getThreadWithContactAddress:signalAccount.recipientAddress transaction:transaction];

        NSNumber *_Nullable isArchived;
        NSNumber *_Nullable inboxPosition;
        if (contactThread) {
            isArchived = [NSNumber numberWithBool:contactThread.isArchived];
            inboxPosition = [[AnyThreadFinder new] sortIndexObjcWithThread:contactThread transaction:transaction];
            conversationColorName = contactThread.conversationColorName;
            disappearingMessagesConfiguration =
                [contactThread disappearingMessagesConfigurationWithTransaction:transaction];
        } else {
            conversationColorName =
                [TSThread stableColorNameForNewConversationWithString:signalAccount.recipientAddress.stringForDisplay];
        }

        [contactsOutputStream writeSignalAccount:signalAccount
                               recipientIdentity:recipientIdentity
                                  profileKeyData:profileKeyData
                                 contactsManager:self.contactsManager
                           conversationColorName:conversationColorName
               disappearingMessagesConfiguration:disappearingMessagesConfiguration
                                      isArchived:isArchived
                                   inboxPosition:inboxPosition];
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
