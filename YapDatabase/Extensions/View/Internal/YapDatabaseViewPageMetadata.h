#import <Foundation/Foundation.h>

@interface YapDatabaseViewPageMetadata : NSObject <NSCoding, NSCopying> {
@public
	
	NSString * pageKey;     // Transient (NOT saved to disk)
	NSString * nextPageKey; // Transient (NOT saved to disk)
	NSString * prevPageKey; // Persistent (saved to disk)
	NSString * group;       // Persistent (saved to disk)
	NSUInteger count;       // Persistent (saved to disk)
}

@end
