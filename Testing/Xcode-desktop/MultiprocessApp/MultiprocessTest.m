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

static int counter = 1;

@implementation MultiprocessTest

-(void)run:(NSString*)name {
    YapDatabaseOptions* options = [[YapDatabaseOptions alloc] init];
    options.enableMultiProcessSupport = YES;

    NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString* filePath = [currentDir stringByAppendingPathComponent:@"db.yap"];
    
    YapDatabase* db = [[YapDatabase alloc] initWithPath:filePath options:options];
    
    YapDatabaseConnection* connection1 = [db newConnection];
    YapDatabaseConnection* connection2 = [db newConnection];

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (true) {
            NSString *key = [NSString stringWithFormat:@"%@(%d)", name, counter];
            counter++;
            [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
                NSLog(@"%@: Writing \"%@\" to database (snapshot %llu)", name, key, connection1.database.snapshot);
                [transaction setObject:key forKey:@"key" inCollection:@"MyCollection"];
            }];
            int n = random() % 5000;
            usleep(n * 1000);
        }
    });

    while (true) {
        [connection2 readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
            NSString *result = (NSString *)[transaction objectForKey:@"key" inCollection:@"MyCollection"];
            NSLog(@"%@: Got \"%@\" (snapshot %llu)", name, result, connection2.database.snapshot);
        }];
        int n = random() % 1000;
        usleep(n * 1000);
    }
}

@end
