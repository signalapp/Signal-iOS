//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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

@implementation OWSSyncContactsMessage

- (instancetype)initWithThread:(TSThread *)thread
                signalAccounts:(NSArray<SignalAccount *> *)signalAccounts
                    isFullSync:(BOOL)isFullSync
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _signalAccounts = signalAccounts;
    _isFullSync = isFullSync;

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
    [contactsBuilder setIsComplete:self.isFullSync];

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

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
