//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^SubmitDebugLogsCompletion)(void);
typedef void (^UploadDebugLogsSuccess)(NSURL *url);
typedef void (^UploadDebugLogsFailure)(NSString *localizedErrorMessage, NSString *_Nullable logArchiveOrDirectoryPath);

@interface Pastelog : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (void)submitLogs;

+ (void)submitLogsWithCompletion:(nullable SubmitDebugLogsCompletion)completion;

+ (void)uploadLogsWithSuccess:(UploadDebugLogsSuccess)successParam failure:(UploadDebugLogsFailure)failureParam;

+ (void)exportLogs;

@end

NS_ASSUME_NONNULL_END
