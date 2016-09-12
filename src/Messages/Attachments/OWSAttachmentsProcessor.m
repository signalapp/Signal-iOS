//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSAttachmentsProcessor.h"
#import "MIMETypeUtil.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSAttachmentPointer.h"
#import "TSInfoMessage.h"
#import "TSMessage.h"
#import "TSMessagesManager+attachments.h"
#import "TSMessagesManager.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSAttachmentsProcessor ()

@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property (nonatomic, readonly) NSArray<TSAttachmentPointer *> *supportedAttachmentPointers;

@end

@implementation OWSAttachmentsProcessor

- (instancetype)initWithAttachmentPointersProtos:(NSArray<OWSSignalServiceProtosAttachmentPointer *> *)attachmentProtos
                                       timestamp:(uint64_t)timestamp
                                           relay:(nullable NSString *)relay
                                   avatarGroupId:(nullable NSData *)avatarGroupId
                                        inThread:(TSThread *)thread
                                 messagesManager:(TSMessagesManager *)messagesManager;
{
    self = [super init];
    if (!self) {
        return self;
    }

    _messagesManager = messagesManager;

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];
    NSMutableArray<TSAttachmentPointer *> *supportedAttachmentPointers = [NSMutableArray new];
    NSMutableArray<NSString *> *supportedAttachmentIds = [NSMutableArray new];

    for (OWSSignalServiceProtosAttachmentPointer *attachmentProto in attachmentProtos) {
        TSAttachmentPointer *pointer;
        if (avatarGroupId) {
            pointer = [[TSAttachmentPointer alloc] initWithIdentifier:attachmentProto.id
                                                                  key:attachmentProto.key
                                                          contentType:attachmentProto.contentType
                                                                relay:relay
                                                      avatarOfGroupId:avatarGroupId];
        } else {
            pointer = [[TSAttachmentPointer alloc] initWithIdentifier:attachmentProto.id
                                                                  key:attachmentProto.key
                                                          contentType:attachmentProto.contentType
                                                                relay:relay];
        }

        [attachmentIds addObject:pointer.uniqueId];

        if ([MIMETypeUtil isSupportedMIMEType:pointer.contentType]) {
            [pointer save];
            [supportedAttachmentPointers addObject:pointer];
            [supportedAttachmentIds addObject:pointer.uniqueId];
        } else {
            DDLogError(@"%@ Received unsupported attachment of type: %@", self.tag, pointer.contentType);
            TSInfoMessage *infoMessage = [[TSInfoMessage alloc] initWithTimestamp:timestamp
                                                                         inThread:thread
                                                                      messageType:TSInfoMessageTypeUnsupportedMessage];
            [infoMessage save];
        }
    }

    _attachmentIds = [attachmentIds copy];
    _supportedAttachmentPointers = [supportedAttachmentPointers copy];
    _supportedAttachmentIds = [supportedAttachmentIds copy];

    return self;
}

- (void)fetchAttachmentsForMessageId:(nullable NSString *)messageId
{
    for (TSAttachmentPointer *attachmentPointer in self.supportedAttachmentPointers) {
        [self.messagesManager retrieveAttachment:attachmentPointer messageId:messageId];
    }
}

- (BOOL)hasSupportedAttachments
{
    return self.supportedAttachmentPointers.count > 0;
}

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
