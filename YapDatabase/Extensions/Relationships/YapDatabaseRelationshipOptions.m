#import "YapDatabaseRelationshipOptions.h"
#import "YapDatabaseRelationshipPrivate.h"


@implementation YapDatabaseRelationshipOptions

@synthesize disableYapDatabaseRelationshipNodeProtocol = disableYapDatabaseRelationshipNodeProtocol;
@synthesize allowedCollections = allowedCollections;

- (id)init
{
	if ((self = [super init]))
	{
		disableYapDatabaseRelationshipNodeProtocol = NO;
		allowedCollections = nil;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseRelationshipOptions *copy = [[YapDatabaseRelationshipOptions alloc] init];
	copy->disableYapDatabaseRelationshipNodeProtocol = disableYapDatabaseRelationshipNodeProtocol;
	copy->allowedCollections = allowedCollections;
	
	return copy;
}

@end
