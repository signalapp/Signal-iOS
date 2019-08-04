//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSPerMessageExpirationReadSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSPerMessageExpirationReadSyncMessage

- (instancetype)initWithSenderId:(NSString *)senderId
              messageIdTimestamp:(uint64_t)messageIdTimestamp
                   readTimestamp:(uint64_t)readTimestamp
{
    OWSAssertDebug(senderId.length > 0 && messageIdTimestamp > 0);

    self = [super initWithTimestamp:readTimestamp];
    if (!self) {
        return self;
    }

    _senderId = senderId;
    _messageIdTimestamp = messageIdTimestamp;
    _readTimestamp = readTimestamp;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];

    SSKProtoSyncMessageMessageTimerReadBuilder *readProtoBuilder =
        [SSKProtoSyncMessageMessageTimerRead builderWithSender:self.senderId timestamp:self.messageIdTimestamp];
    NSError *error;
    SSKProtoSyncMessageMessageTimerRead *_Nullable readProto = [readProtoBuilder buildAndReturnError:&error];
    if (error || !readProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    [syncMessageBuilder setMessageTimerRead:readProto];

    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
