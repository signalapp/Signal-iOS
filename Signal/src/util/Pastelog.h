//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface Pastelog : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate, UIAlertViewDelegate>

typedef void (^successBlock)(NSError *error, NSString *urlString);

+(void)reportErrorAndSubmitLogsWithAlertTitle:(NSString*)alertTitle alertBody:(NSString*)alertBody;
+(void)reportErrorAndSubmitLogsWithAlertTitle:(NSString*)alertTitle alertBody:(NSString*)alertBody completionBlock:(successBlock)block;

+(void)submitLogs;
+(void)submitLogsWithCompletion:(successBlock)block;
+(void)submitLogsWithCompletion:(successBlock)block forFileLogger:(DDFileLogger*)fileLogger;

@end
