#import "YapAbstractDatabaseView.h"
#import "YapAbstractDatabaseViewPrivate.h"


@implementation YapAbstractDatabaseView

@synthesize registeredName;

- (NSString *)tableName
{
	return [NSString stringWithFormat:@"view_%@", self.registeredName];
}

- (YapAbstractDatabaseViewConnection *)newConnection
{
	NSAssert(NO, @"Missing required override method in subclass");
	return nil;
}

@end
