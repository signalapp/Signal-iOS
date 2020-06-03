//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class SSKProtoCallMessageBuilder;
@class SSKProtoDataMessageBuilder;
@class SignalServiceAddress;
@class TSThread;

@interface ProtoUtils : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                              address:(SignalServiceAddress *_Nullable)address
                   dataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder
                          transaction:(SDSAnyReadTransaction *)transaction;

+ (void)addLocalProfileKeyToDataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                              address:(SignalServiceAddress *)address
                   callMessageBuilder:(SSKProtoCallMessageBuilder *)callMessageBuilder
                          transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
