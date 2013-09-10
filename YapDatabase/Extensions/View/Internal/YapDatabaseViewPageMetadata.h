#import <Foundation/Foundation.h>

/**
 * This class stores the metadata about each "page" in the view.
 * 
 * That is, a "page" is a subset of the array of rowids in a group.
 * The metadata does the following:
 * 
 * - stores the associated group
 * - keeps the pages ordered (via prevPageKey).
 * - keeps the count on hand to make it easier to find a particular index
 * 
 * This class is designed only to store the metadata in RAM.
 * When the metadata is stored to disk, the individual ivars have an associated column.
**/
@interface YapDatabaseViewPageMetadata : NSObject <NSCopying> {
@public
	
	NSString * pageKey;
	NSString * prevPageKey;
	NSString * group;
	NSUInteger count;
	
	BOOL isNew; // Is NOT copied. Relevant only to connection.
}

@end
