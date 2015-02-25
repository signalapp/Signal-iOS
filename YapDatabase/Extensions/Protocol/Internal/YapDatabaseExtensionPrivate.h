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


@interface YapDatabaseExtension ()

// See YapDatabaseExtension.m for discussion of this method
+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
                      wasPersistent:(BOOL)wasPersistent;

// See YapDatabaseExtension.m for discussion of this method
+ (NSArray *)previousClassNames;

// See YapDatabaseExtension.m for discussion of these method.
// You should consider them READ-ONLY.
@property (atomic, copy, readwrite) NSString *registeredName;
@property (atomic, weak, readwrite) YapDatabase *registeredDatabase;

// See YapDatabaseExtension.m for discussion of this method
- (BOOL)supportsDatabase:(YapDatabase *)database withRegisteredExtensions:(NSDictionary *)registeredExtensions;

// See YapDatabaseExtension.m for discussion of this method
- (NSSet *)dependencies;

// See YapDatabaseExtension.m for discussion of this method
- (BOOL)isPersistent;

// See YapDatabaseExtension.m for discussion of this method
- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection;

// See YapDatabaseExtension.m for discussion of this method
- (void)processChangeset:(NSDictionary *)changeset;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseExtensionConnection ()

// See YapDatabaseExtensionConnection.m for discussion of this method
- (YapDatabaseExtension *)extension;

// See YapDatabaseExtensionConnection.m for discussion of this method
- (id)newReadTransaction:(YapDatabaseReadTransaction *)databaseTransaction;
- (id)newReadWriteTransaction:(YapDatabaseReadWriteTransaction *)databaseTransaction;

// See YapDatabaseExtensionConnection.m for discussion of this method
- (void)_flushMemoryWithFlags:(YapDatabaseConnectionFlushMemoryFlags)flags;

// See YapDatabaseExtensionConnection.m for discussion of this method
- (void)getInternalChangeset:(NSMutableDictionary **)internalPtr
           externalChangeset:(NSMutableDictionary **)externalPtr
              hasDiskChanges:(BOOL *)hasDiskChangesPtr;

// See YapDatabaseExtensionConnection.m for discussion of this method
- (void)processChangeset:(NSDictionary *)changeset;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseExtensionTransaction ()

// See YapDatabaseExtensionTransaction.m for discussion of this method
- (YapDatabaseExtensionConnection *)extensionConnection;
- (YapDatabaseReadTransaction *)databaseTransaction;

// See YapDatabaseExtensionTransaction.m for discussion of this method
- (BOOL)createIfNeeded;

// See YapDatabaseExtensionTransaction.m for discussion of this method
- (BOOL)prepareIfNeeded;

// See YapDatabaseExtensionTransaction.m for discussion of this method
- (BOOL)flushPendingChangesToMainDatabaseTable;

// See YapDatabaseExtensionTransaction.m for discussion of this method
- (void)flushPendingChangesToExtensionTables;

// See YapDatabaseExtensionTransaction.m for discussion of this method
- (void)didCommitTransaction;

// See YapDatabaseExtensionTransaction.m for discussion of this method
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
