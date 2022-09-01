//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface CallKitIdStore : NSObject

+ (void)setThread:(TSThread *)thread forCallKitId:(NSString *)callKitId;
+ (nullable TSThread *)threadForCallKitId:(NSString *)callKitId;

@end

NS_ASSUME_NONNULL_END
