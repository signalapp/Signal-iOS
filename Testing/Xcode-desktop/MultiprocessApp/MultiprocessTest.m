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
#import <YapDatabase/YapDatabaseRTreeIndex.h>
#import <YapDatabase/YapDatabaseCrossProcessNotification.h>
#import <CocoaLumberjack/CocoaLumberjack.h>

static int counter = 1;

@implementation MultiprocessTest

-(void)_run:(NSString*)name specialBehavior:(BOOL)specialBehavior {
    YapDatabaseOptions* options = [[YapDatabaseOptions alloc] init];
    options.enableMultiProcessSupport = YES;

    NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString* filePath = [currentDir stringByAppendingPathComponent:@"db.yap"];
    
    srandom((int)getpid());
    
    YapDatabase* db = [[YapDatabase alloc] initWithPath:filePath options:options];

    /*
    YapDatabaseRTreeIndexSetup *setup = [[YapDatabaseRTreeIndexSetup alloc] init];
    [setup setColumns:@[@"minLat",
                        @"maxLat",
                        @"minLon",
                        @"maxLon"]];
    YapDatabaseRTreeIndexHandler *handler = [YapDatabaseRTreeIndexHandler withObjectBlock:^(NSMutableDictionary *dict, NSString *collection, NSString *key, id object) {
            dict[@"minLat"] = object[@"latitude"];
            dict[@"maxLat"] = object[@"latitude"];
            dict[@"minLon"] = object[@"longitude"];
            dict[@"maxLon"] = object[@"longitude"];
    }];
    YapDatabaseRTreeIndexOptions *rTreeOptions = [[YapDatabaseRTreeIndexOptions alloc] init];
    NSSet *allowedCollections = [NSSet setWithArray:@[@"coordinates"]];
    rTreeOptions.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:allowedCollections];
    YapDatabaseRTreeIndex *rTree = [[YapDatabaseRTreeIndex alloc] initWithSetup:setup handler:handler versionTag:@"1" options:rTreeOptions];
    [db registerExtension:rTree withName:@"rTree"];
    */
    
    YapDatabaseCrossProcessNotification* cpn = [[YapDatabaseCrossProcessNotification alloc] initWithIdentifier:@"mael"];
    [db registerExtension:cpn withName:@"cpn"];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(otherProcessDidChange:) name:YapDatabaseModifiedExternallyNotification object:nil];
    
    YapDatabaseConnection* connection1 = [db newConnection];
    YapDatabaseConnection* connection2 = [db newConnection];
    //YapDatabaseConnection* connection3 = [db newConnection];
    //YapDatabaseConnection* connection4 = [db newConnection];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        while (true) {
            NSString *key = [NSString stringWithFormat:@"%@(%d)", name, counter];
            counter++;
            [connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
                NSLog(@"%@: Writing \"%@\" to database (snapshot %llu)", name, key, connection1.snapshot);
                [transaction setObject:key forKey:@"key" inCollection:@"MyCollection"];
            }];
            int n = random() % 5000;
            usleep(n * 1000);
        }
    });

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        while (true) {
            [connection2 readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
                NSString *result = (NSString *)[transaction objectForKey:@"key" inCollection:@"MyCollection"];
                NSLog(@"%@: Got \"%@\" (snapshot %llu)", name, result, connection2.snapshot);
            }];
            int n = random() % 1000;
            usleep(n * 1000);
        }
    });

    /*
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        while (true) {
            int lon = random() % 10;
            int lat = random() % 10;
            int id = counter++;
            [connection3 readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
                NSLog(@"%@: RTREE: Writing \"%i, %i\" (%i) to database (snapshot %llu)", name, lon, lat, id, connection3.database.snapshot);
                NSDictionary* object = @{@"longitude": @(lon), @"latitude": @(lat), @"id": @(id)};
                [transaction setObject:object forKey:@"key" inCollection:@"coordinates"];
            }];
            int n = random() % 5000;
            usleep(n * 1000);
        }
    });
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        while (true) {
            [connection4 readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
                NSMutableArray *results = [NSMutableArray array];

                NSString *queryString = [NSString stringWithFormat:@"WHERE %@ >= ? AND %@ <= ? AND %@ >= ? AND %@ <= ?",
                                         @"minLon",
                                         @"maxLon",
                                         @"minLat",
                                         @"maxLat"];

                NSArray *parameters = @[@(2),
                                        @(8),
                                        @(2),
                                        @(8)];
                YapDatabaseQuery *query = [YapDatabaseQuery queryWithString:queryString parameters:parameters];

                YapDatabaseRTreeIndexTransaction *rTree = [transaction ext:@"rTree"];
                [rTree enumerateKeysAndObjectsMatchingQuery:query usingBlock:^(NSString *collection, NSString *key, id object, BOOL *stop) {
                    [results addObject:object];
                }];
                if (results.count == 0) {
                    NSLog(@"%@: RTREE: Got no result in [2, 8] x [2, 8]", name);
                }
                for (id result in results) {
                    NSLog(@"%@: RTREE: Got \"(%@, %@, %@)\" (snapshot %llu)", name, result[@"longitude"], result[@"latitude"], result[@"id"], connection4.database.snapshot);
                }
                
            }];
            int n = random() % 1000;
            usleep(n * 1000);
        }
    });
    */

}


- (void)run:(NSString *)name specialBehavior:(BOOL)specialBehavior {
    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
    
    [self _run:name specialBehavior:specialBehavior];
    
    while([runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {
    }
    
}

- (void)otherProcessDidChange:(NSNotification*)notif {
    NSLog(@"Database did Change: %@", notif);
}

@end
