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

@end

NS_ASSUME_NONNULL_END
