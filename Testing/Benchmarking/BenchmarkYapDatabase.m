#import "BenchmarkYapDatabase.h"
#import "YapDatabase.h"
#import "YapDatabaseConnection.h"

#import <stdlib.h>

@implementation BenchmarkYapDatabase

static YapDatabase *database;
static YapDatabaseConnection *connection;

static NSMutableArray *keys;

+ (NSString *)databaseName
{
	return @"BenchmarkYapDatabase.sqlite";
}

+ (NSString *)databasePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	return [baseDir stringByAppendingPathComponent:[self databaseName]];
}

+ (NSString *)randomLetters:(NSUInteger)length
{
	NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz";
	NSUInteger alphabetLength = [alphabet length];
	
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	
	NSUInteger i;
	for (i = 0; i < length; i++)
	{
		uint32_t randomIndex = arc4random_uniform((uint32_t)alphabetLength);
		unichar c = [alphabet characterAtIndex:(NSUInteger)randomIndex];
		
		[result appendFormat:@"%C", c];
	}
	
	return result;
}

+ (void)generateKeys:(NSUInteger)count
{
	if (keys == nil)
		keys = [[NSMutableArray alloc] initWithCapacity:count];
	else
		[keys removeAllObjects];
	
	for (NSUInteger i = 0; i < count; i++)
	{
		[keys addObject:[self randomLetters:24]];
	}
}

+ (void)populateDatabase
{
	NSDate *start = [NSDate date];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (NSString *key in keys)
		{
			// For now, use key for object.
			// Later we need to test with bigger objects with more serialization overhead.
			
			[transaction setObject:key forKey:key];
		}
	}];
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"Populate database: total time: %.6f, added items: %lu", elapsed, (unsigned long)[keys count]);
}

+ (void)enumerateDatabase
{
	NSDate *start = [NSDate date];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[transaction enumerateKeysUsingBlock:^(NSString *key, BOOL *stop) {
			
			// Nothing to do, just testing overhead
		}];
	}];
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"Enumerate keys: total time: %.6f, database count: %lu", elapsed, (unsigned long)[keys count]);
	
	start = [NSDate date];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[transaction enumerateKeysAndObjectsUsingBlock:^(NSString *key, id object, BOOL *stop) {
			
			// Nothing to do, just testing overhead
		}];
	}];
	
	elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"Enumerate keys & objects: total time: %.6f, database count: %lu", elapsed, (unsigned long)[keys count]);
}

+ (void)fetchValuesInLoop:(NSUInteger)loopCount withCacheHitPercentage:(float)hitPercentage
{
	// Generate a random list of keys to fetch which satisfies the requested hit percentage
	
	NSUInteger cacheSize = connection.objectCacheLimit;
	NSAssert(cacheSize < loopCount, @"Can't satisfy hitPercentage because cacheSize is too big");
	
	NSMutableOrderedSet *keysInCache = [NSMutableOrderedSet orderedSetWithCapacity:cacheSize];
	NSMutableArray *keysToFetch = [NSMutableArray arrayWithCapacity:loopCount];
	
	for (NSUInteger i = 0; i < loopCount; i++)
	{
		float rand = arc4random_uniform(1000) / 1000.0F;
		
		if ((rand < hitPercentage) && ([keysInCache count] > 0))
		{
			// Pick a random key in the cache
			
			uint32_t randomIndex = arc4random_uniform((uint32_t)[keysInCache count]);
			NSString *key = [keysInCache objectAtIndex:(NSUInteger)randomIndex];
			
			[keysToFetch addObject:key];
			
			[keysInCache removeObject:key];
			[keysInCache insertObject:key atIndex:0];
		}
		else
		{
			// Pick a random key NOT in the cache
			
			BOOL found = NO;
			do {
				
				uint32_t randomIndex = arc4random_uniform((uint32_t)[keys count]);
				NSString *key = [keys objectAtIndex:(NSUInteger)randomIndex];
				
				if (![keysInCache containsObject:key])
				{
					found = YES;
					
					[keysToFetch addObject:key];
					
					[keysInCache insertObject:key atIndex:0];
					if ([keysInCache count] > cacheSize) {
						[keysInCache removeObjectAtIndex:cacheSize];
					}
				}
				
			} while (!found);
		}
	}
	
	// Execute fetches
	
	NSDate *start = [NSDate date];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (NSString *key in keysToFetch)
		{
			(void)[transaction objectForKey:key];
		}
	}];
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	
	NSLog(@"Fetch %lu random objs: total time: %.6f, average time per key: %.6f (cache hit %%: %.2f)",
		  (unsigned long)loopCount, elapsed, (elapsed / loopCount), hitPercentage);
}

+ (void)readTransactionOverhead:(NSUInteger)loopCount
{
	NSDate *start = [NSDate date];
	
	for (NSUInteger i = 0; i < loopCount; i++)
	{
		[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			// Nothing to do, just testing overhead
		}];
	}
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"ReadOnly transaction overhead : %.8f", (elapsed / loopCount));
}

+ (void)readWriteTransactionOverhead:(NSUInteger)loopCount
{
	NSDate *start = [NSDate date];
	
	for (NSUInteger i = 0; i < loopCount; i++)
	{
		[connection readWriteWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			// Nothing to do, just testing overhead
		}];
	}
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"ReadWrite transaction overhead: %.8f", (elapsed / loopCount));
}

+ (void)removeAllValues
{
	NSDate *start = [NSDate date];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeAllObjects];
	}];
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"Remove all transaction: total time: %.6f", elapsed);
}

+ (void)startTests
{
	NSString *databasePath = [self databasePath];
	
	// Delete old database file (if exists)
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	
	// Create database
	database = [[YapDatabase alloc] initWithPath:databasePath];
	
	// Create database connection (can have multiple for concurrency)
	connection = [database newConnection];
	connection.objectCacheLimit = 250; // default size
	
	// Setup
	[self generateKeys:1000];
	
	// Run tests
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@" \n\n\n ");
		NSLog(@"====================================================");
		NSLog(@"POPULATE DATABASE");
		
		[self populateDatabase];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"ENUMERATE DATABASE");
		
		[self enumerateDatabase];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"FETCH DATABASE");
		
		[self fetchValuesInLoop:1000 withCacheHitPercentage:0.05];
		[self fetchValuesInLoop:1000 withCacheHitPercentage:0.25];
		[self fetchValuesInLoop:1000 withCacheHitPercentage:0.50];
		[self fetchValuesInLoop:1000 withCacheHitPercentage:0.75];
		[self fetchValuesInLoop:1000 withCacheHitPercentage:0.95];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"TRANSACTION OVERHEAD");
		
		[self readTransactionOverhead:1000];
		[self readWriteTransactionOverhead:1000];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"REMOVE ALL");
		
		[self removeAllValues];
		
		NSLog(@"====================================================");
	});
}

@end
