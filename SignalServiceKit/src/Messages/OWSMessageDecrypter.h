//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosEnvelope;

typedef void (^DecryptSuccessBlock)(NSData *_Nullable plaintextData);
typedef void (^DecryptFailureBlock)();

@interface OWSMessageDecrypter : OWSMessageHandler

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

// decryptEnvelope: can be called from any thread.
// successBlock & failureBlock will be called an arbitrary thread.
//
// Exactly one of successBlock & failureBlock will be called,
// once.
- (void)decryptEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
           successBlock:(DecryptSuccessBlock)successBlock
           failureBlock:(DecryptFailureBlock)failureBlock;

@end

NS_ASSUME_NONNULL_END
