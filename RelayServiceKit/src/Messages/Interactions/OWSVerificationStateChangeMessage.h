//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSRecipientIdentity.h"
#import "TSInfoMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSVerificationStateChangeMessage : TSInfoMessage

@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) OWSVerificationState verificationState;
@property (nonatomic, readonly) BOOL isLocalChange;

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      recipientId:(NSString *)recipientId
                verificationState:(OWSVerificationState)verificationState
                    isLocalChange:(BOOL)isLocalChange;

@end

NS_ASSUME_NONNULL_END
