#import "ViewController.h"

#import "AppDelegate.h"
#import "MYTableViewCell.h"
#import "Person.h"

#import <CocoaLumberjack/CocoaLumberjack.h>

#import <stdlib.h>

// Per-file log level for CocoaLumbejack (logging framework)
#if DEBUG
  static const int ddLogLevel = DDLogLevelVerbose;
#else
  static const int ddLogLevel = DDLogLevelWarn;
#endif
#pragma unused(ddLogLevel)

static NSString *const SkipAnimationFlag = @"SkipAnimationFlag";


@implementation ViewController {
	
	IBOutlet UITableView *tableView;
	
	IBOutlet UIView *topControlView;
	IBOutlet UIView *bottomControlView;
	
	IBOutlet UIButton *editButton;
	IBOutlet UIButton *plusButton;
	IBOutlet UIButton *minusButton;
	IBOutlet UIButton *closeButton;
	IBOutlet UIButton *questionButton;
	IBOutlet UILabel *statusLabel;
	
	YapDatabaseConnection *roDatabaseConnection;
	YapDatabaseConnection *rwDatabaseConnection;
	YapDatabaseViewMappings *mappings;
	
	NSMutableArray<NSString *> *remainingKeys;
}

- (void)viewDidLoad
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
	[super viewDidLoad];
	
	CGFloat topControlViewHeight = topControlView.frame.size.height;
	CGFloat bottomControlViewHeight = bottomControlView.frame.size.height;
	
	UIEdgeInsets contentInsets = tableView.contentInset;
	UIEdgeInsets scrollInsets = tableView.scrollIndicatorInsets;
	
	contentInsets.top += topControlViewHeight;
	scrollInsets.top += topControlViewHeight;
	
	contentInsets.bottom += bottomControlViewHeight;
	scrollInsets.bottom += bottomControlViewHeight;
	
	tableView.contentInset = contentInsets;
	tableView.scrollIndicatorInsets = scrollInsets;
	
	[self initializeDatabaseConnection];
	[self enableDisableButtons];
	
	if (remainingKeys == nil)
	{
		[self setStatusLabelText:@"Populating database...." disappearAfter:0.0];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The AppDelegate invokes this method after it's prepared the database for us.
 *
 * The 'remainingKeys' parameter is a list of all keys (Person.uuid) that exist in the database,
 * but that are not contained within the manualView. In other words, when the user hits the 'plus'
 * button, we can randomly select a key from this array, and then add that person to the manualView.
**/
- (void)setRemainingKeys:(NSArray<NSString *> *)inRemainingKeys
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
	NSAssert([NSThread isMainThread], @"Must be invoked on main thread/queue.");
	
	remainingKeys = [inRemainingKeys mutableCopy];
	
	// Now that we have the data we need,
	// we can configure our databaseConnection & mappings.
	
	[self initializeDatabaseConnection];
	
	// What is a long-lived read transaction?
	// https://github.com/yaptv/YapDatabase/wiki/LongLivedReadTransactions
	
	[roDatabaseConnection beginLongLivedReadTransaction];
	
	// What the heck are mappings?
	// https://github.com/yaptv/YapDatabase/wiki/Views#mappings
	
	mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[ ManualView_GroupName ] view:ManualView_RegisteredName];
	
	[roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		// One time initialization
		[mappings updateWithTransaction:transaction];
	}];
	
	// What is YapDatabaseModifiedNotification?
	// https://github.com/yaptv/YapDatabase/wiki/YapDatabaseModifiedNotification
	
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(databaseModified:)
	                                             name:YapDatabaseModifiedNotification
	                                           object:roDatabaseConnection.database];
	
	// Refresh UI
	
	[tableView reloadData];
	[self enableDisableButtons];
	
	// Update statusLabel
	
	if ([mappings numberOfItemsInGroup:ManualView_GroupName] == 0)
		[self setStatusLabelText:@"Tap plus button" disappearAfter:0.0];
	else
		[self setStatusLabelText:@"Ready" disappearAfter:3.0];
}

- (void)initializeDatabaseConnection
{
	if (roDatabaseConnection == nil)
	{
		YapDatabase *database = TheAppDelegate.database;
		
		roDatabaseConnection = [database newConnection];
		roDatabaseConnection.objectCacheLimit = 500;
		roDatabaseConnection.metadataCacheEnabled = NO; // not using metadata in this example
		
		rwDatabaseConnection = [database newConnection];
		rwDatabaseConnection.objectCacheLimit = 100;
		rwDatabaseConnection.metadataCacheEnabled = NO; // not using metadata in this example
	}
}

- (void)databaseModified:(NSNotification *)ignored
{
	// This method is invoked (on the main-thread) after a readWriteTransaction (commit) has completed.
	// The commit could come from any databaseConnection (from our database).
	
	NSString *prevSelectedKey = nil;
	
	NSIndexPath *prevSelectedIndexPath = [tableView indexPathForSelectedRow];
	if (prevSelectedIndexPath)
	{
		prevSelectedKey = [self keyForIndexPath:prevSelectedIndexPath];
	}
	
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
	
	NSArray *notifications = [roDatabaseConnection beginLongLivedReadTransaction];
	
	// Now that we've updated our "frozen" databaseConnection to the latest commit,
	// we need to update the tableViews (mainTableView & searchResultsTableView).
	//
	// Note: The code below is pretty much boiler-plate update code:
	// https://github.com/yaptv/YapDatabase/wiki/Views#full_animation_example
	//
	// The only difference here is that we have 2 tableViews to update (instead of just 1).
	
	NSArray *rowChanges = nil;
	
	// Update tableView (with animations)
	
	[[roDatabaseConnection ext:ManualView_RegisteredName] getSectionChanges:NULL
	                                                             rowChanges:&rowChanges
	                                                       forNotifications:notifications
	                                                           withMappings:mappings];
	
	if ([rowChanges count] == 0)
	{
		// Nothing to do here.
		// Commit didn't modify anything represented via mappings.
		return;
	}
	
	// Should we skip the tableView animations ?
	//
	// We should if this is only a change from 'tableView:moveRowAtIndexPath:toIndexPath:'.
	
	BOOL shouldSkipAnimation = YES;
	
	for (NSNotification *notification in notifications)
	{
		id flag = notification.userInfo[YapDatabaseCustomKey];
		if (flag != SkipAnimationFlag)
		{
			shouldSkipAnimation = NO;
		}
	}
	
	if (shouldSkipAnimation)
	{
		[tableView reloadData];
	}
	else
	{
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
	
	if (prevSelectedKey) // maintain previous selection
	{
		NSIndexPath *indexPath = [self indexPathForKey:prevSelectedKey];
		if (indexPath) {
			[tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSIndexPath *)indexPathForKey:(NSString *)key
{
	__block NSIndexPath *indexPath = nil;
	
	[roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		indexPath = [[transaction ext:ManualView_RegisteredName] indexPathForKey:key
		                                                            inCollection:@"people"
		                                                            withMappings:mappings];
	}];
	
	return indexPath;
}

- (NSString *)keyForIndexPath:(NSIndexPath *)indexPath
{
	__block NSString *key = nil;
	
	[roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[[transaction ext:ManualView_RegisteredName] getKey:&key
		                                         collection:NULL
		                                        atIndexPath:indexPath
		                                       withMappings:mappings];
	}];
	
	return key;
}

- (Person *)personForIndexPath:(NSIndexPath *)indexPath
{
	__block Person *person = nil;
	
	[roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		person = [[transaction ext:ManualView_RegisteredName] objectAtIndexPath:indexPath withMappings:mappings];
	}];
	
	return person;
}

- (void)removePersonAtIndexPath:(NSIndexPath *)indexPath
{
	NSString *key = [self keyForIndexPath:indexPath];
	if (key == nil) {
		return;
	}
	
	[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:ManualView_RegisteredName] removeKey:key
		                                          inCollection:@"people"
		                                             fromGroup:ManualView_GroupName];
		
	} completionBlock:^{
		
		[self enableDisableButtons];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark IBActions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)editButtonTapped:(id)sender
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	if ([tableView isEditing])
	{
		[tableView setEditing:NO animated:YES];
		[editButton setTitle:@"Edit Table" forState:UIControlStateNormal];
	}
	else
	{
		[tableView setEditing:YES animated:YES];
		[editButton setTitle:@"Done" forState:UIControlStateNormal];
	}
}

- (IBAction)plusButtonTapped:(id)sender
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	uint32_t upperBound = (uint32_t)remainingKeys.count;
	uint32_t random = arc4random_uniform(upperBound);
	
	NSString *key = [remainingKeys objectAtIndex:(NSUInteger)random];
	[remainingKeys removeObjectAtIndex:(NSUInteger)random];
	
	[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:ManualView_RegisteredName] addKey:key inCollection:@"people" toGroup:ManualView_GroupName];
		
	} completionBlock:^{
		
		// Back on the main thread
		
		NSIndexPath *indexPath = [self indexPathForKey:key];
		if (indexPath)
		{
			// Perform a little animation to show & highlight the added row.
			
			[tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
			
			MYTableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
			[cell flash];
		}
	}];
	
	[self setStatusLabelText:@"Added person" disappearAfter:3.0];
}

- (IBAction)minusButtonTapped:(id)sender
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	NSIndexPath *selectedIndexPath = [tableView indexPathForSelectedRow];
	if (selectedIndexPath)
	{
		[self removePersonAtIndexPath:selectedIndexPath];
		[self setStatusLabelText:@"Removed person" disappearAfter:3.0];
	}
}

- (IBAction)closeButtonTapped:(id)sender
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[[transaction ext:ManualView_RegisteredName] removeAllItemsInGroup:ManualView_GroupName];
	}];
	
	[self setStatusLabelText:@"Cleared people" disappearAfter:3.0];
}

- (IBAction)questionButtonTapped:(id)sender
{
	DDLogVerbose(@"%@ - %@", THIS_FILE, THIS_METHOD);
	
	dispatch_block_t addRandomPersonBlock = ^{
		
		[self plusButtonTapped:nil];
	};
	
	dispatch_block_t removeRandomPersonBlock = ^{
		
		uint32_t upperBound = (uint32_t)[mappings numberOfItemsInGroup:ManualView_GroupName];
		uint32_t random = arc4random_uniform(upperBound);
		
		NSIndexPath *randomIndexPath = [NSIndexPath indexPathForRow:random inSection:0];
		
		[self removePersonAtIndexPath:randomIndexPath];
		[self setStatusLabelText:@"Removed random person" disappearAfter:3.0];
 	};
	
	dispatch_block_t moveRandomPersonBlock = ^{
		
		[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			YapDatabaseManualViewTransaction *ext = [transaction ext:ManualView_RegisteredName];
			
			NSUInteger count = [ext numberOfItemsInGroup:ManualView_GroupName];
			if (count < 2) {
				return;
			}
			
			uint32_t upperBound = (uint32_t)count;
			uint32_t oldIndex = arc4random_uniform(upperBound);
			
			upperBound--;
			
			uint32_t newIndex = 0;
			do {
				newIndex = arc4random_uniform(upperBound);
				
			} while (oldIndex == newIndex);
			
			NSString *key = nil;
			[ext getKey:&key collection:NULL atIndex:oldIndex inGroup:ManualView_GroupName];
			
			Person *person = [transaction objectForKey:key inCollection:@"people"];
			
			NSLog(@"person(%@) oldIndex(%u) newIndex(%u)", person.name, oldIndex, newIndex);
			
			[ext removeItemAtIndex:oldIndex inGroup:ManualView_GroupName];
			[ext insertKey:key inCollection:@"people" atIndex:newIndex inGroup:ManualView_GroupName];
		}];
		
		[self setStatusLabelText:@"Moved random person" disappearAfter:3.0];
	};
	
	NSMutableArray<dispatch_block_t> *operations = [NSMutableArray arrayWithCapacity:3];
	
	[operations addObject:addRandomPersonBlock];
	
	if ([mappings numberOfItemsInGroup:ManualView_GroupName] > 0) {
		[operations addObject:removeRandomPersonBlock];
	}
	
	if ([mappings numberOfItemsInGroup:ManualView_GroupName] >= 2) {
		[operations addObject:moveRandomPersonBlock];
	}
	
	uint32_t upperBound = (uint32_t)operations.count;
	uint32_t random = arc4random_uniform(upperBound);
	
	dispatch_block_t randomBlock = operations[random];
	randomBlock();
}

- (void)enableDisableButtons
{
	if (remainingKeys == nil)
	{
		editButton.enabled = NO;
		plusButton.enabled = NO;
		minusButton.enabled = NO;
		closeButton.enabled = NO;
		questionButton.enabled = NO;
	}
	else
	{
		editButton.enabled = ([mappings numberOfItemsInGroup:ManualView_GroupName] > 0);
		plusButton.enabled = (remainingKeys.count > 0);
		minusButton.enabled = ([tableView indexPathForSelectedRow] != nil);
		closeButton.enabled = ([mappings numberOfItemsInGroup:ManualView_GroupName] > 0);
		questionButton.enabled = YES;
	}
}

- (void)setStatusLabelText:(NSString *)text disappearAfter:(NSTimeInterval)disappearDelay
{
	statusLabel.text = text;
	
	NSInteger tag = statusLabel.tag + 1;
	statusLabel.tag = tag;
	
	if (disappearDelay > 0.0)
	{
		dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(disappearDelay * NSEC_PER_SEC));
		dispatch_after(delay, dispatch_get_main_queue(), ^{
			
			if (statusLabel.tag == tag) // Still same as before
			{
				statusLabel.text = nil;
			}
		});
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
	return [mappings numberOfItemsInGroup:ManualView_GroupName];
}

- (UITableViewCell *)tableView:(UITableView *)sender cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString *identifier = @"MYTableViewCell";
	MYTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	
	__block Person *person = nil;
	
	[roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		person = [[transaction ext:ManualView_RegisteredName] objectAtIndexPath:indexPath withMappings:mappings];
	}];
	
	cell.nameLabel.text = person.name;
	cell.showsReorderControl = YES;

	return cell;
}

- (void)tableView:(UITableView *)sender didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[self enableDisableButtons];
}

- (void)tableView:(UITableView *)sender didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[self enableDisableButtons];
}

- (void)tableView:(UITableView *)sender commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
                                         forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete)
	{
		[self removePersonAtIndexPath:indexPath];
		[self setStatusLabelText:@"Removed person" disappearAfter:3.0];
	}
}

- (BOOL)tableView:(UITableView *)sender canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}

- (void)tableView:(UITableView *)sender moveRowAtIndexPath:(NSIndexPath *)srcIndexPath
                                               toIndexPath:(NSIndexPath *)dstIndexPath
{
	NSString *key = [self keyForIndexPath:srcIndexPath];
	
	NSUInteger srcIndex = 0;
	NSUInteger dstIndex = 0;
	
	[mappings getGroup:NULL index:&srcIndex forIndexPath:srcIndexPath];
	[mappings getGroup:NULL index:&dstIndex forIndexPath:dstIndexPath];
	
	[rwDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		YapDatabaseManualViewTransaction *ext = [transaction ext:ManualView_RegisteredName];
		
		[ext removeItemAtIndex:srcIndex inGroup:ManualView_GroupName];
		[ext insertKey:key inCollection:@"people" atIndex:dstIndex inGroup:ManualView_GroupName];
		
		// The tableView acts goofy if we attempt to animate the change mid-move.
		// So we set a flag that 'databaseModified' can read,
		// in order to tell it to skip the animation stuff for this commit.
		
		transaction.yapDatabaseModifiedNotificationCustomObject = SkipAnimationFlag;
	}];
	
	[self setStatusLabelText:@"Moved person" disappearAfter:3.0];
}

@end
