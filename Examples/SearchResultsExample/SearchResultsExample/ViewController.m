#import "ViewController.h"
#import "AppDelegate.h"
#import "Person.h"
#import "DDLog.h"

// Per-file log level for CocoaLumbejack (logging framework)
#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_VERBOSE;
#else
  static const int ddLogLevel = LOG_LEVEL_WARN;
#endif


@implementation ViewController
{
	YapDatabaseConnection *databaseConnection;
	
	YapDatabaseViewMappings *mainMappings;
	YapDatabaseViewMappings *searchMappings;
}

@synthesize tableView = tableView;
@synthesize searchBar = searchBar;

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	databaseConnection = [TheAppDelegate.database newConnection];
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
	                                           object:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)initializeMappings
{
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
	NSArray *notifications = [databaseConnection beginLongLivedReadTransaction];
	
	// Todo...
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// One time initialization
		[mainMappings updateWithTransaction:transaction];
		[searchMappings updateWithTransaction:transaction];
	}];
	
	[tableView reloadData];
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
	if (sender == tableView) {
		return [mainMappings numberOfItemsInGroup:@"all"];
	}
	else {
		return [searchMappings numberOfItemsInGroup:@"all"];
	}
}

- (UITableViewCell *)tableView:(UITableView *)sender cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ydb"];
	if (cell == nil)
	{
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ydb"];
	}
	
	__block Person *person = nil;
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		if (sender == tableView) {
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

@end
