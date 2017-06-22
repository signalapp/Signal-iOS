//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncContactsMessage.h"
#import "Contact.h"
#import "ContactsManagerProtocol.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSContactsOutputStream.h"
#import "OWSSignalServiceProtos.pb.h"
#import "OWSIdentityManager.h"
#import "SignalAccount.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncContactsMessage ()

@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;

@end

@implementation OWSSyncContactsMessage

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
                        identityManager:(OWSIdentityManager *)identityManager
{
    self = [super initWithTimestamp:[NSDate ows_millisecondTimeStamp]];
    if (!self) {
        return self;
    }

    _contactsManager = contactsManager;
    _identityManager = identityManager;

    return self;
}

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    if (self.attachmentIds.count != 1) {
        DDLogError(@"expected sync contact message to have exactly one attachment, but found %lu",
            (unsigned long)self.attachmentIds.count);
    }

    OWSSignalServiceProtosAttachmentPointer *attachmentProto =
        [self buildAttachmentProtoForAttachmentId:self.attachmentIds[0] filename:nil];

    OWSSignalServiceProtosSyncMessageContactsBuilder *contactsBuilder =
        [OWSSignalServiceProtosSyncMessageContactsBuilder new];

    [contactsBuilder setBlob:attachmentProto];
    [contactsBuilder setIsComplete:YES];

    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    [syncMessageBuilder setContactsBuilder:contactsBuilder];

    return [syncMessageBuilder build];
}

- (NSData *)buildPlainTextAttachmentData
{
    // TODO use temp file stream to avoid loading everything into memory at once
    // First though, we need to re-engineer our attachment process to accept streams (encrypting with stream,
    // and uploading with streams).
    NSOutputStream *dataOutputStream = [NSOutputStream outputStreamToMemory];
    [dataOutputStream open];
    OWSContactsOutputStream *contactsOutputStream = [OWSContactsOutputStream streamWithOutputStream:dataOutputStream];

    for (SignalAccount *signalAccount in self.contactsManager.signalAccounts) {
        OWSRecipientIdentity *recipientIdentity = [self.identityManager recipientIdentityForRecipientId:signalAccount.recipientId];
        
        [contactsOutputStream writeSignalAccount:signalAccount recipientIdentity:recipientIdentity];
    }

    [contactsOutputStream flush];
    [dataOutputStream close];

    return [dataOutputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
}

@end

NS_ASSUME_NONNULL_END
