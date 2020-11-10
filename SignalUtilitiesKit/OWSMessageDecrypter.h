//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SSKProtoEnvelope;
@class YapDatabaseReadWriteTransaction;

@interface OWSMessageDecryptResult : NSObject

@property (nonatomic, readonly) NSData *envelopeData;
@property (nonatomic, readonly, nullable) NSData *plaintextData;
@property (nonatomic, readonly) NSString *source;
@property (nonatomic, readonly) UInt32 sourceDevice;
@property (nonatomic, readonly) BOOL isUDMessage;

@end

#pragma mark -

// Decryption result includes the envelope since the envelope
// may be altered by the decryption process.
typedef void (^DecryptSuccessBlock)(OWSMessageDecryptResult *result, YapDatabaseReadWriteTransaction *transaction);
typedef void (^DecryptFailureBlock)(void);

@interface OWSMessageDecrypter : OWSMessageHandler

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

// decryptEnvelope: can be called from any thread.
// successBlock & failureBlock will be called an arbitrary thread.
//
// Exactly one of successBlock & failureBlock will be called,
// once.
- (void)decryptEnvelope:(SSKProtoEnvelope *)envelope
           envelopeData:(NSData *)envelopeData
           successBlock:(DecryptSuccessBlock)successBlock
           failureBlock:(DecryptFailureBlock)failureBlock;

@end

NS_ASSUME_NONNULL_END
