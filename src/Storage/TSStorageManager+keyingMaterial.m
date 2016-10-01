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

- (void)runIfHasLocalNumber:(void (^)())block
{
    [self.newDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        if ([transaction objectForKey:TSStorageRegisteredNumberKey inCollection:TSStorageUserAccountCollection]) {
            block();
        } else {
            DDLogDebug(@"%@ Skipping block since no local number is registered", self.tag);
        }
    }];
}

+ (NSString *)signalingKey {
    return [[self sharedManager] stringForKey:TSStorageServerSignalingKey inCollection:TSStorageUserAccountCollection];
}

+ (NSString *)serverAuthToken {
    return [[self sharedManager] stringForKey:TSStorageServerAuthToken inCollection:TSStorageUserAccountCollection];
}

+ (void)storePhoneNumber:(NSString *)phoneNumber {
    YapDatabaseConnection *dbConn = [[self sharedManager] dbConnection];

    [dbConn readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
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

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
