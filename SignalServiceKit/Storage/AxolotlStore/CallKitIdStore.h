//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface CallKitIdStore : NSObject

+ (void)setThread:(TSThread *)thread forCallKitId:(NSString *)callKitId;
+ (nullable TSThread *)threadForCallKitId:(NSString *)callKitId;

@end

NS_ASSUME_NONNULL_END
