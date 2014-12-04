#import "EditViewController.h"
#import "DatabaseManager.h"
#import "MyTodo.h"


@implementation EditViewController
{
	YapDatabaseConnection *databaseConnection;
}

@synthesize todoID = todoID;

@synthesize titleField = titleField;
@synthesize priority = priority;

@synthesize uuidLabel = uuidLabel;
@synthesize creationDateLabel = creationDateLabel;
@synthesize lastModifiedLabel = lastModifiedLabel;

- (void)viewDidLoad
{
	[super viewDidLoad];
	
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
	if (todoID)
	{
		[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			todo = [transaction objectForKey:todoID inCollection:Collection_Todos];
		}];
	}
	
	if (todo)
	{
		titleField.text = todo.title;
		
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
	}
	else
	{
		titleField.text = nil;
		priority.selectedSegmentIndex = 1;
		
		uuidLabel.text = [[NSUUID UUID] UUIDString];
		creationDateLabel.text = @"<now>";
		lastModifiedLabel.text = @"<now>";
	}
}

- (void)cancelButtonTapped:(id)sender
{
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)saveButtonTapped:(id)sender
{
	NSString *newTitle = titleField.text;
	
	TodoPriority newPriority;
	if (priority.selectedSegmentIndex == 0)
		newPriority = TodoPriorityLow;
	else if (priority.selectedSegmentIndex == 2)
		newPriority = TodoPriorityHigh;
	else
		newPriority = TodoPriorityNormal;
	
	[MyDatabaseManager.bgDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		MyTodo *todo = [transaction objectForKey:todoID inCollection:Collection_Todos];
		
		if (todo == nil) {
			todo = [[MyTodo alloc] initWithUUID:uuidLabel.text];
		}
		else {
			todo = [todo copy]; // mutable copy
			todo.lastModified = [NSDate date];
		}
		
		todo.title = newTitle;
		todo.priority = newPriority;
		
		[transaction setObject:todo forKey:todo.uuid inCollection:Collection_Todos];
	}];
	
	[self.navigationController popViewControllerAnimated:YES];
}

@end
