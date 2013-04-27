#import "YapAbstractDatabaseView.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapAbstractDatabaseView

@synthesize registeredName;

- (YapAbstractDatabaseViewConnection *)newConnection
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

@end
