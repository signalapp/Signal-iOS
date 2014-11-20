#import <UIKit/UIKit.h>

#import "LocalizableCustomFontLabel.h"
#import "SettingsTableHeaderView.h"

/**
 *
 * SettingsViewController displays a list of settings in sections which can animate between being expanded or collapsed.
 * The expanded/collapsed preference of the sections is remembered by the preference util.
 * Table cell text labels are localized by setting them to a custom label class that has a localization key which are both set in the xib -
 * and localized when the cell appears.
 * Preferences are saved to preference util when tapped.
 *
 */

@interface SettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIAlertViewDelegate>

@property (strong, nonatomic) IBOutlet UITableView* settingsTableView;
@property (strong, nonatomic) IBOutlet UILabel* phoneNumberLabel;
@property (strong, nonatomic) IBOutlet UILabel* titleLabel;

@property (strong, nonatomic) IBOutlet SettingsTableHeaderView* privacyAndSecurityHeaderView;
@property (strong, nonatomic) IBOutlet SettingsTableHeaderView* debuggingHeaderView;
@property (strong, nonatomic) IBOutlet UITableViewCell* hideContactImagesCell;
@property (strong, nonatomic) IBOutlet UITableViewCell* disableAutocorrectCell;
@property (strong, nonatomic) IBOutlet UITableViewCell* disableHistoryCell;
@property (strong, nonatomic) IBOutlet UITableViewCell* clearHistoryLogCell;
@property (strong, nonatomic) IBOutlet UITableViewCell* disableLogsCell;
@property (strong, nonatomic) IBOutlet UITableViewCell* enableScreenSecurityCell;

@property (strong, nonatomic) IBOutlet UIButton* hideContactImagesButton;
@property (strong, nonatomic) IBOutlet UIButton* disableAutocorrectButton;
@property (strong, nonatomic) IBOutlet UIButton* disableHistoryButton;
@property (strong, nonatomic) IBOutlet UIButton* disableDebugLogsButton;
@property (strong, nonatomic) IBOutlet UIButton* enableScreenSecurityButton;

@property (strong, nonatomic) IBOutlet UITableViewCell* sendDebugLog;

- (IBAction)registerTapped;

- (IBAction)privacyAndSecurityTapped;
- (IBAction)debuggingTapped:(id)sender;

- (IBAction)hideContactImagesButtonTapped;
- (IBAction)disableAutocorrectButtonTapped;
- (IBAction)disableHistoryButtonTapped;

- (IBAction)disableLogTapped:(id)sender;

- (IBAction)enableScreenSecurityTapped:(id)sender;

- (IBAction)menuButtonTapped;

@end
