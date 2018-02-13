//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@interface Pastelog : NSObject

typedef void (^DebugLogsUploadedBlock)(NSError *error, NSString *urlString);
typedef void (^DebugLogsSharedBlock)(void);

+(void)submitLogs;
+ (void)submitLogsWithShareCompletion:(nullable DebugLogsSharedBlock)block;
+ (void)submitLogsWithUploadCompletion:(DebugLogsUploadedBlock)block;
+ (void)submitLogsWithUploadCompletion:(DebugLogsUploadedBlock)block forFileLogger:(DDFileLogger *)fileLogger;

@end
