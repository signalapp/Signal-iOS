#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"
#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"

@class YapCache;


@interface YapDatabaseView () {
@public
	YapDatabaseViewFilterBlock filterBlock;
	YapDatabaseViewSortBlock sortBlock;
	
	YapDatabaseViewBlockType filterBlockType;
	YapDatabaseViewBlockType sortBlockType;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewConnection () {
@public
	
	NSData *(^serializer)(id object);
	id (^deserializer)(NSData *);
	
	NSMutableArray *hashPages;
	NSMutableDictionary *keyPagesDict;
	
	YapCache *cache;
}

- (BOOL)isOpen;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewHashPage : NSObject <NSCoding> {
@public
	
	// Transient (not saved to disk)
	NSString *key;
	
	// Persistent (saved to disk)
	NSString *nextKey;
	NSUInteger firstHash;
	NSUInteger lastHash;
	NSUInteger count;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface YapDatabaseViewKeyPage : NSObject <NSCoding> {
@public
	
	// Transient (not saved to disk)
	NSString *key;
	
	// Persistent (saved to disk)
	NSString *nextKey;
	NSUInteger section;
	NSUInteger count;
}

@end
