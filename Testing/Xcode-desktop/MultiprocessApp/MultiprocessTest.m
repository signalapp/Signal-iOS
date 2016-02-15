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

@implementation MultiprocessTest

-(void)run {
    YapDatabaseOptions* options = [[YapDatabaseOptions alloc] init];
    options.enableMultiProcessSupport = YES;
    
    NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString* filePath = [currentDir stringByAppendingPathComponent:@"db.yap"];
    
    NSLog(@"Initializing with DB in path: %@", filePath);
    
    YapDatabase* db = [[YapDatabase alloc] initWithPath:filePath options:options];
    
    YapDatabaseConnection* connection = [db newConnection];
    
    [connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
        [transaction setObject:@"Hello World" forKey:@"default" inCollection:@"MyCollection"];
    }];
    
    [connection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        NSString* value = [transaction objectForKey:@"default" inCollection:@"MyCollection"];
        NSLog(@"%@", value);
    }];
}

@end
