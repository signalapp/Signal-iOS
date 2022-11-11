//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoContent;
@class SSKProtoDataMessage;
@class SSKProtoEnvelope;

NSString *envelopeAddress(SSKProtoEnvelope *envelope);

@interface OWSMessageHandler : NSObject

+ (NSString *)descriptionForEnvelopeType:(SSKProtoEnvelope *)envelope;
+ (NSString *)descriptionForEnvelope:(SSKProtoEnvelope *)envelope;

- (NSString *)descriptionForEnvelope:(SSKProtoEnvelope *)envelope;

- (NSString *)descriptionForContent:(SSKProtoContent *)content;
- (NSString *)descriptionForDataMessage:(SSKProtoDataMessage *)dataMessage;
+ (void)logInvalidEnvelope:(SSKProtoEnvelope *)envelope;

@end

NS_ASSUME_NONNULL_END
