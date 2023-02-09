//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^SubmitDebugLogsCompletion)(void);
typedef void (^UploadDebugLogsSuccess)(NSURL *url);
typedef void (^UploadDebugLogsFailure)(NSString *localizedErrorMessage, NSString *_Nullable logArchiveOrDirectoryPath);

@interface DebugLogs : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (void)submitLogs;

+ (void)submitLogsWithSupportTag:(nullable NSString *)tag completion:(nullable SubmitDebugLogsCompletion)completion;

@end

NS_ASSUME_NONNULL_END
