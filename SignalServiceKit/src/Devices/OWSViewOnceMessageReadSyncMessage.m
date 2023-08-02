//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSViewOnceMessageReadSyncMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewOnceMessageReadSyncMessage ()
@property (nonatomic, readonly, nullable) NSString *messageUniqueId; // Only nil if decoding old values
@end

@implementation OWSViewOnceMessageReadSyncMessage

- (instancetype)initWithThread:(TSThread *)thread
                 senderAddress:(SignalServiceAddress *)senderAddress
                       message:(TSMessage *)message
                 readTimestamp:(uint64_t)readTimestamp
                   transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(senderAddress.isValid && message.timestamp > 0);

    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _senderAddress = senderAddress;
    _messageUniqueId = message.uniqueId;
    _messageIdTimestamp = message.timestamp;
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

- (BOOL)isUrgent
{
    return NO;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];

    SSKProtoSyncMessageViewOnceOpenBuilder *readProtoBuilder =
        [SSKProtoSyncMessageViewOnceOpen builderWithTimestamp:self.messageIdTimestamp];
    readProtoBuilder.senderAci = self.senderAddress.aciString;
    NSError *error;
    SSKProtoSyncMessageViewOnceOpen *_Nullable readProto = [readProtoBuilder buildAndReturnError:&error];
    if (error || !readProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    [syncMessageBuilder setViewOnceOpen:readProto];

    return syncMessageBuilder;
}

- (NSSet<NSString *> *)relatedUniqueIds
{
    if (self.messageUniqueId) {
        return [[super relatedUniqueIds] setByAddingObject:self.messageUniqueId];
    } else {
        return [super relatedUniqueIds];
    }
}

@end

NS_ASSUME_NONNULL_END
