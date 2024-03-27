//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
                   dataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder
                          transaction:(SDSAnyReadTransaction *)transaction;

+ (void)addLocalProfileKeyToDataMessageBuilder:(SSKProtoDataMessageBuilder *)dataMessageBuilder;

+ (void)addLocalProfileKeyIfNecessary:(TSThread *)thread
                   callMessageBuilder:(SSKProtoCallMessageBuilder *)callMessageBuilder
                          transaction:(SDSAnyReadTransaction *)transaction;

+ (nullable NSString *)parseProtoE164:(nullable NSString *)value name:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
