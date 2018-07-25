//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosContent;
@class OWSSignalServiceProtosDataMessage;
@class SSKEnvelope;

NSString *envelopeAddress(SSKEnvelope *envelope);

@interface OWSMessageHandler : NSObject

- (NSString *)descriptionForEnvelopeType:(SSKEnvelope *)envelope;
- (NSString *)descriptionForEnvelope:(SSKEnvelope *)envelope;
- (NSString *)descriptionForContent:(OWSSignalServiceProtosContent *)content;
- (NSString *)descriptionForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage;

@end

NS_ASSUME_NONNULL_END
