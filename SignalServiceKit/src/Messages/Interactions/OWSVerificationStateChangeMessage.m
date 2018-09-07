//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationStateChangeMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSVerificationStateChangeMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      recipientId:(NSString *)recipientId
                verificationState:(OWSVerificationState)verificationState
                    isLocalChange:(BOOL)isLocalChange
{
    OWSAssertDebug(recipientId.length > 0);

    self = [super initWithTimestamp:timestamp inThread:thread messageType:TSInfoMessageVerificationStateChange];
    if (!self) {
        return self;
    }

    _recipientId = recipientId;
    _verificationState = verificationState;
    _isLocalChange = isLocalChange;

    return self;
}

@end

NS_ASSUME_NONNULL_END
