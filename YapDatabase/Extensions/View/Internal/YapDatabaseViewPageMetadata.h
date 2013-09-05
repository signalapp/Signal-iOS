#import <Foundation/Foundation.h>

/**
 * This class handles the metadata that is stored about each "page" in the view.
 * 
 * That is, a "page" is a subset of the array of rowids in a group.
 * The metadata does the following:
 * 
 * - stores the associated group
 * - keeps the pages ordered (via prevPageKey & nextPageKey).
 * - keeps the count on hand to make it easier to find a particular index
**/
@interface YapDatabaseViewPageMetadata : NSObject <NSCoding, NSCopying> {
@public
	
	NSString * pageKey;     // Transient (NOT saved to disk)
	NSString * nextPageKey; // Transient (NOT saved to disk)
	NSString * prevPageKey; // Persistent (saved to disk)
	NSString * group;       // Persistent (saved to disk)
	NSUInteger count;       // Persistent (saved to disk)
}

@end
