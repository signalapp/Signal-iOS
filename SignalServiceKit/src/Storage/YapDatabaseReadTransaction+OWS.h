//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseTransaction.h>

@class ECKeyPair;
@class PreKeyRecord;
@class SignedPreKeyRecord;

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseReadTransaction (OWS)

- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection;
- (BOOL)boolForKey:(NSString *)key inCollection:(NSString *)collection defaultValue:(BOOL)defaultValue;
- (int)intForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable NSDate *)dateForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable NSDictionary *)dictionaryForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable NSString *)stringForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable NSData *)dataForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable ECKeyPair *)keyPairForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable PreKeyRecord *)preKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection;
- (nullable SignedPreKeyRecord *)signedPreKeyRecordForKey:(NSString *)key inCollection:(NSString *)collection;

@end

NS_ASSUME_NONNULL_END
