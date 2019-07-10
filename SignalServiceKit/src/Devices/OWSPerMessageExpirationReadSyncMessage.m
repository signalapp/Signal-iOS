//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSPerMessageExpirationReadSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSPerMessageExpirationReadSyncMessage

- (instancetype)initWithSenderAddress:(SignalServiceAddress *)senderAddress
                   messageIdTimestamp:(uint64_t)messageIdTimestamp
                        readTimestamp:(uint64_t)readTimestamp
{
    OWSAssertDebug(senderAddress.isValid && messageIdTimestamp > 0);

    self = [super initWithTimestamp:readTimestamp];
    if (!self) {
        return self;
    }

    _senderAddress = senderAddress;
    _messageIdTimestamp = messageIdTimestamp;
    _readTimestamp = readTimestamp;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_senderAddress == nil) {
        _senderAddress = [[SignalServiceAddress alloc] initWithPhoneNumber:[coder decodeObjectForKey:@"senderId"]];
        OWSAssertDebug(_senderAddress.isValid);
    }

    return self;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];

    SSKProtoSyncMessageMessageTimerReadBuilder *readProtoBuilder =
        [SSKProtoSyncMessageMessageTimerRead builderWithTimestamp:self.messageIdTimestamp];
    readProtoBuilder.senderE164 = self.senderAddress.phoneNumber;
    readProtoBuilder.senderUuid = self.senderAddress.uuidString;
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
