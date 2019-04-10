//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseConnection.h>

@class ECKeyPair;
@class PreKeyRecord;
@class SignedPreKeyRecord;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseConnection (OWS)

- (BOOL)hasObjectForKey:(NSString *)key inCollection:(NSString *)collection;
- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection defaultValue:(BOOL)defaultValue;
- (double)doubleForKey:(NSString *)key inCollection:(NSString *)collection defaultValue:(double)defaultValue;
- (int)intForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable id)objectForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable NSDate *)dateForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable NSDictionary *)dictionaryForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable NSString *)stringForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable NSData *)dataForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable ECKeyPair *)keyPairForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection;

- (NSUInteger)numberOfKeysInCollection:(NSString *)collection;

#pragma mark -

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)setBool:(BOOL)value forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)setDouble:(double)value forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)removeObjectForKey:(NSString *)string inCollection:(NSString *)collection;
- (void)setInt:(int)integer forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)setDate:(NSDate *)value forKey:(NSString *)key inCollection:(NSString *)collection;
- (int)incrementIntForKey:(NSString *)key inCollection:(NSString *)collection;

- (void)purgeCollection:(NSString *)collection;

@end

NS_ASSUME_NONNULL_END
