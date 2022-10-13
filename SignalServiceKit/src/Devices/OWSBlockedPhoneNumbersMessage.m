//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSBlockedPhoneNumbersMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBlockedPhoneNumbersMessage ()

@property (nonatomic, readonly) NSArray<NSString *> *phoneNumbers;
@property (nonatomic, readonly) NSArray<NSString *> *uuids;
@property (nonatomic, readonly) NSArray<NSData *> *groupIds;

@end

@implementation OWSBlockedPhoneNumbersMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithThread:(TSThread *)thread
                  phoneNumbers:(NSArray<NSString *> *)phoneNumbers
                         uuids:(NSArray<NSString *> *)uuids
                      groupIds:(NSArray<NSData *> *)groupIds
                   transaction:(SDSAnyReadTransaction *)transaction
{
    self = [super initWithThread:thread transaction:transaction];
    if (!self) {
        return self;
    }

    _phoneNumbers = [phoneNumbers copy];
    _uuids = [uuids copy];
    _groupIds = [groupIds copy];

    return self;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    SSKProtoSyncMessageBlockedBuilder *blockedBuilder = [SSKProtoSyncMessageBlocked builder];
    [blockedBuilder setNumbers:_phoneNumbers];
    [blockedBuilder setUuids:_uuids];
    [blockedBuilder setGroupIds:_groupIds];

    NSError *error;
    SSKProtoSyncMessageBlocked *_Nullable blockedProto = [blockedBuilder buildAndReturnError:&error];
    if (error || !blockedProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessage builder];
    [syncMessageBuilder setBlocked:blockedProto];
    return syncMessageBuilder;
}

- (BOOL)isUrgent
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
