//
//  TSStorageManager.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageKeys.h"

#import <Foundation/Foundation.h>
#import <YapDatabase/YapDatabase.h>

@class ECKeyPair;
@class PreKeyRecord;
@class SignedPreKeyRecord;

extern NSString *const TSUIDatabaseConnectionDidUpdateNotification;

@interface TSStorageManager : NSObject

+ (instancetype)sharedManager;
- (void)setupDatabase;
- (void)deleteThreadsAndMessages;
- (BOOL)databasePasswordAccessible;
- (void)wipeSignalStorage;

- (YapDatabase *)database;
- (YapDatabaseConnection *)newDatabaseConnection;


- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)removeObjectForKey:(NSString *)string inCollection:(NSString *)collection;


- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection;
- (int)intForKey:(NSString *)key inCollection:(NSString *)collection;
- (void)setInt:(int)integer forKey:(NSString *)key inCollection:(NSString *)collection;
- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection;
- (NSDictionary *)dictionaryForKey:(NSString *)key inCollection:(NSString *)collection;
- (NSString *)stringForKey:(NSString *)key inCollection:(NSString *)collection;
- (NSData *)dataForKey:(NSString *)key inCollection:(NSString *)collection;
- (ECKeyPair *)keyPairForKey:(NSString *)key inCollection:(NSString *)collection;
- (PreKeyRecord *)preKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection;
- (SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection;
- (void)purgeCollection:(NSString *)collection;

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end
