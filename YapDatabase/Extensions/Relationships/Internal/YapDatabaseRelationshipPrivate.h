#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"

#import "YapDatabaseRelationship.h"
#import "YapDatabaseRelationshipConnection.h"
#import "YapDatabaseRelationshipTransaction.h"

#import "YapDatabaseExtensionPrivate.h"
#import "YapCache.h"

/**
 * This version number is stored in the yap2 table.
 * If there is a major re-write to this class, then the version number will be incremented,
 * and the class can automatically rebuild the tables as needed.
**/
#define YAP_DATABASE_RELATIONSHIP_CLASS_VERSION 1


@interface YapDatabaseRelationship () {
@public

	int version;
	
	// options ???
}

- (NSString *)tableName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseRelationshipConnection () {
@public
	
	__strong YapDatabaseRelationship *relationship;
	__unsafe_unretained YapDatabaseConnection *databaseConnection;
	
	YapCache *cache;
	
	NSMutableDictionary *pendingInserts;
	NSMutableDictionary *pendingDeletes;
	NSMutableDictionary *pendingUpdates;
	NSMutableDictionary *pendingOrphans;
}

- (id)initWithRelationship:(YapDatabaseRelationship *)relationship databaseConnection:(YapDatabaseConnection *)dbc;

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
