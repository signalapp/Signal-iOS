#import "YapCollectionsDatabaseFilteredView.h"
#import "YapCollectionsDatabaseFilteredViewPrivate.h"


@implementation YapCollectionsDatabaseFilteredView

#pragma mark Invalid

- (id)initWithGroupingBlock:(YapCollectionsDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapCollectionsDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapCollectionsDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapCollectionsDatabaseViewBlockType)inSortingBlockType
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                           version:0
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapCollectionsDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapCollectionsDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapCollectionsDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapCollectionsDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                           version:inVersion
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapCollectionsDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapCollectionsDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapCollectionsDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapCollectionsDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
                    options:(YapCollectionsDatabaseViewOptions *)inOptions
{
	// Todo: Throw exception
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize parentViewName = parentViewName;

@synthesize filteringBlock = filteringBlock;
@synthesize filteringBlockType = filteringBlockType;

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)inFilteringBlockType
{
	return [self initWithParentViewName:inParentViewName
	                     filteringBlock:inFilteringBlock
	                 filteringBlockType:inFilteringBlockType
	                            version:0
	                            options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)inFilteringBlockType
                     version:(int)inVersion
{
	return [self initWithParentViewName:inParentViewName
	                     filteringBlock:inFilteringBlock
	                 filteringBlockType:inFilteringBlockType
	                            version:inVersion
	                            options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapCollectionsDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapCollectionsDatabaseViewBlockType)inFilteringBlockType
                     version:(int)inVersion
                     options:(YapCollectionsDatabaseViewOptions *)inOptions
{
	NSAssert(inParentViewName != nil, @"Invalid parentViewName");
	NSAssert(inFilteringBlock != NULL, @"Invalid filteringBlock");
	
	NSAssert(inFilteringBlockType == YapCollectionsDatabaseViewBlockTypeWithKey ||
	         inFilteringBlockType == YapCollectionsDatabaseViewBlockTypeWithObject ||
	         inFilteringBlockType == YapCollectionsDatabaseViewBlockTypeWithMetadata ||
	         inFilteringBlockType == YapCollectionsDatabaseViewBlockTypeWithRow,
	         @"Invalid filteringBlockType");
	
	if ((self = [super init]))
	{
		parentViewName = [inParentViewName copy];
		
		filteringBlock = inFilteringBlock;
		filteringBlockType = inFilteringBlockType;
		
		version = inVersion;
		
		options = inOptions ? [inOptions copy] : [[YapCollectionsDatabaseViewOptions alloc] init];
	}
	return self;
}

- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	__unsafe_unretained YapCollectionsDatabaseConnection *dbConnection =
	  (YapCollectionsDatabaseConnection *)databaseConnection;
	
	return [[YapCollectionsDatabaseFilteredViewConnection alloc] initWithView:self databaseConnection:dbConnection];
}

@end
