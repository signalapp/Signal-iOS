#import "YapDatabaseConnectionConfig.h"

static NSUInteger const DEFAULT_OBJECT_CACHE_LIMIT   = 250;
static NSUInteger const DEFAULT_METADATA_CACHE_LIMIT = 250;


@implementation YapDatabaseConnectionConfig

@synthesize objectCacheEnabled = objectCacheEnabled;
@synthesize objectCacheLimit = objectCacheLimit;

@synthesize metadataCacheEnabled = metadataCacheEnabled;
@synthesize metadataCacheLimit = metadataCacheLimit;

@synthesize objectPolicy = objectPolicy;
@synthesize metadataPolicy = metadataPolicy;

#if TARGET_OS_IOS || TARGET_OS_TV
@synthesize autoFlushMemoryFlags = autoFlushMemoryFlags;
#endif

- (id)init
{
	if ((self = [super init]))
	{
		objectCacheEnabled = YES;
		objectCacheLimit = DEFAULT_OBJECT_CACHE_LIMIT;
		
		metadataCacheEnabled = YES;
		metadataCacheLimit = DEFAULT_METADATA_CACHE_LIMIT;
		
		objectPolicy = YapDatabasePolicyContainment;
		metadataPolicy = YapDatabasePolicyContainment;
		
		#if TARGET_OS_IOS || TARGET_OS_TV
		autoFlushMemoryFlags = YapDatabaseConnectionFlushMemoryFlags_All;
		#endif
	}
	return self;
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseConnectionConfig *copy = [[[self class] alloc] init];
	
	copy->objectCacheEnabled = objectCacheEnabled;
	copy->objectCacheLimit = objectCacheLimit;
	
	copy->metadataCacheEnabled = metadataCacheEnabled;
	copy->metadataCacheLimit = metadataCacheLimit;
	
	copy->objectPolicy = objectPolicy;
	copy->metadataPolicy = metadataPolicy;
	
	#if TARGET_OS_IOS || TARGET_OS_TV
	copy->autoFlushMemoryFlags = autoFlushMemoryFlags;
	#endif
	
	return copy;
}

- (void)setObjectPolicy:(YapDatabasePolicy)newObjectPolicy
{
	// sanity check
	switch (newObjectPolicy)
	{
		case YapDatabasePolicyContainment :
		case YapDatabasePolicyShare       :
		case YapDatabasePolicyCopy        : objectPolicy = newObjectPolicy; break;
		default                           : objectPolicy = YapDatabasePolicyContainment; // revert to default
	}
}

- (void)setMetadataPolicy:(YapDatabasePolicy)newMetadataPolicy
{
	// sanity check
	switch (newMetadataPolicy)
	{
		case YapDatabasePolicyContainment :
		case YapDatabasePolicyShare       :
		case YapDatabasePolicyCopy        : metadataPolicy = newMetadataPolicy; break;
		default                           : metadataPolicy = YapDatabasePolicyContainment; // revert to default
	}
}

@end
