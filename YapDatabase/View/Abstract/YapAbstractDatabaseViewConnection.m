#import "YapAbstractDatabaseViewConnection.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapAbstractDatabaseViewConnection

@synthesize abstractView = abstractView;

- (id)initWithDatabaseView:(YapAbstractDatabaseView *)parent
{
	if ((self = [super init]))
	{
		abstractView = parent;
	}
	return self;
}

- (id)newTransaction:(YapAbstractDatabaseTransaction *)databaseTransaction
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

@end
