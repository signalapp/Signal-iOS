//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface Pastelog : NSObject

typedef void (^successBlock)(NSError *error, NSString *urlString);

+(void)submitLogs;
+(void)submitLogsWithCompletion:(successBlock)block;
+(void)submitLogsWithCompletion:(successBlock)block forFileLogger:(DDFileLogger*)fileLogger;

@end
