#import "RootViewController.h"
#import "DatabaseManager.h"
#import "CloudKitManager.h"
#import "MyTodo.h"

#import "DDLog.h"

// Log Levels: off, error, warn, info, verbose
#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_ALL;
#else
  static const int ddLogLevel = LOG_LEVEL_ALL;
#endif


@implementation RootViewController
{
	YapDatabaseConnection *databaseConnection;
	YapDatabaseViewMappings *mappings;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	// Set tableView insets to be above ckStatusView
	
	CGRect ckViewFrame = self.ckStatusView.frame;
	
	UIEdgeInsets insets = self.tableView.scrollIndicatorInsets;
	insets.bottom = ckViewFrame.size.height;
	
	self.tableView.contentInset = insets;
	self.tableView.scrollIndicatorInsets = insets;
	
	// Configure database stuff
	
	databaseConnection = MyDatabaseManager.uiDatabaseConnection;
	[self initializeMappings];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(databaseConnectionDidUpdate:)
	                                             name:UIDatabaseConnectionDidUpdateNotification
	                                           object:nil];
}

- (void)initializeMappings
{
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		if ([transaction ext:Ext_View_Order])
		{
			mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[@""] view:Ext_View_Order];
			[mappings updateWithTransaction:transaction];
		}
		else
		{
			// The view isn't ready yet.
			// We'll try again when we get a databaseConnectionDidUpdate notification.
		}
	}];
}

- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];
	
	if (mappings == nil)
	{
		[self initializeMappings];
		[self.tableView reloadData];
		
		return;
	}
	
	NSArray *rowChanges = nil;
	[[databaseConnection ext:Ext_View_Order] getSectionChanges:NULL
	                                                rowChanges:&rowChanges
	                                          forNotifications:notifications
	                                              withMappings:mappings];
	
	if ([rowChanges count] == 0)
	{
		// There aren't any changes that affect our tableView
		return;
	}
	
	[self.tableView beginUpdates];
	
	for (YapDatabaseViewRowChange *rowChange in rowChanges)
	{
		switch (rowChange.type)
		{
			case YapDatabaseViewChangeDelete :
			{
				[self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
				                      withRowAnimation:UITableViewRowAnimationFade];
				break;
			}
			case YapDatabaseViewChangeInsert :
			{
				[self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
				                      withRowAnimation:UITableViewRowAnimationFade];
				break;
			}
			case YapDatabaseViewChangeMove :
			{
				[self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
				                      withRowAnimation:UITableViewRowAnimationFade];
				[self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
				                      withRowAnimation:UITableViewRowAnimationFade];
				break;
			}
			case YapDatabaseViewChangeUpdate :
			{
				[self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
				                      withRowAnimation:UITableViewRowAnimationFade];
				break;
			}
		}
	}

	[self.tableView endUpdates];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)suspendButtonTapped:(id)sender
{
	DDLogVerbose(@"RootViewController - suspendButtonTapped:");
	
	[MyDatabaseManager.cloudKitExtension suspend];
}

- (IBAction)resumeButtonTapped:(id)sender
{
	DDLogVerbose(@"RootViewController - resumeButtonTapped:");
	
	[MyDatabaseManager.cloudKitExtension resume];
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
	return [mappings numberOfItemsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)sender cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"id"];
	if (cell == nil)
	{
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"id"];
	}
	
	__block MyTodo *todo = nil;
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		todo = [[transaction ext:Ext_View_Order] objectAtIndexPath:indexPath withMappings:mappings];
	}];
	
	cell.textLabel.text = todo.title;
	
	return cell;
}

@end
