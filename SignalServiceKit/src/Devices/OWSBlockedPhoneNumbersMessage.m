//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBlockedPhoneNumbersMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBlockedPhoneNumbersMessage ()

@property (nonatomic, readonly) NSArray<NSString *> *phoneNumbers;

@end

@implementation OWSBlockedPhoneNumbersMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (instancetype)initWithPhoneNumbers:(NSArray<NSString *> *)phoneNumbers
{
    self = [super init];
    if (!self) {
        return self;
    }

    _phoneNumbers = [phoneNumbers copy];

    return self;
}

- (nullable SSKProtoSyncMessageBuilder *)syncMessageBuilder
{
    SSKProtoSyncMessageBlockedBuilder *blockedBuilder = [SSKProtoSyncMessageBlockedBuilder new];
    [blockedBuilder setNumbers:_phoneNumbers];
    NSError *error;
    SSKProtoSyncMessageBlocked *_Nullable blockedProto = [blockedBuilder buildAndReturnError:&error];
    if (error || !blockedProto) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }

    SSKProtoSyncMessageBuilder *syncMessageBuilder = [SSKProtoSyncMessageBuilder new];
    [syncMessageBuilder setBlocked:blockedProto];
    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
