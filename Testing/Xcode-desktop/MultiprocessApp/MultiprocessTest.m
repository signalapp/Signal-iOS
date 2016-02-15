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

@implementation MultiprocessTest

-(void)run {
    
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
    YapDatabaseOptions* options = [[YapDatabaseOptions alloc] init];
    options.enableMultiProcessSupport = YES;
    
    NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString* filePath = [currentDir stringByAppendingPathComponent:@"db.yap"];
    
    NSLog(@"Initializing with DB in path: %@", filePath);
    
    YapDatabase* db = [[YapDatabase alloc] initWithPath:filePath options:options];
    
    YapDatabaseConnection* connection1 = [db newConnection];
    YapDatabaseConnection* connection2 = [db newConnection];
    
    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [transaction setObject:@"Hello World" forKey:@"default" inCollection:@"MyCollection"];
    }];
    
    //[connection2 beginLongLivedReadTransaction];
    [connection2 readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        NSString* obj = [transaction objectForKey:@"default" inCollection:@"MyCollection"];
        NSLog(@"result -> %@", obj);
    }];
    
    [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [transaction setObject:@"Hello Bob" forKey:@"default" inCollection:@"MyCollection"];
    }];
    
    [connection2 readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        NSString* obj = [transaction objectForKey:@"default" inCollection:@"MyCollection"];
        NSLog(@"result -> %@", obj);
    }];
    
    /*
    [connection2 readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        NSString* obj = [transaction objectForKey:@"default" inCollection:@"MyCollection"];
        NSLog(@"result -> %@", obj);
    }];*/
    
    
    
    [connection2 beginLongLivedReadTransaction];
    
    [connection2 readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        NSString* obj = [transaction objectForKey:@"default" inCollection:@"MyCollection"];
        NSLog(@"result -> %@", obj);
    }];
    
    sleep(5);
}

@end
