//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Contacts/Contacts.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsManagerProtocol.h>
#import <SignalServiceKit/OWSContactsOutputStream.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/ProfileManagerProtocol.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSAttachment.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSContactThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncContactsMessage ()

@property (nonatomic, readonly) NSArray<SignalAccount *> *signalAccounts;

@end

@implementation OWSSyncContactsMessage

- (instancetype)initWithThread:(TSThread *)thread
                signalAccounts:(NSArray<SignalAccount *> *)signalAccounts
{
    self = [super initWithThread:thread];
    if (!self) {
        return self;
    }

    _signalAccounts = signalAccounts;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

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

        TSContactThread *_Nullable contactThread =
            [TSContactThread getThreadWithContactAddress:signalAccount.recipientAddress transaction:transaction];
        ThreadAssociatedData *associatedData = [ThreadAssociatedData fetchOrDefaultForThread:contactThread
                                                                               ignoreMissing:contactThread == nil
                                                                                 transaction:transaction];

        NSNumber *_Nullable isArchived;
        NSNumber *_Nullable inboxPosition;
        if (contactThread) {
            isArchived = [NSNumber numberWithBool:associatedData.isArchived];
            inboxPosition = [[AnyThreadFinder new] sortIndexObjcWithThread:contactThread transaction:transaction];
            disappearingMessagesConfiguration =
                [contactThread disappearingMessagesConfigurationWithTransaction:transaction];
        }

        [contactsOutputStream writeSignalAccount:signalAccount
                               recipientIdentity:recipientIdentity
                                  profileKeyData:profileKeyData
                                 contactsManager:self.contactsManager
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
