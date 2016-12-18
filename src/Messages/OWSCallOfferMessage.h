//  Created by Michael Kirk on 12/1/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosCallMessageOffer;

@interface OWSCallOfferMessage : NSObject

- (instancetype)initWithCallId:(UInt64)callId sessionDescription:(NSString *)sessionDescription;

@property (nonatomic, readonly) UInt64 callId;
@property (nonatomic, readonly, copy) NSString *sessionDescription;

- (OWSSignalServiceProtosCallMessageOffer *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
