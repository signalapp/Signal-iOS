//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBlockedPhoneNumbersMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBlockedPhoneNumbersMessage ()

@property (nonatomic, readonly) NSArray<NSString *> *phoneNumbers;
@property (nonatomic, readonly) NSArray<NSData *> *groupIds;

@end

@implementation OWSBlockedPhoneNumbersMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithPhoneNumbers:(NSArray<NSString *> *)phoneNumbers groupIds:(NSArray<NSData *> *)groupIds
{
    self = [super init];
    if (!self) {
        return self;
    }

    _phoneNumbers = [phoneNumbers copy];
    _groupIds = [groupIds copy];

    return self;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageBlockedBuilder *blockedBuilder = [SSKProtoSyncMessageBlockedBuilder new];
    [blockedBuilder setNumbers:_phoneNumbers];
    [blockedBuilder setGroupIds:_groupIds];

    NSError *error;
    SSKProtoSyncMessageBlocked *_Nullable blockedProto = [blockedBuilder buildAndReturnError:&error];
    if (error || !blockedProto) {
        OWSFailDebug(@"could not build protobuf: %@", error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessageBuilder new];
    [syncMessageBuilder setBlocked:blockedProto];
    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
