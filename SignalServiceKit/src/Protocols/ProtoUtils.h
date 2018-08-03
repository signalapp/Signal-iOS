//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageBuilder;
@class SSKProtoDataMessageBuilder;
@class TSThread;

@interface ProtoUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                          recipientId:(NSString *_Nullable)recipientId
                   dataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder;

+ (void)addLocalProfileKeyToDataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                          recipientId:(NSString *)recipientId
                   callMessageBuilder:(SSKProtoCallMessageBuilder *)callMessageBuilder;

@end

NS_ASSUME_NONNULL_END
