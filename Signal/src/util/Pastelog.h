//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^SubmitDebugLogsCompletion)(void);

@interface Pastelog : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)submitLogs;
+ (void)submitEmailWithLogUrl:(nullable NSURL *)url NS_SWIFT_NAME(submitEmail(logUrl:));
+ (void)submitLogsWithCompletion:(nullable SubmitDebugLogsCompletion)completion;

@end

NS_ASSUME_NONNULL_END
