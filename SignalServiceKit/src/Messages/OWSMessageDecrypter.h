//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SSKProtoEnvelope;
@class SignalServiceAddress;

@interface OWSMessageDecryptResult : NSObject

@property (nonatomic, readonly) NSData *envelopeData;
@property (nonatomic, readonly, nullable) NSData *plaintextData;
@property (nonatomic, readonly) SignalServiceAddress *sourceAddress;
@property (nonatomic, readonly) UInt32 sourceDevice;
@property (nonatomic, readonly) BOOL isUDMessage;

@end

#pragma mark -

// Decryption result includes the envelope since the envelope
// may be altered by the decryption process.
typedef void (^DecryptSuccessBlock)(OWSMessageDecryptResult *result, SDSAnyWriteTransaction *transaction);
typedef void (^DecryptFailureBlock)(void);

@interface OWSMessageDecrypter : OWSMessageHandler

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
