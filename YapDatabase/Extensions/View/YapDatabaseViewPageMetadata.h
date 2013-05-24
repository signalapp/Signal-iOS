#import <Foundation/Foundation.h>

@interface YapDatabaseViewPageMetadata : NSObject <NSCoding, NSCopying> {
@public
	
	// Transient (not saved to disk)
	NSString *pageKey;
	
	// Persistent (saved to disk)
	NSString * nextPageKey;
	NSString * group;
	NSUInteger count;
}

@end
