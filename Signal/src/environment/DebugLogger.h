//
//  DebugLogger.h
//  Signal
//
//  Created by Frederic Jacobs on 08/08/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <CocoaLumberjack/DDFileLogger.h>

@interface DebugLogger : NSObject

+ (instancetype)sharedLogger;

- (void)enableFileLogging;

- (void)disableFileLogging;

- (void)enableTTYLogging;

- (void)wipeLogs;

- (NSString *)logsDirectory;

@property (nonatomic) DDFileLogger *fileLogger;

@end
