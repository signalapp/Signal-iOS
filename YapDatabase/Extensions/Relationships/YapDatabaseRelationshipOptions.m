#import "YapDatabaseRelationshipOptions.h"
#import "YapDatabaseRelationshipPrivate.h"


@implementation YapDatabaseRelationshipOptions

@synthesize disableYapDatabaseRelationshipNodeProtocol = disableYapDatabaseRelationshipNodeProtocol;
@synthesize allowedCollections = allowedCollections;
@synthesize destinationFilePathEncryptor;
@synthesize destinationFilePathDecryptor;

- (id)init
{
	if ((self = [super init]))
	{
		disableYapDatabaseRelationshipNodeProtocol = NO;
		allowedCollections = nil;
	}
	return self;
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseRelationshipOptions *copy = [[YapDatabaseRelationshipOptions alloc] init];
	copy->disableYapDatabaseRelationshipNodeProtocol = disableYapDatabaseRelationshipNodeProtocol;
	copy->allowedCollections = allowedCollections;
	
	if (destinationFilePathEncryptor && destinationFilePathDecryptor)
	{
		copy->destinationFilePathEncryptor = destinationFilePathEncryptor;
		copy->destinationFilePathDecryptor = destinationFilePathDecryptor;
	}
	
	return copy;
}

@end
