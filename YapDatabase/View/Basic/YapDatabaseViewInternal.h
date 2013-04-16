#import <Foundation/Foundation.h>

@interface YapDatabaseViewPageMetadata : NSObject <NSCoding, NSCopying> {
@public
	
	// Transient (not saved to disk)
	NSString *pageKey;
	
	// Persistent (saved to disk)
	NSString *nextPageKey;
	NSUInteger section;
	NSUInteger count;
}

@end
