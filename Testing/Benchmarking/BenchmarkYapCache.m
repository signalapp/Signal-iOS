#import "BenchmarkYapCache.h"
#import "YapCache.h"

#define LOOP_COUNT 25000


@implementation BenchmarkYapCache

static NSMutableArray *keys_kv;
static NSMutableArray *keys_ckv;
static NSMutableArray *keysOrder;

static NSMutableArray *cacheSizes;

+ (NSString *)randomLetters:(NSUInteger)length
{
	NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz";
	NSUInteger alphabetLength = [alphabet length];
	
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	
	NSUInteger i;
	for (i = 0; i < length; i++)
	{
		unichar c = [alphabet characterAtIndex:arc4random_uniform(alphabetLength)];
		
		[result appendFormat:@"%C", c];
	}
	
	return result;
}

+ (void)generateKeysWithCacheSize:(NSUInteger)cacheSize hitPercentage:(double)hitPercentage
{
	keys_kv = nil;
	keys_ckv = nil;
	keysOrder = nil;
	
	NSUInteger keysCount = (cacheSize / hitPercentage);
	keys_kv = [NSMutableArray arrayWithCapacity:keysCount];
	keys_ckv = [NSMutableArray arrayWithCapacity:keysCount];
	
	for (NSUInteger i = 0; i < keysCount; i++)
	{
		NSString *key = [self randomLetters:24];
		YapCacheCollectionKey *ckey = [[YapCacheCollectionKey alloc] initWithCollection:@"" key:key];
		
		[keys_kv addObject:key];
		[keys_ckv addObject:ckey];
	}
	
	NSUInteger loopCount = LOOP_COUNT;
	keysOrder = [NSMutableArray arrayWithCapacity:loopCount];
	
	for (NSUInteger i = 0; i < LOOP_COUNT; i++)
	{
		[keysOrder addObject:@(arc4random_uniform(keysCount))];
	}
}

+ (void)runTest1:(NSUInteger)cacheSize
{
	Class keyClass = [YapCacheCollectionKey class];
	
	YapThreadUnsafeCache *cache = [[YapThreadUnsafeCache alloc] initWithKeyClass:keyClass countLimit:cacheSize];
//	YapThreadSafeCache *cache = [[YapThreadUnsafeCache alloc] initWithKeyClass:keyClass countLimit:cacheSize];
	
	NSDate *start = [NSDate date];
	
	for (NSNumber *number in keysOrder)
	{
		id cacheKey = [keys_ckv objectAtIndex:[number unsignedIntegerValue]];
		
		[cache setObject:[NSNull null] forKey:cacheKey];
	}
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"%@: elapsed = %.6f (loop=%d, cache=%d, hit=%d, evict=%d)",
	      NSStringFromSelector(_cmd), elapsed, LOOP_COUNT, cacheSize, cache.hitCount, cache.evictionCount);
}

+ (void)runTest2:(NSUInteger)cacheSize
{
	Class keyClass = [NSString class];
	
	YapThreadUnsafeCache *cache = [[YapThreadUnsafeCache alloc] initWithKeyClass:keyClass countLimit:cacheSize];
//	YapThreadSafeCache *cache = [[YapThreadUnsafeCache alloc] initWithKeyClass:keyClass countLimit:cacheSize];
	
	NSDate *start = [NSDate date];
	
	for (NSNumber *number in keysOrder)
	{
		NSString *key = [keys_kv objectAtIndex:[number unsignedIntegerValue]];
		
		[cache setObject:[NSNull null] forKey:key];
	}
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"%@: elapsed = %.6f (loop=%d, cache=%d, hit=%d, evict=%d)",
	      NSStringFromSelector(_cmd), elapsed, LOOP_COUNT, cacheSize, cache.hitCount, cache.evictionCount);
}

+ (void)runTests
{
	if ([cacheSizes count] == 0) return;
	
	NSUInteger cacheSize = [[cacheSizes objectAtIndex:0] unsignedIntegerValue];
	[cacheSizes removeObjectAtIndex:0];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"====================================================");
		NSLog(@"====================================================");
		NSLog(@"CACHE SIZE: %lu\n\n", (unsigned long)cacheSize);
		
		[self generateKeysWithCacheSize:cacheSize hitPercentage:0.05];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		[self generateKeysWithCacheSize:cacheSize hitPercentage:0.25];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		[self generateKeysWithCacheSize:cacheSize hitPercentage:0.5];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		[self generateKeysWithCacheSize:cacheSize hitPercentage:0.75];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		[self generateKeysWithCacheSize:cacheSize hitPercentage:0.95];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		[self runTest1:cacheSize];
		[self runTest2:cacheSize];
		NSLog(@"====================================================");
	});
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		// Run the next test (with a different cacheSize)
		[self runTests];
	});
}

+ (void)startTests
{
	cacheSizes = [@[ @(40), @(100), @(500), @(1000) ] mutableCopy];
	
	[self runTests];
}

@end
