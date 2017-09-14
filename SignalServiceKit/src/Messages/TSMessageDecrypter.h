//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosEnvelope;

typedef void (^DecryptSuccessBlock)(NSData *_Nullable plaintextData);
typedef void (^DecryptFailureBlock)();

@interface TSMessageDecrypter : TSMessagesHandler

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

// decryptEnvelope: can be called from any thread.
// successBlock & failureBlock may be called on any thread.
//
// Exactly one of successBlock & failureBlock will be called,
// once.
- (void)decryptEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
           successBlock:(DecryptSuccessBlock)successBlock
           failureBlock:(DecryptFailureBlock)failureBlock;

@end

NS_ASSUME_NONNULL_END
