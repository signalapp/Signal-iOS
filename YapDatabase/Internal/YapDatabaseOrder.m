#import "YapDatabaseOrder.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#if DEBUG && robbie_hanson
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_VERBOSE;
#elif DEBUG
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbFileLogLevel = YDB_LOG_LEVEL_WARN;
#endif

#define DEFAULT_MAX_PAGE_SIZE       100
#define DEFAULT_MAX_PAGES_IN_MEMORY 0

#define KEY_PAGE_INFOS    @"order_infos"
#define KEY_MAX_PAGE_SIZE @"order_max_page_size"

#define NO_DUPLICATES_OPTIMIZATION 0


@interface YapDatabasePageInfo : NSObject <NSCoding, NSCopying> {
@public
	NSString *pageKey;   // Persistent
	NSUInteger pageSize; // Persistent
	
	NSDate *lastAccess;  // Non-persistent. Only set if corresponding page is loaded into memory.
	                     // Represents last time page was accessed.
	
	NSUInteger tempPageIndex;  // Used only for temp marking within scope
	NSUInteger tempPageOffset; // Used only for temp marking within scope
}

@end

@implementation YapDatabasePageInfo

+ (NSString *)generatePageKey
{
	NSString *key = nil;
	
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	if (uuid)
	{
		key = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
		CFRelease(uuid);
	}
	
	return key;
}

- (id)init
{
	if ((self = [super init]))
	{
		pageKey = [YapDatabasePageInfo generatePageKey];
		pageSize = 0;
	}
	return self;
}

- (id)initWithPageKey:(NSString *)inPageKey pageSize:(NSUInteger)inPageSize
{
	if ((self = [super init]))
	{
		pageKey = inPageKey;
		pageSize = inPageSize;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		pageKey = [decoder decodeObjectForKey:@"pageKey"];
		pageSize = [decoder decodeIntegerForKey:@"pageSize"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:pageKey forKey:@"pageKey"];
	[coder encodeInteger:pageSize forKey:@"pageSize"];
	
	// lastAccess is not persisted as it relates to memory access info.
	// temp variables are not persisted as they are temporary.
}

- (id)copyWithZone:(NSZone *)zone
{
	// The copy method is used when cloning or resetting a YapDatabaseOrder object.
	
	return [[YapDatabasePageInfo alloc] initWithPageKey:pageKey pageSize:pageSize];
	
	// lastAccess is not copied as it relates to memory access info, and the pages are reset in a clone or reset.
	// temp variables are not copied as they are temporary.
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YapDatabasePageInfo %p: pageKey=%@, pageSize=%lu, inRAM=%@>",
	                        self, pageKey, (unsigned long)pageSize, (lastAccess == nil ? @"NO" : @"YES")];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseOrder
{
	NSUInteger maxPageSize;
	NSUInteger maxPagesInMemory;
	
	NSMutableArray *pageInfos;  // Array of YapDatabasePageInfo's
	NSMutableDictionary *pages; // Key=PageKey, Value=Page (array of strings representing object keys)
	
	NSMutableSet *dirtyPageKeys;
	BOOL allKeysRemoved;
}

@synthesize userInfo;

- (id)init
{
	return [self initWithUserInfo:nil];
}

- (id)initWithUserInfo:(id)inUserInfo
{
	if ((self = [super init]))
	{
		// Initialize ivars
		
		self.userInfo = inUserInfo;
		
		maxPageSize = DEFAULT_MAX_PAGE_SIZE;
		maxPagesInMemory = DEFAULT_MAX_PAGES_IN_MEMORY;
		
		dirtyPageKeys = [[NSMutableSet alloc] init];
	}
	return self;
}

- (void)prepare:(id <YapOrderReadTransaction>)transaction
{
	// Load pageInfos array.
	// This is simply an array of metadata about the pages we have stored on disk.
	// The actual pages will be loaded from disk on demand.
	
	NSData *pageInfosData = [transaction dataForKey:KEY_PAGE_INFOS order:self];
	if (pageInfosData)
	{
		pageInfos = [NSKeyedUnarchiver unarchiveObjectWithData:pageInfosData];
	}
	
	NSUInteger pageInfosCount = [pageInfos count];
	NSUInteger pagesCapacity = (maxPagesInMemory == 0) ? pageInfosCount : MIN(maxPagesInMemory, pageInfosCount);
	
	if (pageInfosCount > 0)
	{
		pages = [[NSMutableDictionary alloc] initWithCapacity:pagesCapacity];
	}
	else
	{
		YapDatabasePageInfo *pageInfo = [[YapDatabasePageInfo alloc] init];
		pageInfo->lastAccess = [NSDate date];
		
		pageInfos = [[NSMutableArray alloc] init];
		[pageInfos addObject:pageInfo];
		
		NSMutableArray *page = [[NSMutableArray alloc] initWithCapacity:maxPageSize];
		
		pages = [[NSMutableDictionary alloc] initWithCapacity:pagesCapacity];
		[pages setObject:page forKey:pageInfo->pageKey];
		
		// Note: We do not force the pageInfos data to be written to disk.
		// This will happen automatically once a key is added.
		// If no keys are added, we don't want the data on disk.
	}
	
	// Load persistent configuration information.
	//
	// We can skip this if the pageInfos weren't in the database,
	// because that would mean this is a new order instance.
	
	if (pageInfosData)
	{
		NSData *maxPageSizeData = [transaction dataForKey:KEY_MAX_PAGE_SIZE order:self];
		if (maxPageSizeData)
		{
			NSNumber *maxPageSizeNumber = [NSKeyedUnarchiver unarchiveObjectWithData:maxPageSizeData];
			maxPageSize = [maxPageSizeNumber unsignedIntegerValue];
		}
	}
	
	if (maxPageSize == 0)
	{
		maxPageSize = DEFAULT_MAX_PAGE_SIZE;
	}
	
	[dirtyPageKeys removeAllObjects];
	allKeysRemoved = NO;
}

- (BOOL)isPrepared
{
	return [pageInfos count] > 0;
}

- (void)reset
{
	// Do not touch non-persistent configuration
	// - maxPageSize
	// - userInfo
	
	maxPagesInMemory = DEFAULT_MAX_PAGES_IN_MEMORY;
	
	pageInfos = nil;
	[pages removeAllObjects];
	
	[dirtyPageKeys removeAllObjects];
	allKeysRemoved = NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Transaction
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)commitTransaction:(id <YapOrderReadWriteTransaction>)transaction
{
	// Write dirty pages to disk, and rewrite pageInfo metadata
	
	if ([dirtyPageKeys count] > 0)
	{
		if ([self hasZeroKeys])
		{
			// Flush everything
			
			[transaction removeAllDataForOrder:self];
		}
		else
		{
			// Update or delete the dirty pages
			
			for (NSString *dirtyPageKey in dirtyPageKeys)
			{
				id page = [pages objectForKey:dirtyPageKey];
				
				if (page == nil)
				{
					NSAssert([self pageIndexForPageKey:dirtyPageKey] == NSNotFound,
					         @"Dirty page should not be faulted");
					
					[transaction removeDataForKey:dirtyPageKey order:self];
				}
				else
				{
					NSData *pageData = [NSKeyedArchiver archivedDataWithRootObject:page];
					[transaction setData:pageData forKey:dirtyPageKey order:self];
				}
			}
			
			// Update pageInfos metadata
			
			NSData *pageInfosData = [NSKeyedArchiver archivedDataWithRootObject:pageInfos];
			[transaction setData:pageInfosData forKey:KEY_PAGE_INFOS order:self];
		}
		
		// Reset dirtyPageKeys set
		[dirtyPageKeys removeAllObjects];
	}
	
	allKeysRemoved = NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Snapshot
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns whether or not the order has been modified since the last time commitTransaction was called.
**/
- (BOOL)isModified
{
	return allKeysRemoved || [dirtyPageKeys count] > 0;
}

/**
 * Fetches a changeset that encapsulates information about changes since the last time commitTransaction was called.
 * This dictionary may be passed to another instance running on another connection in order to keep them synced.
**/
- (NSDictionary *)changeset
{
	NSMutableDictionary *changeset = [NSMutableDictionary dictionaryWithCapacity:4];
	
	[changeset setObject:@(maxPageSize) forKey:@"maxPageSize"];
	
	NSArray *pageInfosCopy = [[NSArray alloc] initWithArray:pageInfos copyItems:YES];
	[changeset setObject:pageInfosCopy forKey:@"pageInfos"];
	
	if (allKeysRemoved)
		[changeset setObject:@(YES) forKey:@"allKeysRemoved"];
	
	if ([dirtyPageKeys count] > 0)
		[changeset setObject:[dirtyPageKeys allObjects] forKey:@"dirtyPageKeys"];
	
	return changeset;
}

/**
 * Merges changes from a sibling instance.
**/
- (void)mergeChangeset:(NSDictionary *)changeset
{
	maxPageSize = [[changeset objectForKey:@"maxPageSize"] unsignedIntegerValue];
	
	NSArray *_pageInfos = [changeset objectForKey:@"pageInfos"];
	pageInfos = [[NSMutableArray alloc] initWithArray:_pageInfos copyItems:YES];
	
	if (pages)
	{
		BOOL _allKeysRemoved = [[changeset objectForKey:@"allKeysRemoved"] boolValue];
		NSArray *_dirtyPageKeys = [changeset objectForKey:@"dirtyPageKeys"];
		
		if (_allKeysRemoved) {
			[pages removeAllObjects];
		}
		else if (_dirtyPageKeys) {
			[pages removeObjectsForKeys:_dirtyPageKeys];
		}
	}
	else
	{
		NSUInteger pageInfosCount = [pageInfos count];
		NSUInteger pagesCapacity = (maxPagesInMemory == 0) ? pageInfosCount : MIN(maxPagesInMemory, pageInfosCount);
		
		pages = [[NSMutableDictionary alloc] initWithCapacity:pagesCapacity];
	}
	
	[dirtyPageKeys removeAllObjects];
	allKeysRemoved = NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Config
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)maxPagesInMemory
{
	return maxPagesInMemory;
}

- (void)setMaxPagesInMemory:(NSUInteger)newPagesInMemory
{
	if (maxPagesInMemory == newPagesInMemory) {
		// No change
		return;
	}

	// Update ivar
	
	maxPagesInMemory = newPagesInMemory;
	
	// Maybe unload some pages
	
	if (maxPagesInMemory > 0) // if there's a restriction on how many pages to keep in memory
	{
		YDBLogInfo(@"%@: Looking for pages to unload due to new maxPagesInMemory: %lu",
		          NSStringFromSelector(_cmd), (unsigned long)maxPagesInMemory);
	
		NSUInteger inMemoryDirtyPageCount = 0;
		NSMutableArray *inMemoryNonDirtyPages = [NSMutableArray arrayWithCapacity:[pageInfos count]];
		
		NSUInteger i = 0;
		for (YapDatabasePageInfo *pageInfo in pageInfos)
		{
			if (pageInfo->lastAccess != nil)
			{
				// Page is in memory. Check to see if it's dirty or not.
				
				if ([dirtyPageKeys containsObject:pageInfo->pageKey])
				{
					inMemoryDirtyPageCount++;
				}
				else
				{
					pageInfo->tempPageIndex = i;
					[inMemoryNonDirtyPages addObject:pageInfo];
				}
			}
			
			i++;
		}
		
		if ((inMemoryDirtyPageCount + [inMemoryNonDirtyPages count]) > maxPagesInMemory)
		{
			// Sort flushable pages by lastAccess timestamp.
			
			[inMemoryNonDirtyPages sortUsingComparator:^NSComparisonResult(id obj1, id obj2){
				
				__unsafe_unretained NSDate *lastAccess1 = ((YapDatabasePageInfo *)obj1)->lastAccess;
				__unsafe_unretained NSDate *lastAccess2 = ((YapDatabasePageInfo *)obj2)->lastAccess;
				
				return [lastAccess1 compare:lastAccess2];
			}];
			
			// Flush the page(s) with the oldest lastAccess timestamp.
			//
			// Since they were sorted ascending by timestamp, the oldest timestamp will be at position zero.
			
			while (([inMemoryNonDirtyPages count] > 0) &&
			       ((inMemoryDirtyPageCount + [inMemoryNonDirtyPages count]) > maxPagesInMemory))
			{
				YapDatabasePageInfo *pageInfo = [inMemoryNonDirtyPages objectAtIndex:0];
				[inMemoryNonDirtyPages removeObjectAtIndex:0];
				
				YDBLogInfo(@"%@: UnLoading page at index %lu with key %@",
				    NSStringFromSelector(_cmd), (unsigned long)pageInfo->tempPageIndex, pageInfo->pageKey);
				
				pageInfo->lastAccess = nil;
				[pages removeObjectForKey:pageInfo->pageKey];
			}
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Persistent Config
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)maxPageSize
{
	return maxPageSize;
}

- (void)setMaxPageSize:(NSUInteger)newPageSize transaction:(id <YapOrderReadWriteTransaction>)transaction
{
	if (maxPageSize == newPageSize) {
		// No change
		return;
	}
	if (newPageSize == 0) {
		YDBLogWarn(@"%@: Ignoring attempt to set maxPageSize to zero", NSStringFromSelector(_cmd));
		return;
	}
	
	// Update ivar
	
	maxPageSize = newPageSize;
	
	// Write persistent config option to disk
	
	NSNumber *maxPageSizeNumber = @(maxPageSize);
	NSData *maxPageSizeData = [NSKeyedArchiver archivedDataWithRootObject:maxPageSizeNumber];
	
	[transaction setData:maxPageSizeData forKey:KEY_MAX_PAGE_SIZE order:self];
	
	// Check for shortcut.
	// This is common if the user changes the values immediately upon creating a database.
	
	if ([self hasZeroKeys]) return;
	
	// Restructure pages to fit new maxPageSize.
	// 
	// We're going to create new versions of 'pageInfos' and 'pages'.
	
	YDBLogInfo(@"%@: Restructuring pages due to new maxPageSize: %lu",
	          NSStringFromSelector(_cmd), (unsigned long)maxPageSize);
	
	NSMutableArray *newPageInfos = [NSMutableArray array];
	NSMutableDictionary *newPages = [NSMutableDictionary dictionary];
	
	YapDatabasePageInfo *newPageInfo = [[YapDatabasePageInfo alloc] init];
	NSMutableArray *newPage = [NSMutableArray arrayWithCapacity:newPageSize];
	
	// Loop over the existing pages/keys, and fill out the new page(s).
	// Once we hit our newPageSize, then close the page and start a new one.
	
	NSUInteger count = [self numberOfPages];
	
	for (NSUInteger i = 0; i < count; i++)
	{
		NSArray *oldPage = [self pageForIndex:i transaction:transaction];
		
		for (NSString *key in oldPage)
		{
			[newPage addObject:key];
			
			if ([newPage count] == newPageSize)
			{
				newPageInfo->pageSize = [newPage count];
				newPageInfo->lastAccess = [NSDate date];
				
				[newPages setObject:newPage forKey:newPageInfo->pageKey];
				[newPageInfos addObject:newPageInfo];
				
				newPageInfo = [[YapDatabasePageInfo alloc] init];
				newPage = [NSMutableArray arrayWithCapacity:newPageSize];
			}
		}
	}
	
	if ([newPage count] > 0 || [newPageInfos count] == 0)
	{
		newPageInfo->pageSize = [newPage count];
		newPageInfo->lastAccess = [NSDate date];
		
		[newPages setObject:newPage forKey:newPageInfo->pageKey];
		[newPageInfos addObject:newPageInfo];
	}
	
	// Mark all old and new pages as dirty
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		[dirtyPageKeys addObject:pageInfo->pageKey];
	}
	
	for (YapDatabasePageInfo *pageInfo in newPageInfos)
	{
		[dirtyPageKeys addObject:pageInfo->pageKey];
	}
	
	// Swap in new arrays
	
	pageInfos = newPageInfos;
	pages = newPages;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Pages
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfPages
{
	return [pageInfos count];
}

/**
 * All page loading should go through this method.
 * It provides all logic to load/unload pages based on faulted state and maxPagesInMemory configuration.
**/
- (NSMutableArray *)pageForIndex:(NSUInteger)index transaction:(id <YapOrderReadTransaction>)transaction
{
	if (index >= [pageInfos count]) return nil;
	
	YapDatabasePageInfo *pageInfo = [pageInfos objectAtIndex:index];
	NSMutableArray *page = [pages objectForKey:pageInfo->pageKey];
	
	if (page == nil)
	{
		// The page isn't loaded into memory
		
		if (pageInfo->pageSize == 0)
		{
			// We need to create a new empty page
			
			page = [[NSMutableArray alloc] initWithCapacity:maxPageSize];
		}
		else
		{
			// We need to load the page from disk and deserialize it
			
			YDBLogInfo(@"%@: Loading page at index %lu with key %@",
			    NSStringFromSelector(_cmd), (unsigned long)index, pageInfo->pageKey);
			
			// Request page data from disk
			
			id archive = [transaction dataForKey:pageInfo->pageKey order:self];
			if (archive == nil)
			{
				YDBLogError(@"%@: Missing page at index %lu with key %@",
				    NSStringFromSelector(_cmd), (unsigned long)index, pageInfo->pageKey);
				
				return nil;
			}
			
			// Unarchive page data
			
			page = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
			if (page == nil)
			{
				YDBLogError(@"%@: Corrupt page at index %lu with key %@",
				    NSStringFromSelector(_cmd), (unsigned long)index, pageInfo->pageKey);
				
				return nil;
			}
		}
		
		// Add page to pageCache
		
		[pages setObject:page forKey:pageInfo->pageKey];
	}
	
	// Update page lastAccess timestamp.
	// This is used during page eviction so we evict pages that are used less often first.
	pageInfo->lastAccess = [NSDate date];
	
	
	if (maxPagesInMemory > 0) // if there's a restriction on how many pages to keep in memory
	{
		// Find non-faulted pages that aren't dirty (don't have changes we still need to write to disk).
		// That is, find pages we can unload from RAM.
		
		NSUInteger inMemoryDirtyPageCount = 0;
		NSMutableArray *inMemoryNonDirtyPages = [NSMutableArray arrayWithCapacity:[pageInfos count]];
		
		NSUInteger i = 0;
		for (YapDatabasePageInfo *pageInfo in pageInfos)
		{
			if (i == index)
			{
				// Ignore requested page
			}
			else if (pageInfo->lastAccess != nil)
			{
				// Page is in memory. Check to see if it's dirty or not.
				
				if ([dirtyPageKeys containsObject:pageInfo->pageKey])
				{
					inMemoryDirtyPageCount++;
				}
				else
				{
					pageInfo->tempPageIndex = i;
					[inMemoryNonDirtyPages addObject:pageInfo];
				}
			}
			
			i++;
		}
		
		// We excluded the 'just loaded' page in the code above.
		// This is where the '1' comes from below.
		
		if ((1 + inMemoryDirtyPageCount + [inMemoryNonDirtyPages count]) > maxPagesInMemory)
		{
			// Flush the page with the oldest lastAccess timestamp.
			
			YapDatabasePageInfo *oldestPageInfo = nil;
			
			for (YapDatabasePageInfo *pageInfo in inMemoryNonDirtyPages)
			{
				if (oldestPageInfo == nil)
				{
					oldestPageInfo = pageInfo;
				}
				else
				{
					__unsafe_unretained NSDate *lastAccess1 = oldestPageInfo->lastAccess;
					__unsafe_unretained NSDate *lastAccess2 = pageInfo->lastAccess;
					
					NSComparisonResult comp = [lastAccess1 compare:lastAccess2];
					
					if (comp == NSOrderedDescending)
						oldestPageInfo = pageInfo;
				}
			}
			
			YDBLogInfo(@"%@: UnLoading page at index %lu with key %@",
			    NSStringFromSelector(_cmd), (unsigned long)oldestPageInfo->tempPageIndex, oldestPageInfo->pageKey);
			
			oldestPageInfo->lastAccess = nil;
			[pages removeObjectForKey:oldestPageInfo->pageKey];
		}
	}
	
	return (NSMutableArray *)page;
}

- (NSUInteger)pageSizeForPageAtIndex:(NSUInteger)index
{
	if (index >= [pageInfos count]) return 0;
	
	YapDatabasePageInfo *pageInfo = [pageInfos objectAtIndex:index];
	return pageInfo->pageSize;
}

/**
 * Returns the pageOffset for the indicated page.
 *
 * For example, if there are 3 pages with counts [10, 5, 10] :
 * Page 0 offset = 0
 * Page 1 offset = 10
 * Page 2 offset = 15
**/
- (NSUInteger)pageOffsetForPageAtIndex:(NSUInteger)index
{
	NSUInteger pageIndex = 0;
	NSUInteger pageOffset = 0;
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		if (pageIndex == index)
		{
			return pageOffset;
		}
		
		pageIndex++;
		pageOffset += pageInfo->pageSize;
	}
	
	return 0;
}

/**
 * Returns the list of pages (via pageKeys) that are loaded into memory.
 * 
 * This is helpful, for example, if you need to search the database for a specific key.
 * You can first search the pages that are already in memory, and possibly reduce trips to the disk.
**/
- (NSArray *)inMemoryPageKeys
{
	NSUInteger sensibleCapacity = maxPagesInMemory > 0 ? maxPagesInMemory : [pageInfos count];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:sensibleCapacity];
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		if (pageInfo->lastAccess != nil)
		{
			[result addObject:pageInfo->pageKey];
		}
	}
	
	return result;
}

/**
 * Returns the list of pages (via pageKeys) that are not loaded into memory.
 * 
 * This is helpful, for example, if you need to search the database for a specific key.
 * You can first search the pages that are already in memory, and possibly reduce trips to the disk.
**/
- (NSArray *)notInMemoryPageKeys
{
	NSUInteger sensibleCapacity = [pageInfos count];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:sensibleCapacity];
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		if (pageInfo->lastAccess == nil)
		{
			[result addObject:pageInfo->pageKey];
		}
	}
	
	return result;
}

/**
 * Translates from pageKey to pageIndex.
 * Returns NSNotFound if pageKey doesn't exist.
**/
- (NSUInteger)pageIndexForPageKey:(NSString *)pageKey
{
	NSUInteger pageIndex = 0;
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		if ([pageInfo->pageKey isEqualToString:pageKey])
		{
			return pageIndex;
		}
		
		pageIndex++;
	}
	
	return NSNotFound;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Keys
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfKeys
{
	NSUInteger count = 0;
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		count += pageInfo->pageSize;
	}
	
	return count;
}

- (BOOL)hasZeroKeys
{
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		if (pageInfo->pageSize > 0)
			return NO;
	}
	
	return YES;
}

- (NSString *)keyAtIndex:(NSUInteger)index transaction:(id <YapOrderReadTransaction>)transaction
{
	// Loop through pages (via pageInfo metadata) to find the corresponding page
	
	NSUInteger pageIndex = 0;
	NSUInteger pageOffset = 0;
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		if (index < (pageOffset + pageInfo->pageSize))
		{
			// Found the corresponding page.
			// Now fetch it from cache or load it from disk.
			
			NSArray *page = [self pageForIndex:pageIndex transaction:transaction];
			
			// And return the requested key
			
			return [page objectAtIndex:(index - pageOffset)];
		}
		
		pageIndex++;
		pageOffset += pageInfo->pageSize;
	}
	
	YDBLogError(@"%@: Index out of bounds: index(%lu) >= numberOfKeys(%lu)",
	    NSStringFromSelector(_cmd), (unsigned long)index, (unsigned long)pageOffset);
	
	return nil;
}

- (NSArray *)allKeys:(id <YapOrderReadTransaction>)transaction
{
	// Sort the pages based on whether they are loaded into memory or not.
	// That way we can first use the pages already in RAM before paging in others.
	// This prevents us from paging out cached pages, only to page them back in immediately afterwards.
	
	NSMutableArray *sortedPageInfos = [NSMutableArray arrayWithCapacity:[pageInfos count]];
	
	NSUInteger pageIndex = 0;
	NSUInteger pageOffset = 0;
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		pageInfo->tempPageIndex = pageIndex;
		pageInfo->tempPageOffset = pageOffset;
		
		if (pageInfo->lastAccess != nil)
		{
			// Page is loaded into memory.
			// Add to beginning of array.
			[sortedPageInfos insertObject:pageInfo atIndex:0];
		}
		else
		{
			// Page isn't loaded into memory.
			// Add to end of array.
			[sortedPageInfos addObject:pageInfo];
		}
		
		pageIndex++;
		pageOffset += pageInfo->pageSize;
	}
	
	NSUInteger numberOfKeys = pageOffset;
	
	// Loop through pages & keys til we've added all keys.
	//
	// Remember we may be looping through the pages out-of-order.
	// So we fill our array with placeholders so we can place the keys directly into their correct position.
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:numberOfKeys];
	id placeholder = [NSNull null];
	
	NSUInteger i;
	for (i = 0; i < numberOfKeys; i++)
	{
		[result addObject:placeholder];
	}
	
	for (YapDatabasePageInfo *pageInfo in sortedPageInfos)
	{
		// Fetch the corresponding page.
		// We've arranged it so cached pages get processed before pages we have to load from disk.
		
		NSArray *page = [self pageForIndex:pageInfo->tempPageIndex transaction:transaction];
		
		// Loop through the keys, and add directly to the C-style array at the correct position.
		
		NSUInteger indexWithinResult = pageInfo->tempPageOffset;
		
		for (NSString *key in page)
		{
			[result replaceObjectAtIndex:indexWithinResult withObject:key];
			
			indexWithinResult++;
		}
	}
	
	return result;
}

- (NSArray *)keysInRange:(NSRange)range transaction:(id <YapOrderReadTransaction>)transaction
{
	// Find the pages (via pageInfo metadata) that contains keys in the given range.
	//
	// Sort these pages based on whether they are loaded into memory or not.
	// That way we can first use the pages already in RAM before paging in the others.
	// This prevents us from paging out cached pages, only to page them back in immediately afterwards.
	
	NSUInteger sensibleCapacity = (NSUInteger)ceil( (double)range.length / (double)maxPageSize ) + 1;
	NSMutableArray *sortedPageInfos = [NSMutableArray arrayWithCapacity:sensibleCapacity];
	
	BOOL startedRange = NO;
	
	NSUInteger pageIndex = 0;
	NSUInteger pageOffset = 0;
	
	NSUInteger keysCount = 0;
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		NSRange pageRange = NSMakeRange(pageOffset, pageInfo->pageSize);
		NSRange keysRange = NSIntersectionRange(pageRange, range);
		
		if (keysRange.length > 0)
		{
			// Found an intersecting page
			startedRange = YES;
			
			pageInfo->tempPageIndex = pageIndex;
			pageInfo->tempPageOffset = pageOffset;
			
			keysCount += keysRange.length;
			
			if (pageInfo->lastAccess != nil)
			{
				// Page is loaded into memory.
				// Add to beginning of array.
				[sortedPageInfos insertObject:pageInfo atIndex:0];
			}
			else
			{
				// Page isn't loaded into memory.
				// Add to end of array.
				[sortedPageInfos addObject:pageInfo];
			}
		}
		else if (startedRange)
		{
			// We've completed the range
			break;
		}
		
		pageIndex++;
		pageOffset += pageInfo->pageSize;
	}
	
	if (!startedRange)
	{
		YDBLogError(@"%@: Range out of bounds: range.location(%lu) >= numberOfKeys(%lu)",
		    NSStringFromSelector(_cmd), (unsigned long)range.location, (unsigned long)[self numberOfKeys]);
		
		return nil;
	}
	
	if (keysCount < range.length)
	{
		YDBLogWarn(@"%@: Range partially out of bounds: range(%lu, %lu) >= numberOfKeys(%lu)",
		    NSStringFromSelector(_cmd),
		    (unsigned long)range.location, (unsigned long)range.length, (unsigned long)pageOffset);
	}
	
	// Loop through pages & keys til we've fullfilled the request.
	//
	// Remember we may be looping through the pages out-of-order.
	// So we fill our array with placeholders so we can place the keys directly into their correct position.
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:keysCount];
	id placeholder = [NSNull null];
	
	NSUInteger i;
	for (i = 0; i < keysCount; i++)
	{
		[result addObject:placeholder];
	}
	
	for (YapDatabasePageInfo *pageInfo in sortedPageInfos)
	{
		// Fetch the corresponding page.
		// We've arranged it so cached pages get processed before pages we have to load from disk.
		
		NSArray *page = [self pageForIndex:pageInfo->tempPageIndex transaction:transaction];
		
		// Calculate the range of keys we need from this page
		
		NSRange pageRange = NSMakeRange(pageInfo->tempPageOffset, pageInfo->pageSize);
		NSRange keysRange = NSIntersectionRange(pageRange, range);
		
		// Loop through the needed keys, and add directly to the C-style array at the correct position.
		
		NSUInteger indexWithinPage = keysRange.location - pageInfo->tempPageOffset;
		NSUInteger indexWithinResult = keysRange.location - range.location;
		
		for (i = 0; i < keysRange.length; i++)
		{
			[result replaceObjectAtIndex:indexWithinResult withObject:[page objectAtIndex:indexWithinPage]];
			
			indexWithinPage++;
			indexWithinResult++;
		}
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Add
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Appends the given key to the end of the array.
**/
- (void)appendKey:(NSString *)key transaction:(id <YapOrderReadWriteTransaction>)transaction
{
	NSUInteger lastPageIndex = [self numberOfPages] - 1;
	YapDatabasePageInfo *lastPageInfo = [pageInfos objectAtIndex:lastPageIndex];
	
	if (lastPageInfo->pageSize + 1 <= maxPageSize)
	{
		// Add to last page
		
		NSMutableArray *lastPage = (NSMutableArray *)[self pageForIndex:lastPageIndex transaction:transaction];
		[lastPage addObject:key];
		
		lastPageInfo->pageSize++;
		[dirtyPageKeys addObject:lastPageInfo->pageKey];
	}
	else
	{
		// Create a new page, and add to the end
		
		NSMutableArray *page = [[NSMutableArray alloc] initWithCapacity:maxPageSize];
		[page addObject:key];
		
		YapDatabasePageInfo *pageInfo = [[YapDatabasePageInfo alloc] init];
		pageInfo->lastAccess = [NSDate date];
		pageInfo->pageSize++;
		
		[pageInfos addObject:pageInfo];
		[pages setObject:page forKey:pageInfo->pageKey];
		
		[dirtyPageKeys addObject:pageInfo->pageKey];
	}
}

/**
 * Prepends the given key to the beginning of the array.
**/
- (void)prependKey:(NSString *)key transaction:(id <YapOrderReadWriteTransaction>)transaction
{
	NSUInteger firstPageIndex = 0;
	YapDatabasePageInfo *firstPageInfo = [pageInfos objectAtIndex:firstPageIndex];
	
	if (firstPageInfo->pageSize + 1 <= maxPageSize)
	{
		// Add to first page
		
		NSMutableArray *firstPage = (NSMutableArray *)[self pageForIndex:firstPageIndex transaction:transaction];
		[firstPage insertObject:key atIndex:0];
		
		firstPageInfo->pageSize++;
		[dirtyPageKeys addObject:firstPageInfo->pageKey];
	}
	else
	{
		// Create a new page, and insert at the beginning
		
		NSMutableArray *page = [[NSMutableArray alloc] initWithCapacity:maxPageSize];
		[page addObject:key];
		
		YapDatabasePageInfo *pageInfo = [[YapDatabasePageInfo alloc] init];
		pageInfo->lastAccess = [NSDate date];
		pageInfo->pageSize++;
		
		[pageInfos insertObject:pageInfo atIndex:0];
		[pages setObject:page forKey:pageInfo->pageKey];
		
		[dirtyPageKeys addObject:pageInfo->pageKey];
	}
}

/**
 * Inserts the given key into the array at the specified position.
**/
- (void)insertKey:(NSString *)key atIndex:(NSUInteger)index transaction:(id <YapOrderReadWriteTransaction>)transaction
{
	if (index == 0)
	{
		[self prependKey:key transaction:transaction];
		return;
	}
	if (index >= [self numberOfKeys])
	{
		[self appendKey:key transaction:transaction];
		return;
	}
	
	// Find pageIndex
	
	NSUInteger pageIndex = 0;
	NSUInteger pageOffset = 0;
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		if (index < (pageOffset + pageInfo->pageSize))
		{
			// Found corresponding page
			break;
		}
		
		pageIndex++;
		pageOffset += pageInfo->pageSize;
	}
	
	// Insert object in page
	
	YapDatabasePageInfo *pageInfo = [pageInfos objectAtIndex:pageIndex];
	
	NSMutableArray *page = (NSMutableArray *)[self pageForIndex:pageIndex transaction:transaction];
	[page insertObject:key atIndex:(index - pageOffset)];
	
	pageInfo->pageSize++;
	[dirtyPageKeys addObject:pageInfo->pageKey];
	
	// Did we exceed the maxPageSize
	
	if (pageInfo->pageSize <= maxPageSize)
	{
		// Cool, we're done
		return;
	}
	
	// Need to shift keys to fit within maxPageSize restriction.
	// But do we shift up or down?
	//
	// We'd like to do whatever is more efficient.
	// So we look at the effort needed in each direction.
	// And we take into account those pages that are already cached in memory.
	
	NSUInteger numPagesToShiftBeforeIndex = 0;
	NSUInteger numPagesToShiftAfterIndex = 0;
	
	NSUInteger numPagesToLoadBeforeIndex = 0;
	NSUInteger numPagesToLoadAfterIndex = 0;
	
	NSUInteger prevPageIndex = pageIndex;
	while (prevPageIndex > 0)
	{
		prevPageIndex--;
		YapDatabasePageInfo *prevPageInfo = [pageInfos objectAtIndex:prevPageIndex];
		
		if (prevPageInfo->lastAccess == nil)
		{
			numPagesToLoadBeforeIndex++;
		}
		if (prevPageInfo->pageSize >= maxPageSize)
		{
			numPagesToShiftBeforeIndex++;
		}
		else
		{
			break;
		}
	}
	
	NSUInteger nextPageIndex = pageIndex;
	while (nextPageIndex + 1 < [pageInfos count])
	{
		nextPageIndex++;
		YapDatabasePageInfo *nextPageInfo = [pageInfos objectAtIndex:nextPageIndex];
		
		if (nextPageInfo->lastAccess == nil)
		{
			numPagesToLoadAfterIndex++;
		}
		if (nextPageInfo->pageSize >= maxPageSize)
		{
			numPagesToShiftAfterIndex++;
		}
		else
		{
			break;
		}
	}
	
	BOOL shiftDown =
	    (numPagesToLoadBeforeIndex < numPagesToLoadAfterIndex)
	 || (
	         (numPagesToLoadBeforeIndex == numPagesToLoadAfterIndex)
	      && (numPagesToShiftBeforeIndex < numPagesToShiftAfterIndex)
	    );
	
	// Perform key shifting
	
	if (shiftDown)
	{
		// Shift keys before index downward
		
		while (pageInfo->pageSize > maxPageSize)
		{
			YapDatabasePageInfo *prevPageInfo;
			NSMutableArray *prevPage;
			
			if (pageIndex > 0)
			{
				prevPageInfo = [pageInfos objectAtIndex:(pageIndex - 1)];
				prevPage = (NSMutableArray *)[self pageForIndex:(pageIndex-1) transaction:transaction];
			}
			else
			{
				prevPageInfo = [[YapDatabasePageInfo alloc] init];
				prevPageInfo->lastAccess = [NSDate date];
				
				prevPage = [[NSMutableArray alloc] initWithCapacity:maxPageSize];
				
				[pageInfos insertObject:prevPageInfo atIndex:0];
				[pages setObject:prevPage forKey:prevPageInfo->pageKey];
			}
			
			NSString *firstKey = [page objectAtIndex:0];
			[page removeObjectAtIndex:0];
			pageInfo->pageSize--;
			
			[prevPage addObject:firstKey];
			prevPageInfo->pageSize++;
			
			[dirtyPageKeys addObject:prevPageInfo->pageKey];
			
			pageInfo = prevPageInfo;
			page = prevPage;
		}
	}
	else
	{
		// Shift keys after index upwards
		
		while (pageInfo->pageSize > maxPageSize)
		{
			YapDatabasePageInfo *nextPageInfo;
			NSMutableArray *nextPage;
			
			if ((pageIndex+1) < [pageInfos count])
			{
				nextPageInfo = [pageInfos objectAtIndex:(pageIndex+1)];
				nextPage = (NSMutableArray *)[self pageForIndex:(pageIndex+1) transaction:transaction];
			}
			else
			{
				nextPageInfo = [[YapDatabasePageInfo alloc] init];
				nextPageInfo->lastAccess = [NSDate date];
				
				nextPage = [[NSMutableArray alloc] initWithCapacity:maxPageSize];
				
				[pageInfos addObject:nextPageInfo];
				[pages setObject:nextPage forKey:nextPageInfo->pageKey];
			}
			
			NSString *lastKey = [page lastObject];
			[page removeLastObject];
			pageInfo->pageSize--;
			
			[nextPage insertObject:lastKey atIndex:0];
			nextPageInfo->pageSize++;
			
			[dirtyPageKeys addObject:nextPageInfo->pageKey];
			
			pageInfo = nextPageInfo;
			page = nextPage;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Remove
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Removes the key at the given index.
 *
 * This method is faster than removeKey: as it doesn't require searching for the key.
**/
- (NSString *)removeKeyAtIndex:(NSUInteger)index transaction:(id <YapOrderReadWriteTransaction>)transaction
{
	// Loop through pages (via pageInfo metadata) to find the corresponding page
	
	NSString *removedKey = nil;
	
	NSUInteger pageIndex = 0;
	NSUInteger pageOffset = 0;
	
	for (YapDatabasePageInfo *pageInfo in pageInfos)
	{
		if (index < (pageOffset + pageInfo->pageSize))
		{
			// Found the corresponding page.
			// Now fetch it from cache or load it from disk.
			
			NSMutableArray *page = (NSMutableArray *)[self pageForIndex:pageIndex transaction:transaction];
			
			// Remove the key, and update the pageInfo metadata
			
			removedKey = [page objectAtIndex:(index - pageOffset)];
			
			[page removeObjectAtIndex:(index - pageOffset)];
			pageInfo->pageSize--;
			
			// Mark the page as dirty so it gets rewritten during commitTransaction
			
			[dirtyPageKeys addObject:pageInfo->pageKey];
			
			// Drop the page if it's now empty (but not the last page)
			
			if ((pageInfo->pageSize == 0) && ([pageInfos count] > 1))
			{
				YDBLogInfo(@"%@: Dropping empty page at index %lu with key %@",
				    NSStringFromSelector(_cmd), (unsigned long)pageIndex, pageInfo->pageKey);
				
				[pages removeObjectForKey:pageInfo->pageKey];
				[pageInfos removeObjectAtIndex:pageIndex];
			}
			
			break;
		}
		
		pageIndex++;
		pageOffset += pageInfo->pageSize;
	}
	
	if (removedKey == nil)
	{
		YDBLogError(@"%@: Index out of bounds: index(%lu) >= numberOfKeys(%lu)",
		              NSStringFromSelector(_cmd), (unsigned long)index, (unsigned long)pageOffset);
	}
	
	return removedKey;
}

/**
 * Removes the keys at the given indexes.
 *
 * This method is faster than removeKeys: as it doesn't require searching for the keys.
**/
- (NSArray *)removeKeysInRange:(NSRange)range transaction:(id <YapOrderReadWriteTransaction>)transaction
{
	NSMutableArray *removedKeys = [NSMutableArray arrayWithCapacity:range.length];
	
	// Loop throuh pages (via pageInfo metadata) to find the corresponding page(s)
	
	NSUInteger pageIndex = 0;
	NSUInteger pageOffset = 0;
	
	while ((pageIndex < [pageInfos count]) && ([removedKeys count] < range.length))
	{
		YapDatabasePageInfo *pageInfo = [pageInfos objectAtIndex:pageIndex];
		
		NSRange pageRange = NSMakeRange(pageOffset, pageInfo->pageSize);
		NSRange removeRange = NSIntersectionRange(pageRange, range);
		
		BOOL droppedPage = NO;
		
		if (removeRange.length > 0)
		{
			// Fetch the corresponding page from cache or load it from disk.
			
			NSMutableArray *page = (NSMutableArray *)[self pageForIndex:pageIndex transaction:transaction];
			
			// Remove the key(s), and update the pageInfo metadata
			
			[removedKeys addObjectsFromArray:[page subarrayWithRange:removeRange]];
			
			[page removeObjectsInRange:removeRange];
			pageInfo->pageSize -= removeRange.length;
			
			// Mark the page as dirty so it gets rewritten during completeTransaction
			
			[dirtyPageKeys addObject:pageInfo->pageKey];
			
			// Drop the page if it's now empty (but not the last page)
			
		 	if ((pageInfo->pageSize == 0) && ([pageInfos count] > 1))
			{
				YDBLogInfo(@"%@: Dropping empty page at index %lu with key %@",
				    NSStringFromSelector(_cmd), (unsigned long)pageIndex, pageInfo->pageKey);
				
				[pages removeObjectForKey:pageInfo->pageKey];
				[pageInfos removeObjectAtIndex:pageIndex];
				
				droppedPage = YES;
			}
		}
		
		if (!droppedPage) {
			pageIndex++;
		}
		pageOffset += pageInfo->pageSize;
	}
	
	if ([removedKeys count] < range.length)
	{
		YDBLogWarn(@"%@: Range out of bounds: range(%lu, %lu) >= numberOfKeys(%lu)",
		    NSStringFromSelector(_cmd),
		    (unsigned long)range.location, (unsigned long)range.length, (unsigned long)pageOffset);
	}
	
	return removedKeys;
}

/**
 * Removes the given key.
 *
 * Only use this method if you don't already know the index of the key.
 * Otherwise, it is far faster to use the removeKeyAtIndex: method, as this method must search for the key.
**/
- (void)removeKey:(NSString *)key transaction:(id <YapOrderReadWriteTransaction>)transaction
{
	if (key == nil) return;
	
	[self removeKeys:@[ key ] transaction:transaction];
}

/**
 * Removes the given keys.
 *
 * Only use this method if you don't already know the indexes of the keys.
 * Otherwise, it is far faster to use the removeKeyAtIndex: method, as this method must search for the key.
**/
- (void)removeKeys:(NSArray *)keysArray transaction:(id <YapOrderReadWriteTransaction>)transaction
{
	if ([keysArray count] == 0) return;
	
	// Convert array to set for faster containsObject: execution
	NSMutableSet *keys = [NSMutableSet setWithArray:keysArray];
	
	// First, search pages we already have loaded into memory.
	// Then, if needed, search the rest.
	
	NSMutableArray *pageKeys = [NSMutableArray arrayWithCapacity:[pageInfos count]];
	
	[pageKeys addObjectsFromArray:[self inMemoryPageKeys]];
	[pageKeys addObjectsFromArray:[self notInMemoryPageKeys]];
	
	for (NSString *pageKey in pageKeys)
	{
		NSUInteger pageIndex = [self pageIndexForPageKey:pageKey];
		
		YapDatabasePageInfo *pageInfo = [pageInfos objectAtIndex:pageIndex];
		NSMutableArray *page = (NSMutableArray *)[self pageForIndex:pageIndex transaction:transaction];
		
		NSUInteger i = 0;
		while (i < [page count])
		{
			NSString *key = [page objectAtIndex:i];
			
			if ([keys containsObject:key])
			{
				// Remove key from page
				
				[page removeObjectAtIndex:i];
				
				pageInfo->pageSize--;
				[dirtyPageKeys addObject:pageInfo->pageKey];
				
				#if NO_DUPLICATES_OPTIMIZATION
				
				// Remove key from set of keys.
				//
				// Since there's a verbal guarantee there won't be any duplicate keys appended/prepended,
				// we can optimize the removal process by only looking for each key once.
				
				[keys removeObject:key];
				
				if ([keys count] == 0) break;
				
				#endif
			}
			else
			{
				i++;
			}
		}
		
		// Drop the page if it's now empty (but not the last page)
		
		if ((pageInfo->pageSize == 0) && ([pageInfos count] > 1))
		{
			YDBLogInfo(@"%@: Dropping empty page at index %lu with key %@",
			    NSStringFromSelector(_cmd), (unsigned long)pageIndex, pageInfo->pageKey);
			
			[pages removeObjectForKey:pageInfo->pageKey];
			[pageInfos removeObjectAtIndex:pageIndex];
		}
		
		#if NO_DUPLICATES_OPTIMIZATION
		
		if ([keys count] == 0) break;
		
		#endif
	}
}

- (void)removeAllKeys:(id <YapOrderReadWriteTransaction>)transaction
{
	if ([self hasZeroKeys]) return;
	
	[transaction removeAllDataForOrder:self];
	
	[dirtyPageKeys removeAllObjects];
	
	[pageInfos removeAllObjects];
	[pages removeAllObjects];
	
	YapDatabasePageInfo *emptyPageInfo = [[YapDatabasePageInfo alloc] init];
	emptyPageInfo->lastAccess = [NSDate date];
	
	NSMutableArray *emptyPage = [[NSMutableArray alloc] initWithCapacity:maxPageSize];
	
	[pageInfos addObject:emptyPageInfo];
	[pages setObject:emptyPage forKey:emptyPageInfo->pageKey];
	
	allKeysRemoved = YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)enumerateKeysUsingBlock:(void (^)(NSUInteger idx, NSString *key, BOOL *stop))block
                    transaction:(id <YapOrderReadTransaction>)transaction
{
	if (block == NULL) return;
	
	BOOL stop = NO;
	
	NSUInteger keyIndex = 0;
	NSUInteger pageIndex = 0;
	NSUInteger pageCount = [pageInfos count];
	
	for (pageIndex = 0; pageIndex < pageCount; pageIndex++)
	{
		NSArray *page = [self pageForIndex:pageIndex transaction:transaction];
		
		for (NSString *key in page)
		{
			block(keyIndex, key, &stop);
			
			if (stop) return;
			keyIndex++;
		}
	}
}

- (void)enumerateKeysWithOptions:(NSEnumerationOptions)inOptions
                      usingBlock:(void (^)(NSUInteger idx, NSString *key, BOOL *stop))block
                     transaction:(id <YapOrderReadTransaction>)transaction
{
	if (block == NULL) return;
	
	NSEnumerationOptions options = (inOptions & NSEnumerationReverse); // We only support NSEnumerationReverse
	BOOL forwardEnumeration = (options == NSEnumerationReverse);
	
	__block NSUInteger keyIndex;
	
	if (forwardEnumeration)
		keyIndex = 0;
	else
		keyIndex = [self numberOfKeys] - 1;
	
	__block BOOL stop = NO;
	
	[pageInfos enumerateObjectsWithOptions:options usingBlock:^(id pageInfoObj, NSUInteger pageIdx, BOOL *outerStop){
		
		NSArray *page = [self pageForIndex:pageIdx transaction:transaction];
		
		[page enumerateObjectsWithOptions:options usingBlock:^(id keyObj, NSUInteger keyIdx, BOOL *innerStop){
			
			NSString *key = (NSString *)keyObj;
			
			block(keyIndex, key, &stop);
			
			if (forwardEnumeration)
				keyIndex++;
			else
				keyIndex--;
			
			if (stop) *innerStop = YES;
		}];
		
		if (stop) *outerStop = YES;
	}];
}

- (void)enumerateKeysInRange:(NSRange)range
                 withOptions:(NSEnumerationOptions)inOptions
                  usingBlock:(void (^)(NSUInteger idx, NSString *key, BOOL *stop))block
                 transaction:(id <YapOrderReadTransaction>)transaction
{
	if (block == NULL) return;
	
	NSEnumerationOptions options = (inOptions & NSEnumerationReverse); // We only support NSEnumerationReverse
	BOOL forwardEnumeration = (options == NSEnumerationReverse);
	
	
	__block NSUInteger pageOffset;
	if (forwardEnumeration)
		pageOffset = 0;
	else
		pageOffset = [self pageOffsetForPageAtIndex:([self numberOfPages] - 1)];
		
	__block NSUInteger keysLeft = range.length;
	__block BOOL startedRange = NO;
	
	[pageInfos enumerateObjectsWithOptions:options usingBlock:^(id pageInfoObj, NSUInteger pageIndex, BOOL *outerStop){
	
		YapDatabasePageInfo *pageInfo = (YapDatabasePageInfo *)pageInfoObj;
		
		NSRange pageRange = NSMakeRange(pageOffset, pageInfo->pageSize);
		NSRange keysRange = NSIntersectionRange(pageRange, range);
		
		if (keysRange.length > 0)
		{
			// Fetch the corresponding page from cache or load it from disk.
			
			NSArray *page = [self pageForIndex:pageIndex transaction:transaction];
			
			// Enumerate the subset
			
			NSRange subsetRange = NSMakeRange(keysRange.location-pageOffset, keysRange.length);
			NSIndexSet *subset = [NSIndexSet indexSetWithIndexesInRange:subsetRange];
			
			__block BOOL abort = NO;
			
			[page enumerateObjectsAtIndexes:subset
			                        options:options
			                     usingBlock:^(id obj, NSUInteger idx, BOOL *innerStop){
				
				NSString *key = (NSString *)obj;
				
				block(pageOffset+idx, key, &abort);
				
				if (abort) *innerStop = YES;
			}];
			
			if (abort) *outerStop = YES;
			
			keysLeft -= keysRange.length;
		}
		else if (startedRange)
		{
			// We've completed the range
			*outerStop = YES;
		}
		
		pageIndex++;
		pageOffset += pageInfo->pageSize;
	}];
	
	if (keysLeft > 0)
	{
		YDBLogWarn(@"%@: Range out of bounds: range(%lu, %lu) >= numberOfKeys(%lu)",
		    NSStringFromSelector(_cmd),
		    (unsigned long)range.location, (unsigned long)range.length, (unsigned long)pageOffset);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Description
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	return [pageInfos description];
}

@end
