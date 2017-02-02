//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageAnswer;

/**
 * Sent by the call recipient upon accepting a CallOffer
 */
@interface OWSCallAnswerMessage : NSObject

- (instancetype)initWithCallId:(UInt64)callId sessionDescription:(NSString *)sessionDescription;

@property (nonatomic, readonly) UInt64 callId;
@property (nonatomic, readonly, copy) NSString *sessionDescription;

- (OWSSignalServiceProtosCallMessageAnswer *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
