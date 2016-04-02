#import "YapCollectionKey.h"
#import "YapMurmurHash.h"


@implementation YapCollectionKey
{
	// When these objects are stored in a dictionary (as the key), the hash method is invoked extremely often.
	// And when these objects are stored in a changeset dictionary,
	// then processing code invokes the isEqual method extremely often.
	//
	// So we pre-calculate the hash, and use it to optimize the isEqual method.
	// This decision was made after significant profiling.
	
	NSUInteger hash;
}

@synthesize collection = collection;
@synthesize key = key;

- (id)initWithCollection:(NSString *)aCollection key:(NSString *)aKey
{
	if ((self = [super init]))
	{
		if (aCollection == nil)
			collection = @"";
		else
			collection = [aCollection copy]; // copy == retain if aCollection is immutable
		
		if (aKey == nil)
			return nil;
		else
			key = [aKey copy];               // copy == retain if aKey is immutable
		
		hash = YapMurmurHash2([collection hash], [key hash]);
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		collection = [decoder decodeObjectForKey:@"collection"];
		key        = [decoder decodeObjectForKey:@"key"];
		
		hash = YapMurmurHash2([collection hash], [key hash]);
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:collection forKey:@"collection"];
	[coder encodeObject:key        forKey:@"key"];
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	return self; // Immutable
}

- (BOOL)isEqualToCollectionKey:(YapCollectionKey *)collectionKey
{
	if (hash != collectionKey->hash)
		return NO;
	else
		return [key isEqualToString:collectionKey->key] && [collection isEqualToString:collectionKey->collection];
}

- (BOOL)isEqual:(id)obj
{
	if ([obj isMemberOfClass:[YapCollectionKey class]])
	{
		__unsafe_unretained YapCollectionKey *collectionKey = (YapCollectionKey *)obj;
		
		if (hash != collectionKey->hash)
			return NO;
		else
			return [key isEqualToString:collectionKey->key] && [collection isEqualToString:collectionKey->collection];
	}
	
	return NO;
}

BOOL YapCollectionKeyEqual(const __unsafe_unretained YapCollectionKey *ck1,
                           const __unsafe_unretained YapCollectionKey *ck2)
{
	if (ck1->hash != ck2->hash)
		return NO;
	else
		return [ck1->key isEqualToString:ck2->key] && [ck1->collection isEqualToString:ck2->collection];
}

- (NSUInteger)hash
{
	return hash;
}

CFHashCode YapCollectionKeyHash(const __unsafe_unretained YapCollectionKey *ck)
{
	return (CFHashCode)(ck->hash);
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapCollectionKey collection(%@) key(%@)>", collection, key];
}

+ (CFDictionaryKeyCallBacks)keyCallbacks
{
	CFDictionaryKeyCallBacks keyCallbacks = kCFTypeDictionaryKeyCallBacks;
	
	keyCallbacks.equal = (CFDictionaryEqualCallBack)YapCollectionKeyEqual;
	keyCallbacks.hash = (CFDictionaryHashCallBack)YapCollectionKeyHash;
	
	return keyCallbacks;
}

@end
