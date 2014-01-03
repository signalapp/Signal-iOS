#import "YapDatabaseRelationshipEdge.h"

enum {
	YDB_EdgeActionNone   = 0,
	YDB_EdgeActionInsert = 1,
	YDB_EdgeActionUpdate = 2,
	YDB_EdgeActionDelete = 3
};

enum {
	YDB_NodeActionNone               = 0,
	YDB_NodeActionSourceDeleted      = 1 << 0,
	YDB_NodeActionDestinationDeleted = 1 << 1
};


@interface YapDatabaseRelationshipEdge () {
@public
	
	// Public properties.
	// Internal code should access these directly.
	
	NSString *name;
	
	NSString *sourceKey;
	NSString *sourceCollection;
	
	NSString *destinationKey;
	NSString *destinationCollection;
	
	YDB_NodeDeleteRules nodeDeleteRules;
	
	// Internal properties.
	// Internal code must access these directly.
	
	int64_t edgeRowid;
	int64_t sourceRowid;
	int64_t destinationRowid;
	
	int edgeAction;
	int nodeAction;
	
	int flags;
	
	BOOL notInDatabase;  // Used as a flag when edgeAction is YDB_EdgeActionDelete
	BOOL badDestination; // Used as a flag to avoid unneeded processing
}

- (id)initWithRowid:(int64_t)rowid name:(NSString *)name src:(int64_t)src dst:(int64_t)dst rules:(int)rules;

- (id)copyWithSourceKey:(NSString *)newSrcKey collection:(NSString *)newSrcCollection rowid:(int64_t)newSrcRowid;

@end
