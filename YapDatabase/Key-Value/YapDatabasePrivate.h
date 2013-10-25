#import <Foundation/Foundation.h>

#import "YapAbstractDatabasePrivate.h"

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "sqlite3.h"


@interface YapDatabase () {
@public
	
	YapDatabaseSerializer objectSerializer;       // Read-only by transactions
	YapDatabaseDeserializer objectDeserializer;   // Read-only by transactions
	
	YapDatabaseSerializer metadataSerializer;     // Read-only by transactions
	YapDatabaseDeserializer metadataDeserializer; // Read-only by transactions
	
	YapDatabaseSanitizer objectSanitizer;         // Read-only by transactions
	YapDatabaseSanitizer metadataSanitizer;       // Read-only by transactions
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseConnection () {
@public
	
	__strong YapDatabase *database;
	
	NSMutableDictionary *objectChanges;
	NSMutableDictionary *metadataChanges;
	NSMutableSet *removedKeys;
	BOOL allKeysRemoved;
	BOOL hasDiskChanges;
}

- (sqlite3_stmt *)getCountStatement;
- (sqlite3_stmt *)getCountForRowidStatement;
- (sqlite3_stmt *)getRowidForKeyStatement;
- (sqlite3_stmt *)getKeyForRowidStatement;
- (sqlite3_stmt *)getDataForRowidStatement;
- (sqlite3_stmt *)getMetadataForRowidStatement;
- (sqlite3_stmt *)getAllForRowidStatement;
- (sqlite3_stmt *)getDataForKeyStatement;
- (sqlite3_stmt *)getMetadataForKeyStatement;
- (sqlite3_stmt *)getAllForKeyStatement;
- (sqlite3_stmt *)insertForRowidStatement;
- (sqlite3_stmt *)updateAllForRowidStatement;
- (sqlite3_stmt *)updateMetadataForRowidStatement;
- (sqlite3_stmt *)removeForRowidStatement;
- (sqlite3_stmt *)removeAllStatement;
- (sqlite3_stmt *)enumerateKeysStatement;
- (sqlite3_stmt *)enumerateKeysAndMetadataStatement;
- (sqlite3_stmt *)enumerateKeysAndObjectsStatement;
- (sqlite3_stmt *)enumerateRowsStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseReadTransaction () {
@public
	__unsafe_unretained YapDatabaseConnection *connection;
}

- (BOOL)getRowid:(int64_t *)rowidPtr forKey:(NSString *)key;

- (BOOL)getKey:(NSString **)keyPtr forRowid:(int64_t)rowid;
- (BOOL)getKey:(NSString **)keyPtr object:(id *)objectPtr forRowid:(int64_t)rowid;
- (BOOL)getKey:(NSString **)keyPtr metadata:(id *)metadataPtr forRowid:(int64_t)rowid;
- (BOOL)getKey:(NSString **)keyPtr object:(id *)objectPtr metadata:(id *)metadataPtr forRowid:(int64_t)rowid;

- (BOOL)hasRowForRowid:(int64_t)rowid;

- (void)_enumerateKeysUsingBlock:(void (^)(int64_t rowid, NSString *key, BOOL *stop))block;

- (void)_enumerateKeysAndMetadataUsingBlock:(void (^)(int64_t rowid, NSString *key, id metadata, BOOL *stop))block;
- (void)_enumerateKeysAndMetadataUsingBlock:(void (^)(int64_t rowid, NSString *key, id metadata, BOOL *stop))block
                                 withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter;

- (void)_enumerateKeysAndObjectsUsingBlock:(void (^)(int64_t rowid, NSString *key, id object, BOOL *stop))block;
- (void)_enumerateKeysAndObjectsUsingBlock:(void (^)(int64_t rowid, NSString *key, id object, BOOL *stop))block
                                withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter;

- (void)_enumerateRowsUsingBlock:(void (^)(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop))block;
- (void)_enumerateRowsUsingBlock:(void (^)(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop))block
                      withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter;

@end

