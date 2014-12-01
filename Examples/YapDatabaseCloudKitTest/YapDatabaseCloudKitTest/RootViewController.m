#import "RootViewController.h"
#import "DatabaseManager.h"

#import "DDLog.h"

// Log Levels: off, error, warn, info, verbose
#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_ALL;
#else
  static const int ddLogLevel = LOG_LEVEL_ALL;
#endif


@implementation RootViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	CGRect ckViewFrame = self.ckStatusView.frame;
	
	UIEdgeInsets insets = self.tableView.scrollIndicatorInsets;
	insets.bottom = ckViewFrame.size.height;
	
	self.tableView.contentInset = insets;
	self.tableView.scrollIndicatorInsets = insets;
}

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

@end
