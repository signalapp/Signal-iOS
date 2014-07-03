//
//  LogSubmit.h
//  Signal
//
//  Created by Frederic Jacobs on 02/07/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LogSubmit : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>

typedef void (^successBlock)(BOOL success, NSString *urlString);

+(void)submitLogsWithCompletion:(successBlock)block;

@property (nonatomic)NSMutableData *responseData;

@end
