/**
 * Copyright Deusty LLC.
**/

#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseCloudCore.h"
#import "YapDatabaseCloudCoreConnection.h"
#import "YapDatabaseCloudCoreTransaction.h"
#import "YapDatabaseCloudCoreTypes.h"
#import "YapDatabaseCloudCoreOptions.h"

#import "YapDatabaseCloudCoreOperation.h"
#import "YapDatabaseCloudCoreFileOperation.h"
#import "YapDatabaseCloudCoreRecordOperation.h"
#import "YapDatabaseCloudCoreOperationPrivate.h"

#import "YapDatabaseCloudCoreGraph.h"
#import "YapDatabaseCloudCorePipeline.h"
#import "YapDatabaseCloudCorePipelinePrivate.h"

#import "YapCache.h"
#import "YapManyToManyCache.h"

#import "sqlite3.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAPDATABASE_OWNCLOUD_CLASS_VERSION 1

static NSString * const YDBCloudCore_DiryMappingMetadata_NeedsRemove = @"NeedsRemove";
static NSString * const YDBCloudCore_DiryMappingMetadata_NeedsInsert = @"NeedsInsert";

static NSString *const changeset_key_modifiedMappings = @"modifiedMappings"; // YapManyToManyCache: rowid <-> URI
static NSString *const changeset_key_modifiedTags     = @"modifiedTags";     // Dict : CK -> (changeTag || NSNull)
static NSString *const changeset_key_reset            = @"reset";

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudCore () {
@public
	
	YapDatabaseCloudCoreHandler *handler;
	YapDatabaseCloudCoreDeleteHandler *deleteHandler;
	YapDatabaseCloudCoreMergeRecordBlock mergeRecordBlock;
	
	YDBCloudCoreOperationSerializer operationSerializer;
	YDBCloudCoreOperationDeserializer operationDeserializer;
	
	NSString *versionTag;
	YapDatabaseCloudCoreOptions *options;
}

- (NSString *)pipelineTableName;
- (NSString *)queueTableName;
- (NSString *)mappingTableName;
- (NSString *)tagTableName;

- (NSArray *)registeredPipelineNamesExcludingDefault;

- (void)restorePipelineRowids:(NSDictionary *)rowidsToPipelineName;
- (void)restorePipelineGraphs:(NSDictionary *)sortedGraphsPerPipeline;

- (void)commitAddedGraphs:(NSDictionary<NSString *, YapDatabaseCloudCoreGraph *> *)addedGraphs
       insertedOperations:(NSDictionary<NSString *, NSDictionary *> *)insertedOperations
       modifiedOperations:(NSDictionary<NSUUID *, YapDatabaseCloudCoreOperation *> *)modifiedOperations;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudCoreConnection () {
@protected
	
	id sharedKeySetForInternalChangeset;
	
@public
	
	__strong YapDatabaseCloudCore *parent;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	NSMutableDictionary<NSString *, NSMutableArray<YapDatabaseCloudCoreOperation *> *> *operations_added;
	NSMutableDictionary<NSString *, NSMutableDictionary *> *operations_inserted;
	NSMutableDictionary<NSUUID *, YapDatabaseCloudCoreOperation *> *operations_modified;
	
	// operations_added    : pipelineName  -> array of added operations (new ops, new graph)
	// operations_inserted : pipelineName  -> dictionary<graphIdx, @[ inserted ops ]> (new ops, previous graph)
	// operations_modified : operationUUID -> modified operation (replacement ops, previous graph)
	
	NSMutableArray *operations_block; // parameter to YapDatabaseCloudCoreHandler block
	
	NSMutableDictionary<NSString *, YapDatabaseCloudCoreGraph *> *graphs_added;
	
	YapManyToManyCache *pendingAttachRequests; // unlimited cache size
	
	YapManyToManyCache *cleanMappingCache;
	YapManyToManyCache *dirtyMappingInfo;  // unlimited cache size
	
	YapCache<YapCollectionKey*, id> *tagCache;
	NSMutableDictionary<YapCollectionKey*, id> *dirtyTags;
	
	BOOL reset;
}

- (id)initWithParent:(YapDatabaseCloudCore *)inParent databaseConnection:(YapDatabaseConnection *)inDbC;

- (sqlite3_stmt *)pipelineTable_insertStatement;
- (sqlite3_stmt *)pipelineTable_removeStatement;
- (sqlite3_stmt *)pipelineTable_removeAllStatement;

- (sqlite3_stmt *)queueTable_insertStatement;
- (sqlite3_stmt *)queueTable_modifyStatement;
- (sqlite3_stmt *)queueTable_removeStatement;
- (sqlite3_stmt *)queueTable_removeAllStatement;

- (sqlite3_stmt *)mappingTable_insertStatement;
- (sqlite3_stmt *)mappingTable_fetchStatement;
- (sqlite3_stmt *)mappingTable_fetchForRowidStatement;
- (sqlite3_stmt *)mappingTable_fetchForCloudURIStatement;
- (sqlite3_stmt *)mappingTable_removeStatement;
- (sqlite3_stmt *)mappingTable_removeAllStatement;

- (sqlite3_stmt *)tagTable_setStatement;
- (sqlite3_stmt *)tagTable_fetchStatement;
- (sqlite3_stmt *)tagTable_removeForBothStatement;
- (sqlite3_stmt *)tagTable_removeForCloudURIStatement;
- (sqlite3_stmt *)tagTable_removeAllStatement;

- (void)postCommitCleanup;
- (void)postRollbackCleanup;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudCoreTransaction () {
@protected

	__unsafe_unretained YapDatabaseCloudCoreConnection *parentConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
}

- (id)initWithParentConnection:(YapDatabaseCloudCoreConnection *)parentConnection
           databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudCoreHandler () {
@public
	
	YapDatabaseCloudCoreHandlerBlock block;
	YapDatabaseBlockType             blockType;
	YapDatabaseBlockInvoke           blockInvokeOptions;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseCloudCoreDeleteHandler () {
@public
	
	YapDatabaseCloudCoreDeleteHandlerBlock block;
	YapDatabaseBlockType                   blockType;
}

@end
