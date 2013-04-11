#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewPrivate.h"
#import "YapAbstractDatabaseViewPrivate.h"
#import "YapCache.h"


@implementation YapDatabaseViewConnection

- (id)initWithDatabaseView:(YapAbstractDatabaseView *)parent
{
	if ((self = [super initWithDatabaseView:parent]))
	{
		cache = [[YapCache alloc] init];
	}
	return self;
}

/**
 * Required override method from YapAbstractDatabaseViewConnection.
**/
- (id)newTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	return [[YapDatabaseViewTransaction alloc] initWithViewConnection:self
	                                              databaseTransaction:databaseTransaction];
}

- (BOOL)isOpen
{
	return (hashPages && keyPagesDict);
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseViewHashPage

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// Note: 'key' is transient
		
		nextKey = [decoder decodeObjectForKey:@"nextKey"];
		firstHash = [decoder decodeIntegerForKey:@"firstHash"];
		lastHash = [decoder decodeIntegerForKey:@"lastHash"];
		count = [decoder decodeIntegerForKey:@"count"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	// Note: 'key' is transient
	
	[coder encodeObject:nextKey forKey:@"nextKey"];
	[coder encodeInteger:firstHash forKey:@"firstHash"];
	[coder encodeInteger:lastHash forKey:@"lastHash"];
	[coder encodeInteger:count forKey:@"count"];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseViewKeyPage

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// Note: 'key' is transient
		
		nextKey = [decoder decodeObjectForKey:@"nextKey"];
		section = [decoder decodeIntegerForKey:@"section"];
		count = [decoder decodeIntegerForKey:@"count"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	// Note: 'key' is transient
	
	[coder encodeObject:nextKey forKey:@"nextKey"];
	[coder encodeInteger:section forKey:@"section"];
	[coder encodeInteger:count forKey:@"count"];
}

@end
