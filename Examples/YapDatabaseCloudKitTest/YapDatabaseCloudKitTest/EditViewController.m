#import "EditViewController.h"
#import "DatabaseManager.h"
#import "MyTodo.h"


@implementation EditViewController

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
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	if (todoID == nil) {
		[self updateViews];
	}
}

- (void)setTodoID:(NSString *)newTodoID
{
	todoID = newTodoID;
	[self updateViews];
}

- (void)updateViews
{
	__block MyTodo *todo = nil;
	if (todoID)
	{
		[MyDatabaseManager.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
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
		creationDateLabel.text = [todo.creationDate descriptionWithLocale:[NSLocale currentLocale]];
		lastModifiedLabel.text = [todo.lastModified descriptionWithLocale:[NSLocale currentLocale]];
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
	__block MyTodo *todo = nil;
	if (todoID)
	{
		[MyDatabaseManager.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
			
			todo = [transaction objectForKey:todoID inCollection:Collection_Todos];
		}];
	}
	
	if (todo == nil) {
		todo = [[MyTodo alloc] initWithUUID:uuidLabel.text];
	}
	else {
		todo = [todo copy]; // mutable copy
		todo.lastModified = [NSDate date];
	}
	
	todo.title = titleField.text;
	
	if (priority.selectedSegmentIndex == 0)
		todo.priority = TodoPriorityLow;
	else if (priority.selectedSegmentIndex == 2)
		todo.priority = TodoPriorityHigh;
	else
		todo.priority = TodoPriorityNormal;
	
	[MyDatabaseManager.bgDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:todo forKey:todo.uuid inCollection:Collection_Todos];
	}];
	
	[self.navigationController popViewControllerAnimated:YES];
}

@end
