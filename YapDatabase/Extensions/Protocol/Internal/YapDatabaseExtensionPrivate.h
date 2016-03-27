#import <Foundation/Foundation.h>

#import "YapDatabaseExtension.h"
#import "YapDatabaseExtensionConnection.h"
#import "YapDatabaseExtensionTransaction.h"

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapCollectionKey.h"
#import "YapMemoryTable.h"

#import "sqlite3.h"


typedef NS_OPTIONS(NSUInteger, YapDatabaseConnectionFlushMemoryFlags_Extension) {
//	YapDatabaseConnectionFlushMemoryFlags_None       = 0,
//	YapDatabaseConnectionFlushMemoryFlags_Caches     = 1 << 0,
//	YapDatabaseConnectionFlushMemoryFlags_Statements = 1 << 1,
//	YapDatabaseConnectionFlushMemoryFlags_Internal   = 1 << 2,
//	YapDatabaseConnectionFlushMemoryFlags_All        = (YapDatabaseConnectionFlushMemoryFlags_Caches     |
//																		 YapDatabaseConnectionFlushMemoryFlags_Statements |
//																		 YapDatabaseConnectionFlushMemoryFlags_Internal   ),
	
	YapDatabaseConnectionFlushMemoryFlags_Extension_State = 1 << 3,
};


@interface YapDatabaseExtension ()

/**
 * See YapDatabaseExtension.m for discussion of these methods.
**/

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
                      wasPersistent:(BOOL)wasPersistent;

+ (NSArray *)previousClassNames;

@property (atomic, copy, readwrite) NSString *registeredName;
@property (atomic, weak, readwrite) YapDatabase *registeredDatabase;

- (NSSet *)dependencies;
- (BOOL)isPersistent;

- (BOOL)supportsDatabaseWithRegisteredExtensions:(NSDictionary<NSString*, YapDatabaseExtension*> *)registeredExtensions;
- (void)didRegisterExtension;

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection;

- (void)processChangeset:(NSDictionary *)changeset;
- (void)noteCommittedChangeset:(NSDictionary *)changeset registeredName:(NSString *)extName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseExtensionConnection ()

/**
 * See YapDatabaseExtensionConnection.m for discussion of these methods
**/

- (YapDatabaseExtension *)extension;

- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction;
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction;

- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags;

- (void)getInternalChangeset:(NSMutableDictionary **)internalPtr
           externalChangeset:(NSMutableDictionary **)externalPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr;


- (void)processChangeset:(NSDictionary *)changeset;
- (void)noteCommittedChangeset:(NSDictionary *)changeset registeredName:(NSString *)registeredName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseExtensionTransaction ()

/**
 * See YapDatabaseExtensionTransaction.m for discussion of these methods
**/

- (YapDatabaseExtensionConnection *)extensionConnection;
- (YapDatabaseReadTransaction *)databaseTransaction;

- (BOOL)createIfNeeded;
- (BOOL)prepareIfNeeded;

- (BOOL)flushPendingChangesToMainDatabaseTable;
- (void)flushPendingChangesToExtensionTables;

- (void)didCommitTransaction;
- (void)didRollbackTransaction;

#pragma mark Hooks

/**
 * See YapDatabaseExtensionTransaction.m for discussion of these methods
**/

- (void)handleInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid;

- (void)handleUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid;

- (void)handleReplaceObject:(id)object
           forCollectionKey:(YapCollectionKey *)collectionKey
                  withRowid:(int64_t)rowid;

- (void)handleReplaceMetadata:(id)metadata
             forCollectionKey:(YapCollectionKey *)collectionKey
                    withRowid:(int64_t)rowid;

- (void)handleTouchObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid;
- (void)handleTouchMetadataForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid;
- (void)handleTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid;

- (void)handleRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid;

- (void)handleRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids;

- (void)handleRemoveAllObjectsInAllCollections;

// Pre-op versions

- (void)handleWillInsertObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata;

- (void)handleWillUpdateObject:(id)object
          forCollectionKey:(YapCollectionKey *)collectionKey
              withMetadata:(id)metadata
                     rowid:(int64_t)rowid;

- (void)handleWillReplaceObject:(id)object
           forCollectionKey:(YapCollectionKey *)collectionKey
                  withRowid:(int64_t)rowid;

- (void)handleWillReplaceMetadata:(id)metadata
             forCollectionKey:(YapCollectionKey *)collectionKey
                    withRowid:(int64_t)rowid;

- (void)handleWillRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid;

- (void)handleWillRemoveObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids;

- (void)handleWillRemoveAllObjectsInAllCollections;


#pragma mark Configuration Values

/**
 * See YapDatabaseExtensionTransaction.m for discussion of these methods
**/

- (BOOL)getBoolValue:(BOOL *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;
- (BOOL)boolValueForExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;
- (void)setBoolValue:(BOOL)value forExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;

- (BOOL)getIntValue:(int *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;
- (int)intValueForExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;
- (void)setIntValue:(int)value forExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;

- (BOOL)getDoubleValue:(double *)valuePtr forExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;
- (double)doubleValueForExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;
- (void)setDoubleValue:(double)value forExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;

- (NSString *)stringValueForExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;
- (void)setStringValue:(NSString *)value forExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;

- (NSData *)dataValueForExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;
- (void)setDataValue:(NSData *)value forExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;

- (void)removeValueForExtensionKey:(NSString *)key persistent:(BOOL)inDatabaseOrMemoryTable;

@end
