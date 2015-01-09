#import "BenchmarkYapCache.h"
#import "YapCache.h"
#import "YapCollectionKey.h"

#define LOOP_COUNT 25000

#define TEST_COLLECTION_KEY 1 // 0:Key=NSString, 1:Key=YapCollectionKey


/**
 * Head-to-head stress test.
 * We generate the exact same sequence of keys, and iterate over them as fast as possible.
**/
@implementation BenchmarkYapCache

static NSMutableArray *cacheSizes;
static NSMutableArray *keys;

+ (NSString *)randomLetters:(NSUInteger)length
{
	NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz";
	NSUInteger alphabetLength = [alphabet length];
	
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	
	NSUInteger i;
	for (i = 0; i < length; i++)
	{
		unichar c = [alphabet characterAtIndex:(NSUInteger)arc4random_uniform((uint32_t)alphabetLength)];
		
		[result appendFormat:@"%C", c];
	}
	
	return result;
}

+ (void)generateKeysWithCacheSize:(NSUInteger)cacheSize targetHitPercentage:(double)hitPercentage
{
	keys = [NSMutableArray arrayWithCapacity:LOOP_COUNT];
	
	NSMutableArray *recentKeys = [NSMutableArray arrayWithCapacity:cacheSize];
	
	for (NSUInteger i = 0; i < LOOP_COUNT; i++)
	{
		NSString *key;
		
		if (arc4random_uniform(100) > (100 * hitPercentage) || [recentKeys count] == 0)
		{
			key = [self randomLetters:24];
			
			[recentKeys addObject:key];
			if ([recentKeys count] > cacheSize)
				[recentKeys removeObjectAtIndex:0];
		}
		else
		{
			NSUInteger recentIndex = (NSUInteger)arc4random_uniform((uint32_t)[recentKeys count]);
			
			key = [recentKeys objectAtIndex:recentIndex];
			
			[recentKeys removeObjectAtIndex:recentIndex];
			[recentKeys addObject:key];
		}
		
	#if TEST_COLLECTION_KEY
		YapCollectionKey *ckey = [[YapCollectionKey alloc] initWithCollection:@"" key:key];
		[keys addObject:ckey];
	#else
		[keys addObject:key];
	#endif
	}
}

+ (NSTimeInterval)testNSCache:(NSUInteger)cacheSize
{
	NSCache *cache = [[NSCache alloc] init];
	cache.countLimit = cacheSize;
	
	NSUInteger hitCount = 0;
	
	NSDate *start = [NSDate date];
	
	for (id key in keys)
	{
		if ([cache objectForKey:key] == nil)
		{
			[cache setObject:[NSNull null] forKey:key];
		}
		else
		{
			hitCount++;
		}
	}
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	double hitPercentage = (double)hitCount / (double)[keys count];
	
	NSLog(@"NSCache : elapsed = %.6f (actual hit percentage = %.2f)", elapsed, hitPercentage);
	
	return elapsed;
}

+ (NSTimeInterval)testYapCache:(NSUInteger)cacheSize
{
#if TEST_COLLECTION_KEY
	YapCache *cache = [[YapCache alloc] initWithCountLimit:cacheSize keyCallbacks:[YapCollectionKey keyCallbacks]];
	cache.allowedKeyClasses = [NSSet setWithObject:[YapCollectionKey class]];
#else
	YapCache *cache = [[YapCache alloc] initWithCountLimit:cacheSize];
	cache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
#endif
	
	
	
	NSUInteger hitCount = 0;
	
	NSDate *start = [NSDate date];
	
	for (id key in keys)
	{
		if ([cache objectForKey:key] == nil)
		{
			[cache setObject:[NSNull null] forKey:key];
		}
		else
		{
			hitCount++;
		}
	}
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	double hitPercentage = (double)hitCount / (double)[keys count];
	
	NSLog(@"YapCache: elapsed = %.6f (actual hit percentage = %.2f)", elapsed, hitPercentage);
	
	return elapsed;
}

+ (void)testWithCompletion:(dispatch_block_t)completionBlock;
{
	if ([cacheSizes count] == 0)
	{
		// Done!
		completionBlock();
		return;
	}
	
	NSUInteger cacheSize = [[cacheSizes objectAtIndex:0] unsignedIntegerValue];
	[cacheSizes removeObjectAtIndex:0];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@" \n\n\n ");
		NSLog(@"====================================================");
		NSLog(@"CACHE SIZE: %lu, TARGET HIT PERCENTAGE: 5%% \n\n", (unsigned long)cacheSize);
		
		NSTimeInterval ns = 0.0;
		NSTimeInterval yap = 0.0;
		
		[self generateKeysWithCacheSize:cacheSize targetHitPercentage:0.05];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		
		ns  = ns  / 3.0;
		yap = yap / 3.0;
		
		if (ns < yap)
			NSLog(@"Winner: NSCache (%.2f%% faster) \n ", ((1.0-(ns/yap))*100) );
		else
			NSLog(@"Winner: YapCache (%.2f%% faster) \n ", ((1.0-(yap/ns))*100) );
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"CACHE SIZE: %lu, TARGET HIT PERCENTAGE: 25%% \n\n", (unsigned long)cacheSize);
		
		NSTimeInterval ns = 0.0;
		NSTimeInterval yap = 0.0;
		
		[self generateKeysWithCacheSize:cacheSize targetHitPercentage:0.25];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		
		ns  = ns  / 3.0;
		yap = yap / 3.0;
		
		if (ns < yap)
			NSLog(@"Winner: NSCache (%.2f%% faster) \n ", ((1.0-(ns/yap))*100) );
		else
			NSLog(@"Winner: YapCache (%.2f%% faster) \n ", ((1.0-(yap/ns))*100) );
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"CACHE SIZE: %lu, TARGET HIT PERCENTAGE: 50%% \n\n", (unsigned long)cacheSize);
		
		NSTimeInterval ns = 0.0;
		NSTimeInterval yap = 0.0;
		
		[self generateKeysWithCacheSize:cacheSize targetHitPercentage:0.5];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		
		ns  = ns  / 3.0;
		yap = yap / 3.0;
		
		if (ns < yap)
			NSLog(@"Winner: NSCache (%.2f%% faster) \n ", ((1.0-(ns/yap))*100) );
		else
			NSLog(@"Winner: YapCache (%.2f%% faster) \n ", ((1.0-(yap/ns))*100) );
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"CACHE SIZE: %lu, TARGET HIT PERCENTAGE: 75%% \n\n", (unsigned long)cacheSize);
		
		NSTimeInterval ns = 0.0;
		NSTimeInterval yap = 0.0;
		
		[self generateKeysWithCacheSize:cacheSize targetHitPercentage:0.75];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		
		ns  = ns  / 3.0;
		yap = yap / 3.0;
		
		if (ns < yap)
			NSLog(@"Winner: NSCache (%.2f%% faster) \n ", ((1.0-(ns/yap))*100) );
		else
			NSLog(@"Winner: YapCache (%.2f%% faster) \n ", ((1.0-(yap/ns))*100) );
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"CACHE SIZE: %lu, TARGET HIT PERCENTAGE: 95%% \n\n", (unsigned long)cacheSize);
		
		NSTimeInterval ns = 0.0;
		NSTimeInterval yap = 0.0;
		
		[self generateKeysWithCacheSize:cacheSize targetHitPercentage:0.95];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		ns  += [self testNSCache:cacheSize];
		yap += [self testYapCache:cacheSize];
		
		ns  = ns  / 3.0;
		yap = yap / 3.0;
		
		if (ns < yap)
			NSLog(@"Winner: NSCache (%.2f%% faster) \n ", ((1.0-(ns/yap))*100) );
		else
			NSLog(@"Winner: YapCache (%.2f%% faster) \n ", ((1.0-(yap/ns))*100) );
		
		NSLog(@"====================================================");
	});
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		// Run the next test (with a different cacheSize)
		[self testWithCompletion:completionBlock];
	});
}

+ (void)runTestsWithCompletion:(dispatch_block_t)completionBlock
{
	// Run test for each of the cache sizes listed below
	
	cacheSizes = [@[ @(40), @(100), @(500), @(1000), @(5000) ] mutableCopy];
	[self testWithCompletion:completionBlock];
}

@end
