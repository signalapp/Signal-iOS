//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"
#import "OWSRecipientIdentity.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSVerificationStateSyncMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithVerificationState:(OWSVerificationState)verificationState
                              identityKey:(NSData *)identityKey
               verificationForRecipientId:(NSString *)recipientId NS_DESIGNATED_INITIALIZER;

// This is a clunky name, but we want to differentiate it from `recipientIdentifier` inherited from `TSOutgoingMessage`
@property (nonatomic, readonly) NSString *verificationForRecipientId;

@property (nonatomic, readonly) size_t paddingBytesLength;
@property (nonatomic, readonly) size_t unpaddedVerifiedLength;

@end

NS_ASSUME_NONNULL_END
