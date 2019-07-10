//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageBuilder;
@class SSKProtoDataMessageBuilder;
@class SignalServiceAddress;
@class TSThread;

@interface ProtoUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                              address:(SignalServiceAddress *_Nullable)address
                   dataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder;

+ (void)addLocalProfileKeyToDataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                              address:(SignalServiceAddress *)address
                   callMessageBuilder:(SSKProtoCallMessageBuilder *)callMessageBuilder;

@end

NS_ASSUME_NONNULL_END
