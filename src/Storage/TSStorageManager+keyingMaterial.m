//
//  TSStorageManager+keyingMaterial.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+keyingMaterial.h"

@implementation TSStorageManager (keyingMaterial)

+ (NSString *)localNumber
{
    return [[self sharedManager] localNumber];
}

- (NSString *)localNumber
{
    return [self stringForKey:TSStorageRegisteredNumberKey inCollection:TSStorageUserAccountCollection];
}

- (void)ifLocalNumberPresent:(BOOL)runIfPresent runAsync:(void (^)())block;
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block BOOL isPresent;
        [self.newDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
            isPresent = [[transaction objectForKey:TSStorageRegisteredNumberKey
                                      inCollection:TSStorageUserAccountCollection] boolValue];
        }];

        if (isPresent == runIfPresent) {
            if (runIfPresent) {
                DDLogDebug(@"%@ Running existing-user block", self.logTag);
            } else {
                DDLogDebug(@"%@ Running new-user block", self.logTag);
            }
            block();
        } else {
            if (runIfPresent) {
                DDLogDebug(@"%@ Skipping existing-user block for new-user", self.logTag);
            } else {
                DDLogDebug(@"%@ Skipping new-user block for existing-user", self.logTag);
            }
        }
    });
}

+ (NSString *)signalingKey {
    return [[self sharedManager] stringForKey:TSStorageServerSignalingKey inCollection:TSStorageUserAccountCollection];
}

+ (NSString *)serverAuthToken {
    return [[self sharedManager] stringForKey:TSStorageServerAuthToken inCollection:TSStorageUserAccountCollection];
}

- (void)storePhoneNumber:(NSString *)phoneNumber
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:phoneNumber
                        forKey:TSStorageRegisteredNumberKey
                  inCollection:TSStorageUserAccountCollection];
    }];
}

+ (void)storeServerToken:(NSString *)authToken signalingKey:(NSString *)signalingKey {
    YapDatabaseConnection *dbConn = [[self sharedManager] dbConnection];

    [dbConn readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [transaction setObject:authToken forKey:TSStorageServerAuthToken inCollection:TSStorageUserAccountCollection];
      [transaction setObject:signalingKey
                      forKey:TSStorageServerSignalingKey
                inCollection:TSStorageUserAccountCollection];

    }];
}

#pragma mark - Logging

+ (NSString *)logTag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)logTag
{
    return self.class.logTag;
}

@end
