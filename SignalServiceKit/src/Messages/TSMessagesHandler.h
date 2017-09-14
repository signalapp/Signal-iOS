//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kIncomingMessageBatchSize;

@class OWSSignalServiceProtosEnvelope;

NSString *envelopeAddress(OWSSignalServiceProtosEnvelope *envelope);

@interface TSMessagesHandler : NSObject

- (NSString *)descriptionForEnvelopeType:(OWSSignalServiceProtosEnvelope *)envelope;
- (NSString *)descriptionForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope;

@end

NS_ASSUME_NONNULL_END
