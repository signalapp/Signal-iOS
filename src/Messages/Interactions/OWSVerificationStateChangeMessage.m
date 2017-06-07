//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationStateChangeMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSVerificationStateChangeMessage ()

@property (nonatomic, readonly) OWSVerificationState verificationState;
@property (nonatomic, readonly) BOOL isLocalChange;

@end

#pragma mark -

@implementation OWSVerificationStateChangeMessage

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                verificationState:(OWSVerificationState)verificationState
                    isLocalChange:(BOOL)isLocalChange
{
    self = [super initWithTimestamp:timestamp inThread:thread messageType:TSInfoMessageVerificationStateChange];
    if (!self) {
        return self;
    }

    _verificationState = verificationState;
    _isLocalChange = isLocalChange;

    return self;
}

- (NSString *)description
{
    switch (self.verificationState) {
        case OWSVerificationStateDefault:
        case OWSVerificationStateNoLongerVerified:
            return NSLocalizedString(@"VERIFICATION_STATE_CHANGE_NOT_VERIFIED",
                @"Info Message indicating that the verification state is not verified.");
        case OWSVerificationStateVerified:
            return NSLocalizedString(@"VERIFICATION_STATE_CHANGE_VERIFIED",
                @"Info Message indicating that the verification state is verified.");
    }
}

@end

NS_ASSUME_NONNULL_END
