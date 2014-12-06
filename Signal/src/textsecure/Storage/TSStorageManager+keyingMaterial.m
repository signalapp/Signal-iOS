//
//  TSStorageManager+keyingMaterial.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+keyingMaterial.h"

@implementation TSStorageManager (keyingMaterial)


+ (NSString*)signalingKey{
    return [[self sharedManager] stringForKey:TSStorageServerSignalingKey
                                 inCollection:TSStorageUserAccountCollection];
}

+ (NSString*)serverAuthToken{
    return [[self sharedManager] stringForKey:TSStorageServerAuthToken
                                 inCollection:TSStorageUserAccountCollection];
}

+ (void)storeServerToken:(NSString*)authToken signalingKey:(NSString*)signalingKey phoneNumber:(NSString*)phoneNumber {
    YapDatabaseConnection *dbConn = [[self sharedManager] dbConnection];
    
    [dbConn readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:authToken    forKey:TSStorageServerAuthToken     inCollection:TSStorageUserAccountCollection];
        [transaction setObject:signalingKey forKey:TSStorageServerSignalingKey  inCollection:TSStorageUserAccountCollection];
        [transaction setObject:phoneNumber  forKey:TSStorageRegisteredNumberKey inCollection:TSStorageUserAccountCollection];
    }];
}

@end
