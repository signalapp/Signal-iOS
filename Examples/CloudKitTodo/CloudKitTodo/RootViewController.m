#import "RootViewController.h"
#import "EditViewController.h"
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
	
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(cloudKitSuspendCountChanged:)
	                                             name:YapDatabaseCloudKitSuspendCountChangedNotification
	                                           object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(cloudKitInFlightChangeSetChanged:)
	                                             name:YapDatabaseCloudKitInFlightChangeSetChangedNotification
	                                           object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	[self updateStatusLabels];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database Stuff
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
	[self updateStatusLabels];
	
	if (mappings == nil)
	{
		[self initializeMappings];
		[self.tableView reloadData];
		
		return;
	}
	
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];
	
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

- (void)cloudKitSuspendCountChanged:(NSNotification *)notification
{
	[self updateStatusLabels];
}

- (void)cloudKitInFlightChangeSetChanged:(NSNotification *)notification
{
	[self updateStatusLabels];
}

- (MyTodo *)todoAtIndexPath:(NSIndexPath *)indexPath
{
	__block MyTodo *todo = nil;
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		todo = [[transaction ext:Ext_View_Order] objectAtIndexPath:indexPath withMappings:mappings];
	}];
	
	return todo;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Status
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateStatusLabels
{
	NSUInteger suspendCount = [MyDatabaseManager.cloudKitExtension suspendWithCount:0];
	if (suspendCount > 0)
	{
		self.ckTopStatusLabel.text =
		  [NSString stringWithFormat:@"Status: Suspended (suspendCount = %lu)", (unsigned long)suspendCount];
	}
	else
	{
		self.ckTopStatusLabel.text = @"Status: Resumed";
	}
	
	NSUInteger inFlightCount = 0;
	NSUInteger queuedCount = 0;
	[MyDatabaseManager.cloudKitExtension getNumberOfInFlightChangeSets:&inFlightCount queuedChangeSets:&queuedCount];
	
	self.ckBottomStatusLabel.text =
	  [NSString stringWithFormat:@"ChangeSets: InFlight(%lu), Queued(%lu)",
	   (unsigned long)inFlightCount,
	   (unsigned long)queuedCount];
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
	
	MyTodo *todo = [self todoAtIndexPath:indexPath];
	
	cell.textLabel.text = todo.title;
	
	return cell;
}

- (void)tableView:(UITableView *)sender didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	MyTodo *todo = [self todoAtIndexPath:indexPath];
	
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
	EditViewController *evc = [storyboard instantiateViewControllerWithIdentifier:@"EditViewController"];
	
	evc.todoID = todo.uuid;
	
	[self.navigationController pushViewController:evc animated:YES];
	[self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (NSArray *)tableView:(UITableView *)sender editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewRowAction *deleteAction =
	  [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
	                                     title:@"Delete"
	                                   handler:^(UITableViewRowAction *action, NSIndexPath *indexPath)
	{
		MyTodo *todo = [self todoAtIndexPath:indexPath];
		
		YapDatabaseConnection *rwDatabaseConnection = MyDatabaseManager.bgDatabaseConnection;
		[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			[transaction removeObjectForKey:todo.uuid inCollection:Collection_Todos];
			
		} completionBlock:^{
			
			[self updateStatusLabels];
		}];
	}];
	
	return @[ deleteAction ];
}

- (void)tableView:(UITableView *)sender commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                         forRowAtIndexPath:(NSIndexPath *)indexPath
{
	// No statement or algorithm is needed in here. Just the implementation
}

@end
