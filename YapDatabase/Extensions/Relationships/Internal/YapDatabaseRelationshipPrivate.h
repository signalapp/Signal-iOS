#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseRelationship.h"
#import "YapDatabaseRelationshipOptions.h"
#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipTransaction.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the table as needed.
**/
#define YAP_DATABASE_RELATIONSHIP_CLASS_VERSION 3

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationship () {
@public

	NSString *versionTag;
	YapDatabaseRelationshipOptions *options;
}

- (NSString *)tableName;

/**
 * The dispatch queue for performing file deletion operations.
 * Note: This method is not thread-safe, as it expects to only be invoked from within a read-write transaction.
**/
- (dispatch_queue_t)fileManagerQueue;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationshipOptions () {
@public
	
	BOOL disableYapDatabaseRelationshipNodeProtocol;
	YapWhitelistBlacklist *allowedCollections;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationshipConnection () {
@public
	
	__strong YapDatabaseRelationship *relationship;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	NSMutableDictionary *protocolChanges; // key:(NSNumber *)srcRowidNumber, value:(NSMutableArray *)edges
	NSMutableDictionary *manualChanges;   // key:(NSString *)edgeName, value:(NSMutableArray *)edges
	
	NSMutableSet *inserted; // contains:(NSNumber *)rowidNumber
	
	NSMutableArray *deletedOrder; // contains:(NSNumber *)rowidNumber
	NSMutableDictionary *deletedInfo; // key:(NSNumber *)rowidNumber, value:(YapCollectionKey *)collectionKey
	
	NSMutableSet *filesToDelete;
	
//	NSMutableSet *mutatedSomething;
}

- (id)initWithRelationship:(YapDatabaseRelationship *)relationship databaseConnection:(YapDatabaseConnection *)dbc;

- (void)postRollbackCleanup;
- (void)postCommitCleanup;

- (sqlite3_stmt *)findManualEdgeStatement;
- (sqlite3_stmt *)insertEdgeStatement;
- (sqlite3_stmt *)updateEdgeStatement;
- (sqlite3_stmt *)deleteEdgeStatement;
- (sqlite3_stmt *)deleteEdgesWithNodeStatement;
- (sqlite3_stmt *)enumerateAllDstFilePathStatement;
- (sqlite3_stmt *)enumerateForSrcStatement;
- (sqlite3_stmt *)enumerateForDstStatement;
- (sqlite3_stmt *)enumerateForSrcNameStatement;
- (sqlite3_stmt *)enumerateForDstNameStatement;
- (sqlite3_stmt *)enumerateForNameStatement;
- (sqlite3_stmt *)enumerateForSrcDstStatement;
- (sqlite3_stmt *)enumerateForSrcDstNameStatement;
- (sqlite3_stmt *)countForSrcNameExcludingDstStatement;
- (sqlite3_stmt *)countForDstNameExcludingSrcStatement;
- (sqlite3_stmt *)countForNameStatement;
- (sqlite3_stmt *)countForSrcStatement;
- (sqlite3_stmt *)countForSrcNameStatement;
- (sqlite3_stmt *)countForDstStatement;
- (sqlite3_stmt *)countForDstNameStatement;
- (sqlite3_stmt *)countForSrcDstStatement;
- (sqlite3_stmt *)countForSrcDstNameStatement;
- (sqlite3_stmt *)removeAllStatement;
- (sqlite3_stmt *)removeAllProtocolStatement;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationshipTransaction () {
@protected
	
	__unsafe_unretained YapDatabaseRelationshipConnection *relationshipConnection;
	__unsafe_unretained YapDatabaseReadTransaction *databaseTransaction;
}

- (id)initWithRelationshipConnection:(YapDatabaseRelationshipConnection *)relationshipConnection
                 databaseTransaction:(YapDatabaseReadTransaction *)databaseTransaction;

@end
