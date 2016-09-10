//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSReadReceiptsProcessor.h"
#import "OWSReadReceipt.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSContactThread.h"
#import "TSIncomingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptsProcessor ()

@property (nonatomic, readonly) NSArray<OWSReadReceipt *> *readReceipts;

@end

@implementation OWSReadReceiptsProcessor

- (instancetype)initWithReadReceipts:(NSArray<OWSReadReceipt *> *)readReceipts
{
    self = [super init];
    if (!self) {
        return self;
    }

    _readReceipts = [readReceipts copy];

    return self;
}

- (instancetype)initWithReadReceiptProtos:(NSArray<OWSSignalServiceProtosSyncMessageRead *> *)readReceiptProtos
{
    NSMutableArray<OWSReadReceipt *> *readReceipts = [NSMutableArray new];
    for (OWSSignalServiceProtosSyncMessageRead *readReceiptProto in readReceiptProtos) {
        OWSReadReceipt *readReceipt =
            [[OWSReadReceipt alloc] initWithSenderId:readReceiptProto.sender timestamp:readReceiptProto.timestamp];
        if (readReceipt.isValid) {
            [readReceipts addObject:readReceipt];
        } else {
            DDLogError(@"%@ Received invalid read receipt: %@", self.tag, readReceipt.validationErrorMessages);
        }
    }

    return [self initWithReadReceipts:[readReceipts copy]];
}

- (instancetype)initWithIncomingMessage:(TSIncomingMessage *)message
{
    // Only groupthread sets authorId, thus this crappy code.
    // TODO ALL incoming messages should have an authorId.
    NSString *messageAuthorId;
    if (message.authorId) { // Group Thread
        messageAuthorId = message.authorId;
    } else { // Contact Thread
        messageAuthorId = [TSContactThread contactIdFromThreadId:message.uniqueThreadId];
    }

    OWSReadReceipt *readReceipt = [OWSReadReceipt firstWithSenderId:messageAuthorId timestamp:message.timestamp];
    if (readReceipt) {
        DDLogInfo(@"%@ Found prior read receipt for incoming message.", self.tag);
        return [self initWithReadReceipts:@[ readReceipt ]];
    } else {
        return [self initWithReadReceipts:@[]];
    }
}

- (void)process
{
    DDLogDebug(@"%@ Processing %ld read receipts.", self.tag, (unsigned long)self.readReceipts.count);
    for (OWSReadReceipt *readReceipt in self.readReceipts) {
        TSIncomingMessage *message =
            [TSIncomingMessage findMessageWithAuthorId:readReceipt.senderId timestamp:readReceipt.timestamp];
        if (message) {
            [message markAsReadFromReadReceipt];
            // If it was previously saved, no need to keep it around any longer.
            [readReceipt remove];
        } else {
            DDLogDebug(@"%@ Received read receipt for an unkown message. Saving it for later.", self.tag);
            [readReceipt save];
        }
    }
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
