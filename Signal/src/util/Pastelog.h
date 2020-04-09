//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^SubmitDebugLogsCompletion)(void);
typedef void (^UploadDebugLogsSuccess)(NSURL *url);
typedef void (^UploadDebugLogsFailure)(NSString *localizedErrorMessage);

@interface Pastelog : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (void)submitLogs;

+ (void)submitEmailWithDefaultErrorHandlingWithSubject:(NSString *)subject
                                                logUrl:(nullable NSURL *)url
    NS_SWIFT_NAME(submitEmailWithDefaultErrorHandling(subject:logUrl:));

+ (BOOL)submitEmailWithSubject:(NSString *)subject
                        logUrl:(nullable NSURL *)url
                         error:(NSError **)outError NS_SWIFT_NAME(submitEmail(subject:logUrl:));

+ (void)submitLogsWithCompletion:(nullable SubmitDebugLogsCompletion)completion;

+ (void)uploadLogsWithSuccess:(UploadDebugLogsSuccess)successParam failure:(UploadDebugLogsFailure)failureParam;

@end

NS_ASSUME_NONNULL_END
