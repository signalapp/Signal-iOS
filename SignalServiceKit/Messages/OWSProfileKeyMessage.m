//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSProfileKeyMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSProfileKeyMessage ()
@property (nonatomic, readonly, nullable) NSData *profileKey;
@end

@implementation OWSProfileKeyMessage

- (instancetype)initWithThread:(TSThread *)thread
                    profileKey:(NSData *)profileKey
                   transaction:(DBReadTransaction *)transaction
{
    TSOutgoingMessageBuilder *messageBuilder = [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:thread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (self) {
        _profileKey = [profileKey copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    NSData *profileKey = self.profileKey;
    if (profileKey != nil) {
        [coder encodeObject:profileKey forKey:@"profileKey"];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }
    self->_profileKey = [coder decodeObjectOfClass:[NSData class] forKey:@"profileKey"];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.profileKey.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSProfileKeyMessage *typedOther = (OWSProfileKeyMessage *)other;
    if (![NSObject isObject:self.profileKey equalToObject:typedOther.profileKey]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    OWSProfileKeyMessage *result = [super copyWithZone:zone];
    result->_profileKey = self.profileKey;
    return result;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)shouldSyncTranscript
{
    return NO;
}

- (nullable SSKProtoDataMessage *)buildDataMessage:(TSThread *)thread transaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug(thread != nil);

    SSKProtoDataMessageBuilder *_Nullable builder = [self dataMessageBuilderWithThread:thread transaction:transaction];
    if (!builder) {
        OWSFailDebug(@"could not build protobuf.");
        return nil;
    }
    [builder setTimestamp:self.timestamp];
    [ProtoUtils addLocalProfileKeyIfNecessaryForThread:thread
                                    profileKeySnapshot:self.profileKey
                                    dataMessageBuilder:builder
                                           transaction:transaction];
    [builder setFlags:SSKProtoDataMessageFlagsProfileKeyUpdate];

    NSError *error;
    SSKProtoDataMessage *_Nullable dataProto = [builder buildAndReturnError:&error];
    if (error || !dataProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }
    if (dataProto.profileKey == nil) {
        // If we couldn't include the profile key, drop it.
        OWSLogWarn(@"Dropping profile key message without a profile key.");
        return nil;
    }
    return dataProto;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

@end

NS_ASSUME_NONNULL_END
