#import "EditViewController.h"
#import "DatabaseManager.h"
#import "MyTodo.h"


@implementation EditViewController
{
	YapDatabaseConnection *databaseConnection;
}

@synthesize todoID = todoID;

@synthesize titleView = titleView;

@synthesize titleViewHeightConstraint = titleViewHeightConstraint;
@synthesize titleViewMinHeightConstraint = titleViewMinHeightConstraint;
@synthesize titleViewMaxHeightConstraint = titleViewMaxHeightConstraint;

@synthesize checkmarkButton = checkmarkButton;
@synthesize priority = priority;

@synthesize uuidLabel = uuidLabel;
@synthesize creationDateLabel = creationDateLabel;
@synthesize lastModifiedLabel = lastModifiedLabel;

@synthesize baseRecordLabel = baseRecordLabel;

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	titleView.textColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
	
	titleView.layer.borderColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0].CGColor;
	titleView.layer.borderWidth = 1.75;
	titleView.layer.cornerRadius = 5.5;
	
	titleView.delegate = self;
	
	UIEdgeInsets modifiedInsets = titleView.textContainerInset;
	modifiedInsets.top -= 2;
	modifiedInsets.bottom -= 2;
	titleView.textContainerInset = modifiedInsets;
	
	self.navigationItem.leftBarButtonItem =
	  [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                target:self
	                                                action:@selector(cancelButtonTapped:)];
	
	self.navigationItem.rightBarButtonItem =
	  [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
	                                                target:self
	                                                action:@selector(saveButtonTapped:)];
	
	databaseConnection = MyDatabaseManager.uiDatabaseConnection;
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(databaseConnectionDidUpdate:)
	                                             name:UIDatabaseConnectionDidUpdateNotification
	                                           object:nil];
	
	[self updateView];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self textViewDidChange:titleView];
	});
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	[titleView becomeFirstResponder];
}

- (void)setTodoID:(NSString *)newTodoID
{
	todoID = newTodoID;
	
	if (self.isViewLoaded) {
		[self updateView];
	}
}

- (void)databaseConnectionDidUpdate:(NSNotification *)notification
{
	NSArray *notifications = [notification.userInfo objectForKey:kNotificationsKey];
	
	if ([databaseConnection hasChangeForKey:todoID inCollection:Collection_Todos inNotifications:notifications])
	{
		[self updateView];
	}
}

- (void)updateView
{
	__block MyTodo *todo = nil;
	__block CKRecord *record = nil;
	if (todoID)
	{
		[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			todo = [transaction objectForKey:todoID inCollection:Collection_Todos];
			record = [[transaction ext:Ext_CloudKit] recordForKey:todoID inCollection:Collection_Todos];
		}];
	}
	
	if (todo)
	{
		titleView.text = todo.title;
		
		if (todo.isDone)
		{
			checkmarkButton.tag = 1;
			[checkmarkButton setImage:[UIImage imageNamed:@"checkmark-on"] forState:UIControlStateNormal];
		}
		else
		{
			checkmarkButton.tag = 0;
			[checkmarkButton setImage:[UIImage imageNamed:@"checkmark-off"] forState:UIControlStateNormal];
		}
		
		if (todo.priority == TodoPriorityLow)
			priority.selectedSegmentIndex = 0;
		else if (todo.priority == TodoPriorityHigh)
			priority.selectedSegmentIndex = 2;
		else
			priority.selectedSegmentIndex = 1;
		
		uuidLabel.text = todo.uuid;
		
		NSDateFormatter *df = [[NSDateFormatter alloc] init];
		df.dateStyle = NSDateFormatterMediumStyle;
		df.timeStyle = NSDateFormatterMediumStyle;
		
		creationDateLabel.text = [df stringFromDate:todo.creationDate];
		lastModifiedLabel.text = [df stringFromDate:todo.lastModified];
		
		baseRecordLabel.text = [record description];
	}
	else
	{
		titleView.text = nil;
		
		checkmarkButton.tag = 0;
		[checkmarkButton setImage:[UIImage imageNamed:@"checkmark-off"] forState:UIControlStateNormal];
		
		priority.selectedSegmentIndex = 1;
		
		uuidLabel.text = [[NSUUID UUID] UUIDString];
		creationDateLabel.text = @"<now>";
		lastModifiedLabel.text = @"<now>";
		
		baseRecordLabel.text = @"<New CKRecord>";
	}
	
	if (self.isViewLoaded) {
		[self textViewDidChange:titleView];
	}
}

- (IBAction)checkmarkButtonTapped:(id)sender
{
	if (checkmarkButton.tag == 1)
	{
		checkmarkButton.tag = 0;
		[checkmarkButton setImage:[UIImage imageNamed:@"checkmark-off"] forState:UIControlStateNormal];
	}
	else
	{
		checkmarkButton.tag = 1;
		[checkmarkButton setImage:[UIImage imageNamed:@"checkmark-on"] forState:UIControlStateNormal];
	}
}

- (void)cancelButtonTapped:(id)sender
{
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)saveButtonTapped:(id)sender
{
	NSString *newTitle = titleView.text;
	
	BOOL newIsDone = (checkmarkButton.tag == 1);
	
	TodoPriority newPriority;
	if (priority.selectedSegmentIndex == 0)
		newPriority = TodoPriorityLow;
	else if (priority.selectedSegmentIndex == 2)
		newPriority = TodoPriorityHigh;
	else
		newPriority = TodoPriorityNormal;
	
	[MyDatabaseManager.bgDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		MyTodo *todo = [transaction objectForKey:todoID inCollection:Collection_Todos];
		
		if (todo == nil)
		{
			todo = [[MyTodo alloc] initWithUUID:uuidLabel.text];
			
			todo.title = newTitle;
			todo.isDone = newIsDone;
			todo.priority = newPriority;
			
			[transaction setObject:todo forKey:todo.uuid inCollection:Collection_Todos];
		}
		else
		{
			todo = [todo copy]; // mutable copy
			
			// If the user didn't effectively make any changes,
			// we're going to try to avoid updating the properties.
			// Which, in turn, avoids uploading unchanged properties.
			
			if (![todo.title isEqualToString:newTitle]) {
				todo.title = newTitle;
			}
			if (todo.isDone != newIsDone) {
				todo.isDone = newIsDone;
			}
			if (todo.priority != newPriority) {
				todo.priority = newPriority;
			}
			
			if (todo.hasChangedProperties)
			{
				todo.lastModified = [NSDate date];
				
				[transaction setObject:todo forKey:todo.uuid inCollection:Collection_Todos];
			}
		}
	}];
	
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)textViewDidChange:(UITextView *)sender
{
	CGFloat intrinsicHeight = [titleView intrinsicContentSize].height;
	CGFloat currentHeight = titleView.frame.size.height;
	
	BOOL needsUpdate = NO;
	
	if (intrinsicHeight != currentHeight)
	{
		if ((intrinsicHeight > currentHeight) && (currentHeight != titleViewMaxHeightConstraint.constant))
		{
			needsUpdate = YES;
		}
		if ((intrinsicHeight < currentHeight) && (currentHeight != titleViewMinHeightConstraint.constant))
		{
			needsUpdate = YES;
		}
	}
	
	if (needsUpdate)
	{
		[UIView animateWithDuration:0.1 animations:^{
			
			titleView.needsScrollIfNeeded = YES;
			
			[titleView invalidateIntrinsicContentSize];
			[self.view layoutIfNeeded];
		}];
	}
}

@end
