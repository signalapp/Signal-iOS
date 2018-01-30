//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosEnvelope;
@class YapDatabaseReadWriteTransaction;

typedef void (^DecryptSuccessBlock)(NSData *_Nullable plaintextData, YapDatabaseReadWriteTransaction *transaction);
typedef void (^DecryptFailureBlock)(void);

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
