#import "ViewController.h"
#import "AppDelegate.h"
#import "Person.h"

#import <CocoaLumberjack/CocoaLumberjack.h>

// Per-file log level for CocoaLumbejack (logging framework)
#if DEBUG
  static const int ddLogLevel = DDLogLevelVerbose;
#else
  static const int ddLogLevel = DDLogLevelWarn;
#endif
#pragma unused(ddLogLevel)


@implementation ViewController
{
	YapDatabaseConnection *databaseConnection;
	
	YapDatabaseViewMappings *mainMappings;
	YapDatabaseViewMappings *searchMappings;
	
	UISearchDisplayController *searchController;
	
	YapDatabaseConnection *searchConnection;
	YapDatabaseSearchQueue *searchQueue;
}

@synthesize mainTableView = mainTableView;

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	// Setup search bar & controller
	
	UISearchBar *searchBar = [[UISearchBar alloc] init];
	
	searchController = [[UISearchDisplayController alloc] initWithSearchBar:searchBar contentsController:self];
	searchController.delegate = self;
	searchController.searchResultsDataSource = self;
	searchController.searchResultsDelegate = self;
	
	mainTableView.tableHeaderView = searchBar;
	
	// Setup database
	
	YapDatabase *database = TheAppDelegate.database;
	
	databaseConnection = [database newConnection];
	databaseConnection.objectCacheLimit = 500;
	databaseConnection.metadataCacheEnabled = NO; // not using metadata in this example
	
	// What is a long-lived read transaction?
	// https://github.com/yaptv/YapDatabase/wiki/LongLivedReadTransactions
	
	[databaseConnection beginLongLivedReadTransaction];
	[self initializeMappings];
	
	// What is YapDatabaseModifiedNotification?
	// https://github.com/yaptv/YapDatabase/wiki/YapDatabaseModifiedNotification
	
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(databaseModified:)
	                                             name:YapDatabaseModifiedNotification
	                                           object:database];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)initializeMappings
{
	// What the heck are mappings?
	// https://github.com/yaptv/YapDatabase/wiki/Views#mappings
	
	mainMappings   = [[YapDatabaseViewMappings alloc] initWithGroups:@[ @"all" ] view:@"order"];
	searchMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[ @"all" ] view:@"searchResults"];
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// One time initialization
		[mainMappings updateWithTransaction:transaction];
		[searchMappings updateWithTransaction:transaction];
	}];
}

- (void)databaseModified:(NSNotification *)ignored
{
	// This method is invoked (on the main-thread) after a readWriteTransaction (commit) has completed.
	// The commit could come from any databaseConnection (from our database).
	
	// Our databaseConnection is "frozen" on a particular commit. (via longLivedReadTransaction)
	// We do this in order to provide a stable data source for the UI.
	//
	// What we're going to do now is move our connection from it's current commit to the latest commit.
	// This is done atomically.
	// And we may jump multiple commits when we make this jump.
	// The notifications array gives us the details on each commit.
	//
	// This process/architecture is detailed in the following wiki articles:
	//
	// https://github.com/yaptv/YapDatabase/wiki/LongLivedReadTransactions
	// https://github.com/yaptv/YapDatabase/wiki/YapDatabaseModifiedNotification
	
	NSArray *notifications = [databaseConnection beginLongLivedReadTransaction];
	
	// Now that we've updated our "frozen" databaseConnection to the latest commit,
	// we need to update the tableViews (mainTableView & searchResultsTableView).
	//
	// Note: The code below is pretty much boiler-plate update code:
	// https://github.com/yaptv/YapDatabase/wiki/Views#full_animation_example
	//
	// The only difference here is that we have 2 tableViews to update (instead of just 1).
	
	NSArray *rowChanges = nil;
	
	// Update mainTableView
	
	DDLogVerbose(@"Calculating rowChanges for mainTableView...");
	[[databaseConnection ext:@"order"] getSectionChanges:NULL
	                                          rowChanges:&rowChanges
	                                    forNotifications:notifications
	                                        withMappings:mainMappings];
	
	DDLogVerbose(@"Processing rowChanges for mainTableView...");
	
	if ([rowChanges count] > 0)
	{
		UITableView *tableView = mainTableView;
		[tableView beginUpdates];
		
		for (YapDatabaseViewRowChange *rowChange in rowChanges)
		{
			switch (rowChange.type)
			{
				case YapDatabaseViewChangeDelete :
				{
					[tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
					                 withRowAnimation:UITableViewRowAnimationAutomatic];
					break;
				}
				case YapDatabaseViewChangeInsert :
				{
					[tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
					                 withRowAnimation:UITableViewRowAnimationAutomatic];
					break;
				}
				case YapDatabaseViewChangeMove :
				{
					[tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
					                 withRowAnimation:UITableViewRowAnimationAutomatic];
					[tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
					                 withRowAnimation:UITableViewRowAnimationAutomatic];
					break;
				}
				case YapDatabaseViewChangeUpdate :
				{
					[tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
					                 withRowAnimation:UITableViewRowAnimationNone];
					break;
				}
			}
		}
		
		[tableView endUpdates];
	}
	
	// Update searchResultsTableView
	
	rowChanges = nil;
	
	DDLogVerbose(@"Calculating rowChanges for searchResultsTableView...");
	[[databaseConnection ext:@"searchResults"] getSectionChanges:NULL
	                                                  rowChanges:&rowChanges
	                                            forNotifications:notifications
	                                                withMappings:searchMappings];
	
	DDLogVerbose(@"Processing rowChanges for searchResultsTableView...");
	
	if ([rowChanges count] > 0)
	{
		UITableView *tableView = searchController.searchResultsTableView;
		[tableView beginUpdates];
		
		for (YapDatabaseViewRowChange *rowChange in rowChanges)
		{
			switch (rowChange.type)
			{
				case YapDatabaseViewChangeDelete :
				{
					[tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
					                 withRowAnimation:UITableViewRowAnimationAutomatic];
					break;
				}
				case YapDatabaseViewChangeInsert :
				{
					[tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
					                 withRowAnimation:UITableViewRowAnimationAutomatic];
					break;
				}
				case YapDatabaseViewChangeMove :
				{
					[tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
					                 withRowAnimation:UITableViewRowAnimationAutomatic];
					[tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
					                 withRowAnimation:UITableViewRowAnimationAutomatic];
					break;
				}
				case YapDatabaseViewChangeUpdate :
				{
					[tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
					                 withRowAnimation:UITableViewRowAnimationNone];
					break;
				}
			}
		}
		
		[tableView endUpdates];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableView
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)numberOfSectionsInTableView:(UITableView *)sender
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)sender numberOfRowsInSection:(NSInteger)section
{
	if (sender == mainTableView) {
		return [mainMappings numberOfItemsInGroup:@"all"];
	}
	else {
		return [searchMappings numberOfItemsInGroup:@"all"];
	}
}

- (UITableViewCell *)tableView:(UITableView *)sender cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString *identifier = @"ydb";
	
	UITableViewCell *cell = nil;
	if (sender == mainTableView)
	{
		cell = [mainTableView dequeueReusableCellWithIdentifier:identifier];
		if (cell == nil) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
		}
	}
	else
	{
		cell = [searchController.searchResultsTableView dequeueReusableCellWithIdentifier:identifier];
		if (cell == nil) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
		}
	}
	
	__block Person *person = nil;
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		if (sender == mainTableView) {
			person = [[transaction ext:@"order"] objectAtIndex:indexPath.row inGroup:@"all"];
		}
		else {
			person = [[transaction ext:@"searchResults"] objectAtIndex:indexPath.row inGroup:@"all"];
		}
	}];
	
	cell.textLabel.text = person.name;
	cell.detailTextLabel.text = person.uuid;
	
	return cell;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UISearchDisplayController
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)searchDisplayController:(UISearchDisplayController *)controller
  didLoadSearchResultsTableView:(UITableView *)sender
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayController:(UISearchDisplayController *)controller
    willUnloadSearchResultsTableView:(UITableView *)sender
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayController:(UISearchDisplayController *)controller
     willShowSearchResultsTableView:(UITableView *)searchTableView
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayController:(UISearchDisplayController *)controller
    didShowSearchResultsTableView:(UITableView *)searchTableView
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayController:(UISearchDisplayController *)controller
    willHideSearchResultsTableView:(UITableView *)searchTableView
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayController:(UISearchDisplayController *)controller
    didHideSearchResultsTableView:(UITableView *)searchTableView
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayControllerWillBeginSearch:(UISearchDisplayController *)controller
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayControllerDidBeginSearch:(UISearchDisplayController *)controller
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayControllerWillEndSearch:(UISearchDisplayController *)controller
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (void)searchDisplayControllerDidEndSearch:(UISearchDisplayController *)controller
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
}

- (BOOL)searchDisplayController:(UISearchDisplayController *)controller
    shouldReloadTableForSearchString:(NSString *)searchString
{
	DDLogVerbose(@"%@ - %@ (%@)", THIS_FILE, THIS_METHOD, searchString);
	
	if (searchConnection == nil)
		searchConnection = [TheAppDelegate.database newConnection];
	
	if (searchQueue == nil)
		searchQueue = [[YapDatabaseSearchQueue alloc] init];
	
	// Parse the text into a proper search query
	
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
	
	NSArray *searchComponents = [searchString componentsSeparatedByCharactersInSet:whitespace];
	NSMutableString *query = [NSMutableString string];
	
	for (NSString *term in searchComponents)
	{
		if ([term length] > 0)
			[query appendString:@""];
		
		[query appendFormat:@"%@*", term];
	}
	
	DDLogVerbose(@"searchString(%@) -> query(%@)", searchString, query);
	
	[searchQueue enqueueQuery:query];
	
	[searchConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:@"searchResults"] performSearchWithQueue:searchQueue];
	}];
	
	return NO;
}

@end
