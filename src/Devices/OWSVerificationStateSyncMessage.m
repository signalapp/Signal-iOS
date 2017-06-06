//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationStateSyncMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSVerificationStateSyncMessage ()

@property (nonatomic, readonly) OWSVerificationState verificationState;
@property (nonatomic, readonly) NSData *identityKey;
@property (nonatomic, readonly) NSString *recipientId;

@end

#pragma mark -

@implementation OWSVerificationStateSyncMessage

- (instancetype)initWithVerificationState:(OWSVerificationState)verificationState
                              identityKey:(NSData *)identityKey
                              recipientId:(NSString *)recipientId
{
    OWSAssert(identityKey.length > 0);
    OWSAssert(recipientId.length > 0);

    self = [super init];
    if (!self) {
        return self;
    }

    _verificationState = verificationState;
    _identityKey = identityKey;
    _recipientId = recipientId;

    return self;
}

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    // TODO:
    //    OWSSignalServiceProtosSyncMessageBlockedBuilder *blockedPhoneNumbersBuilder =
    //        [OWSSignalServiceProtosSyncMessageBlockedBuilder new];
    //    [blockedPhoneNumbersBuilder setNumbersArray:_phoneNumbers];
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    //    [syncMessageBuilder setBlocked:[blockedPhoneNumbersBuilder build]];

    return [syncMessageBuilder build];
}

@end

NS_ASSUME_NONNULL_END
