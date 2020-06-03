//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSViewOnceMessageReadSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSViewOnceMessageReadSyncMessage

- (instancetype)initWithThread:(TSThread *)thread
                 senderAddress:(SignalServiceAddress *)senderAddress
            messageIdTimestamp:(uint64_t)messageIdTimestamp
                 readTimestamp:(uint64_t)readTimestamp
{
    OWSAssertDebug(senderAddress.isValid && messageIdTimestamp > 0);

    self = [super initWithThread:thread];
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

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];

    SSKProtoSyncMessageViewOnceOpenBuilder *readProtoBuilder =
        [SSKProtoSyncMessageViewOnceOpen builderWithTimestamp:self.messageIdTimestamp];
    readProtoBuilder.senderE164 = self.senderAddress.phoneNumber;
    readProtoBuilder.senderUuid = self.senderAddress.uuidString;
    NSError *error;
    SSKProtoSyncMessageViewOnceOpen *_Nullable readProto = [readProtoBuilder buildAndReturnError:&error];
    if (error || !readProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    [syncMessageBuilder setViewOnceOpen:readProto];

    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
