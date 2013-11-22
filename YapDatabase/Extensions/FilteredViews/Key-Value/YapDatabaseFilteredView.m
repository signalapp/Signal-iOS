#import "YapDatabaseFilteredView.h"
#import "YapDatabaseFilteredViewPrivate.h"


@implementation YapDatabaseFilteredView

#pragma mark Invalid

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                           version:0
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                           version:inVersion
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
                    options:(YapDatabaseViewOptions *)inOptions
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
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
{
	return [self initWithParentViewName:inParentViewName
	                     filteringBlock:inFilteringBlock
	                 filteringBlockType:inFilteringBlockType
	                            version:0
	                            options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
                     version:(int)inVersion
{
	return [self initWithParentViewName:inParentViewName
	                     filteringBlock:inFilteringBlock
	                 filteringBlockType:inFilteringBlockType
	                            version:inVersion
	                            options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
                     version:(int)inVersion
                     options:(YapDatabaseViewOptions *)inOptions
{
	NSAssert(inParentViewName != nil, @"Invalid parentViewName");
	NSAssert(inFilteringBlock != NULL, @"Invalid filteringBlock");
	
	NSAssert(inFilteringBlockType == YapDatabaseViewBlockTypeWithKey ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithObject ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithMetadata ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithRow,
	         @"Invalid filteringBlockType");
	
	if ((self = [super init]))
	{
		parentViewName = [inParentViewName copy];
		
		filteringBlock = inFilteringBlock;
		filteringBlockType = inFilteringBlockType;
		
		version = inVersion;
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseViewOptions alloc] init];
	}
	return self;
}

- (YapAbstractDatabaseExtensionConnection *)newConnection:(YapAbstractDatabaseConnection *)databaseConnection
{
	__unsafe_unretained YapDatabaseConnection *dbConnection = (YapDatabaseConnection *)databaseConnection;
	
	return [[YapDatabaseFilteredViewConnection alloc] initWithView:self databaseConnection:dbConnection];
}

@end
