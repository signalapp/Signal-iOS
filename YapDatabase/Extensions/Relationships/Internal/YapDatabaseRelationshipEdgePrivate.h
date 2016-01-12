#import "YapDatabaseRelationshipEdge.h"

typedef NS_OPTIONS(NSUInteger, YDB_EdgeState) {
	YDB_EdgeState_None                      = 0,
	YDB_EdgeState_DestinationFileURL        = 1 << 0, // If set, edge originally had destinationFileURL
	YDB_EdgeState_HasSourceRowid            = 1 << 1, // If set, sourceRowid lookup is done
	YDB_EdgeState_HasDestinationRowid       = 1 << 2, // If set, destinationRowid lookup is done
	YDB_EdgeState_HasDestinationFileURL     = 1 << 3, // If set, destinationFileURL has been deserialized
	YDB_EdgeState_HasEdgeRowid              = 1 << 4,
};

typedef NS_OPTIONS(NSUInteger, YDB_EdgeFlags) {
	YDB_EdgeFlags_None                      = 0,
	YDB_EdgeFlags_SourceDeleted             = 1 << 1,
	YDB_EdgeFlags_DestinationDeleted        = 1 << 2,
	YDB_EdgeFlags_BadSource                 = 1 << 3,
	YDB_EdgeFlags_BadDestination            = 1 << 4,
	YDB_EdgeFlags_EdgeNotInDatabase         = 1 << 5,
};

typedef NS_ENUM(NSInteger, YDB_EdgeAction) {
	YDB_EdgeAction_None,
	YDB_EdgeAction_Insert,
	YDB_EdgeAction_Update,
	YDB_EdgeAction_Delete
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
	
	NSURL *destinationFileURL;
	
	YDB_NodeDeleteRules nodeDeleteRules;
	
	BOOL isManualEdge;
	
	// Internal properties.
	// Internal code must access these directly.
	
	int64_t edgeRowid;
	int64_t sourceRowid;
	int64_t destinationRowid;
	
	NSData *destinationFileURLData;
	
	YDB_EdgeState  state;
	YDB_EdgeFlags  flags;
	YDB_EdgeAction action;
}

// Init directly from database row
- (id)initWithEdgeRowid:(int64_t)edgeRowid
                   name:(NSString *)name
               srcRowid:(int64_t)srcRowid
               dstRowid:(int64_t)dstRowid
                dstData:(NSData *)dstData
                  rules:(int)rules
                 manual:(BOOL)isManual;

// Copy for YapDatabaseRelationshipNode protocol
- (id)copyWithSourceKey:(NSString *)newSrcKey collection:(NSString *)newSrcCollection rowid:(int64_t)newSrcRowid;

@end
