//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSReadReceiptsProcessor.h"
#import "OWSReadReceipt.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSIncomingMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSReadReceiptsProcessor ()

@property (nonatomic, readonly) NSArray<OWSReadReceipt *> *readReceipts;

@end

@implementation OWSReadReceiptsProcessor

- (instancetype)init
{
    return [self initWithReadReceiptProtos:@[]];
}

- (instancetype)initWithReadReceiptProtos:(NSArray<OWSSignalServiceProtosSyncMessageRead *> *)readReceiptProtos
{
    self = [super init];
    if (!self) {
        return self;
    }

    NSMutableArray<OWSReadReceipt *> *readReceipts = [NSMutableArray new];
    for (OWSSignalServiceProtosSyncMessageRead *readReceiptProto in readReceiptProtos) {
        OWSReadReceipt *readReceipt =
            [[OWSReadReceipt alloc] initWithSenderId:readReceiptProto.sender timestamp:readReceiptProto.timestamp];
        if (readReceipt.isValid) {
            [readReceipts addObject:readReceipt];
        } else {
            DDLogError(@"Received invalid read receipt: %@", readReceipt.validationErrorMessages);
        }
    }

    _readReceipts = [readReceipts copy];

    return self;
}

- (void)process
{
    DDLogInfo(@"Processing %ld read receipts.", self.readReceipts.count);
    for (OWSReadReceipt *readReceipt in self.readReceipts) {
        TSIncomingMessage *message =
            [TSIncomingMessage findMessageWithAuthorId:readReceipt.senderId timestamp:readReceipt.timestamp];
        if (message) {
            [message markAsRead];
        } else {
            DDLogWarn(@"Couldn't find message for read receipt. Message not synced?");
        }
    }
}

@end

NS_ASSUME_NONNULL_END
