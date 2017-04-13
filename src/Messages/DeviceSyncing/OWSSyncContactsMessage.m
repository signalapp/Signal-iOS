//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSyncContactsMessage.h"
#import "Contact.h"
#import "ContactsManagerProtocol.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSContactsOutputStream.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncContactsMessage ()

@property (nonatomic, readonly) id<ContactsManagerProtocol> contactsManager;

@end

@implementation OWSSyncContactsMessage

- (instancetype)initWithContactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    self = [super initWithTimestamp:[NSDate ows_millisecondTimeStamp]];
    if (!self) {
        return self;
    }

    _contactsManager = contactsManager;

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

    for (Contact *contact in self.contactsManager.signalContacts) {
        [contactsOutputStream writeContact:contact];
    }

    [contactsOutputStream flush];
    [dataOutputStream close];

    return [dataOutputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
}

@end

NS_ASSUME_NONNULL_END
