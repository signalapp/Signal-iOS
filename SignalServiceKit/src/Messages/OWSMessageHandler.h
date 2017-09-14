//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kIncomingMessageBatchSize;

@class OWSSignalServiceProtosContent;
@class OWSSignalServiceProtosDataMessage;
@class OWSSignalServiceProtosEnvelope;

NSString *envelopeAddress(OWSSignalServiceProtosEnvelope *envelope);

@interface OWSMessageHandler : NSObject

- (NSString *)descriptionForEnvelopeType:(OWSSignalServiceProtosEnvelope *)envelope;
- (NSString *)descriptionForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope;
- (NSString *)descriptionForContent:(OWSSignalServiceProtosContent *)content;
- (NSString *)descriptionForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage;

@end

NS_ASSUME_NONNULL_END
