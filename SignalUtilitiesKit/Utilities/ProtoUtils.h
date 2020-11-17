//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SNProtoCallMessageBuilder;
@class SNProtoDataMessageBuilder;
@class TSThread;

@interface ProtoUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                          recipientId:(NSString *_Nullable)recipientId
                   dataMessageBuilder:(SNProtoDataMessageBuilder *)dataMessageBuilder;

+ (void)addLocalProfileKeyToDataMessageBuilder:(SNProtoDataMessageBuilder *)dataMessageBuilder;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                          recipientId:(NSString *)recipientId
                   callMessageBuilder:(SNProtoCallMessageBuilder *)callMessageBuilder;

@end

NS_ASSUME_NONNULL_END
