//
//  MultiprocessTest.m
//  YapDatabaseTesting
//
//  Created by Jeremie Girault on 15/02/2016.
//  Copyright © 2016 Robbie Hanson. All rights reserved.
//

@import Foundation;

#import "MultiprocessTest.h"
#import <YapDatabase/YapDatabase.h>
#import <CocoaLumberjack/CocoaLumberjack.h>

const int ddLogLevel = DDLogLevelAll;

@interface ParentChildFormatter: NSObject <DDLogFormatter>

+(instancetype)shared;

@end

@implementation ParentChildFormatter

+(instancetype)shared {
    static dispatch_once_t onceToken;
    static ParentChildFormatter* instance = nil;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    
    return instance;
}

- (NSString *)formatLogMessage:(DDLogMessage *)logMessage {
    static NSString* processName = @"Unknown";
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pid_t myPid = getpid();
        processName = (myPid == 0 ? @"PARENT" : @"CHILD");
    });
    
    NSString* msg = [NSString stringWithFormat:@"%@: %@ : %@", processName, logMessage->_timestamp, logMessage->_message];
    NSLog(msg);
    return msg;
}

@end

@implementation MultiprocessTest

-(void)runParent {
    YapDatabaseOptions* options = [[YapDatabaseOptions alloc] init];
    options.enableMultiProcessSupport = YES;
    
    NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString* filePath = [currentDir stringByAppendingPathComponent:@"db.yap"];
    
    DDLogInfo(@"Initializing with DB in path: %@", filePath);
    
    YapDatabase* db = [[YapDatabase alloc] initWithPath:filePath options:options];
    
    YapDatabaseConnection* connection1 = [db newConnection];
    
    DDLogInfo(@"Before Write");
    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        DDLogInfo(@"Start Write");
        sleep(5);
        [transaction setObject:@"Hello World" forKey:@"default" inCollection:@"MyCollection"];
        
        DDLogInfo(@"End Write");
    }];
    DDLogInfo(@"After Write");
}

-(void)runChild {
    sleep(1);
    
    YapDatabaseOptions* options = [[YapDatabaseOptions alloc] init];
    options.enableMultiProcessSupport = YES;
    
    NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString* filePath = [currentDir stringByAppendingPathComponent:@"db.yap"];
    
    DDLogInfo(@"Initializing with DB in path: %@", filePath);
    
    YapDatabase* db = [[YapDatabase alloc] initWithPath:filePath options:options];
    
    YapDatabaseConnection* connection1 = [db newConnection];
    
    DDLogInfo(@"Before Write");
    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        DDLogInfo(@"Start Write");
        sleep(5);
        [transaction setObject:@"Hello World" forKey:@"default" inCollection:@"MyCollection"];
        
        DDLogInfo(@"End Write");
    }];
    NSLog(@"After Write");
}

-(void)runAsParent:(BOOL)parent {
    [[DDTTYLogger sharedInstance] setLogFormatter:[ParentChildFormatter shared]];
    [[DDASLLogger sharedInstance] setLogFormatter:[ParentChildFormatter shared]];
    
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    
    if (parent) {
        [self runParent];
    } else {
        [self runChild];
    }
    
    sleep(5);
}

@end
