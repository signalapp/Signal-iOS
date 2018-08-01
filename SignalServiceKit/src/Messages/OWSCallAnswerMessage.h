//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageAnswer;

/**
 * Sent by the call recipient upon accepting a CallOffer
 */
@interface OWSCallAnswerMessage : NSObject

- (instancetype)initWithCallId:(UInt64)callId sessionDescription:(NSString *)sessionDescription;

@property (nonatomic, readonly) UInt64 callId;
@property (nonatomic, readonly, copy) NSString *sessionDescription;

- (nullable SSKProtoCallMessageAnswer *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
