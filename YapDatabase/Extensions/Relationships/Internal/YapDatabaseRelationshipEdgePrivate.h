#import "YapDatabaseRelationshipEdge.h"

enum {
	YDB_EdgeActionNone   = 0,
	YDB_EdgeActionInsert = 1,
	YDB_EdgeActionUpdate = 2,
	YDB_EdgeActionDelete = 3
};

enum {
	YDB_FlagsNone                        = 0,
	YDB_FlagsSourceDeleted               = 1 << 0,
	YDB_FlagsDestinationDeleted          = 1 << 1,
	YDB_FlagsBadSource                   = 1 << 2,
	YDB_FlagsBadDestination              = 1 << 3,
	YDB_FlagsSourceLookupSuccessful      = 1 << 4,
	YDB_FlagsDestinationLookupSuccessful = 1 << 5,
	YDB_FlagsNotInDatabase               = 1 << 6,
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
	
	NSString *destinationFilePath;
	
	YDB_NodeDeleteRules nodeDeleteRules;
	
	BOOL isManualEdge;
	
	// Internal properties.
	// Internal code must access these directly.
	
	int64_t edgeRowid;
	int64_t sourceRowid;
	int64_t destinationRowid;
	
	int edgeAction;
	int flags;
}

// Init directly from database row
- (id)initWithRowid:(int64_t)rowid
               name:(NSString *)name
                src:(int64_t)src
                dst:(int64_t)dst
              rules:(int)rules
             manual:(BOOL)isManual;

// Init directly from database row
- (id)initWithRowid:(int64_t)rowid
               name:(NSString *)name
                src:(int64_t)src
        dstFilePath:(NSString *)dstFilePath
              rules:(int)rules
             manual:(BOOL)isManual;

// Copy for YapDatabaseRelationshipNode protocol
- (id)copyWithSourceKey:(NSString *)newSrcKey collection:(NSString *)newSrcCollection rowid:(int64_t)newSrcRowid;

@end
