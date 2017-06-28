#import "YapDatabaseCrossProcessNotificationTransaction.h"
#import "YapDatabaseCrossProcessNotificationConnection.h"
#import "YapDatabaseCrossProcessNotificationPrivate.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

@interface YapDatabaseCrossProcessNotificationTransaction ()

@property (nonatomic, strong) YapDatabaseCrossProcessNotificationConnection* parentConnection;
@property (nonatomic, strong) YapDatabaseReadTransaction* databaseTransaction;

@end

@implementation YapDatabaseCrossProcessNotificationTransaction

- (id)initWithParentConnection:(YapDatabaseCrossProcessNotificationConnection *)inParentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)inDatabaseTransaction
{
	if ((self = [super init]))
	{
		self.parentConnection = inParentConnection;
        self.databaseTransaction = inDatabaseTransaction;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Extension Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
 *
 * This method is called to create any necessary tables (if needed),
 * as well as populate the view (if needed) by enumerating over the existing rows in the database.
**/
- (BOOL)createIfNeeded
{	
	return YES;
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
 *
 * This method is called to prepare the transaction for use.
 *
 * Remember, an extension transaction is a very short lived object.
 * Thus it stores the majority of its state within the extension connection (the parent).
 *
 * Return YES if completed successfully, or if already prepared.
 * Return NO if some kind of error occured.
**/
- (BOOL)prepareIfNeeded
{
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (YapDatabaseReadTransaction *)databaseTransaction
{
	return self.databaseTransaction;
}

/**
 * Required override method from YapDatabaseExtensionTransaction.
**/
- (YapDatabaseExtensionConnection *)extensionConnection
{
	return self.parentConnection;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cleanup & Commit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Required override method from YapDatabaseExtension
**/
- (void)didCommitTransaction
{
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	self.parentConnection = nil;    // Do not remove !
	self.databaseTransaction = nil; // Do not remove !
}

/**
 * Required override method from YapDatabaseExtension
**/
- (void)didRollbackTransaction
{
	// An extensionTransaction is only valid within the scope of its encompassing databaseTransaction.
	// I imagine this may occasionally be misunderstood, and developers may attempt to store the extension in an ivar,
	// and then use it outside the context of the database transaction block.
	// Thus, this code is here as a safety net to ensure that such accidental misuse doesn't do any damage.
	
	self.parentConnection = nil;    // Do not remove !
	self.databaseTransaction = nil; // Do not remove !
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction Hooks
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didInsertObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didUpdateObject:(id)object
       forCollectionKey:(YapCollectionKey *)collectionKey
           withMetadata:(id)metadata
                  rowid:(int64_t)rowid
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceObject:(id)object forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didReplaceMetadata:(id)metadata forCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didTouchObjectForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didTouchMetadataForCollectionKey:(YapCollectionKey __unused *)collectionKey withRowid:(int64_t __unused)rowid
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didTouchRowForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveObjectForCollectionKey:(YapCollectionKey *)collectionKey withRowid:(int64_t)rowid
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveObjectsForKeys:(NSArray __unused *)keys inCollection:(NSString *)collection withRowids:(NSArray *)rowids
{

}

/**
 * YapDatabase extension hook.
 * This method is invoked by a YapDatabaseReadWriteTransaction as a post-operation-hook.
**/
- (void)didRemoveAllObjectsInAllCollections
{

}

@end
