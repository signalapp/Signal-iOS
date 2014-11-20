#import "DebugLogger.h"
#import "Environment.h"
#import "TOCFuture+FutureUtil.h"
#import "LocalizableText.h"
#import "Operation.h"
#import "PropertyListPreferences+Util.h"
#import "PhoneNumber.h"
#import "RecentCallManager.h"
#import "RegisterViewController.h"
#import "SettingsViewController.h"
#import "Pastelog.h"
#import "SGNKeychainUtil.h"

#import "UIViewController+MMDrawerController.h"

#define SECTION_HEADER_VIEW_HEIGHT 27
#define PRIVACY_SECTION_INDEX 0
#define DEBUG_SECTION_INDEX 1

static NSString* const CHECKBOX_CHECKMARK_IMAGE_NAME = @"checkbox_checkmark";
static NSString* const CHECKBOX_EMPTY_IMAGE_NAME = @"checkbox_empty";

@interface SettingsViewController ()

@property (strong, nonatomic) NSArray* sectionHeaderViews;
@property (strong, nonatomic) NSArray* privacyTableViewCells;
@property (strong, nonatomic) NSArray* debuggingTableViewCells;
@property (strong, nonatomic) NSString* gistURL;

@end

@implementation SettingsViewController

@synthesize privacyTableViewCells = _privacyTableViewCells, debuggingTableViewCells = _debuggingTableViewCells;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.sectionHeaderViews = @[self.privacyAndSecurityHeaderView , self.debuggingHeaderView];
    
    self.titleLabel.text = SETTINGS_NAV_BAR_TITLE;
}

- (void)viewWillAppear:(BOOL)animated {
    [self configureLocalNumber];
    [self configureAllCells];
    [self configureCheckboxPreferences];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self saveExpandedSectionPreferences];
    
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController setNavigationBarHidden:NO animated:YES];
    }
    
    [super viewWillDisappear:animated];
}

- (void)menuButtonTapped {
    [self.mm_drawerController openDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

#pragma mark - Local number

- (void)configureLocalNumber {
    PhoneNumber* localNumber = [SGNKeychainUtil localNumber];
    if (localNumber) {
        self.phoneNumberLabel.attributedText = [self localNumberAttributedStringForNumber:localNumber];
    } else {
        self.phoneNumberLabel.text = @"";
    }
}

- (NSAttributedString*)localNumberAttributedStringForNumber:(PhoneNumber*)number {
    NSString* numberPrefixString = SETTINGS_NUMBER_PREFIX;
    NSString* localNumberString = number.toE164;
    
    NSString* displayString = [NSString stringWithFormat:@"%@ %@", numberPrefixString, localNumberString];
    NSMutableAttributedString* attributedString = [[NSMutableAttributedString alloc] initWithString:displayString];
    
    UIFont* prefixFont = [UIUtil helveticaNeueLTStdLightFontWithSize:self.phoneNumberLabel.font.pointSize];
    UIFont* numberFont = [UIUtil helveticaNeueLTStdBoldFontWithSize:self.phoneNumberLabel.font.pointSize];
    
    [attributedString addAttribute:NSFontAttributeName
                             value:prefixFont
                             range:NSMakeRange(0, numberPrefixString.length)];
    
    [attributedString addAttribute:NSFontAttributeName
                             value:numberFont
                             range:NSMakeRange(numberPrefixString.length + 1, localNumberString.length)];
    return attributedString;
}

#pragma mark - Preferences

- (void)configureCheckboxPreferences {
    NSArray* buttons = @[self.hideContactImagesButton,
                         self.enableScreenSecurityButton,
                         self.disableAutocorrectButton,
                         self.disableHistoryButton,
                         self.disableDebugLogsButton];
    
    for (UIButton* button in buttons) {
        [button setImage:[UIImage imageNamed:CHECKBOX_EMPTY_IMAGE_NAME]
                forState:UIControlStateNormal];
        
        [button setImage:[UIImage imageNamed:CHECKBOX_CHECKMARK_IMAGE_NAME]
                forState:UIControlStateSelected];
    }
    PropertyListPreferences* prefs           = Environment.preferences;
    self.hideContactImagesButton.selected    = !prefs.getContactImagesEnabled;
    self.enableScreenSecurityButton.selected = prefs.screenSecurityIsEnabled;
    self.disableAutocorrectButton.selected   = !prefs.getAutocorrectEnabled;
    self.disableHistoryButton.selected       = !prefs.getHistoryLogEnabled;
    self.disableDebugLogsButton.selected     = !prefs.loggingIsEnabled;
}

- (void)configureAllCells {
    self.privacyTableViewCells   = [self privacyAndSecurityCells];
    self.debuggingTableViewCells = [self debugCells];
    [self.privacyAndSecurityHeaderView setColumnStateExpanded:YES andIsAnimated:NO];
    [self.debuggingHeaderView setColumnStateExpanded:YES andIsAnimated:NO];
}

- (void)saveExpandedSectionPreferences {
    NSMutableArray* expandedSectionPrefs = [[NSMutableArray alloc] init];
    NSNumber* numberBoolYes = @YES;
    NSNumber* numberBoolNo = @NO;
    
    [expandedSectionPrefs addObject:(self.privacyTableViewCells ? numberBoolYes : numberBoolNo)];
}

#pragma mark - Table View Helpers

- (NSArray*)privacyAndSecurityCells {
    return @[self.hideContactImagesCell,
             self.enableScreenSecurityCell,
             self.disableAutocorrectCell,
             self.disableHistoryCell,
             self.clearHistoryLogCell];
}

- (NSArray*)debugCells {
    
    NSMutableArray* cells = [@[self.disableLogsCell] mutableCopy];
    
    if (Environment.preferences.loggingIsEnabled) {
        [cells addObject:self.sendDebugLog];
    }
    
    return cells;
}

- (NSArray*)indexPathsForCells:(NSArray*)cells forRow:(NSInteger)row {
    NSMutableArray* indexPaths = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < cells.count; i++) {
        NSIndexPath* indexPath = [NSIndexPath indexPathForRow:(NSInteger)i inSection:row];
        [indexPaths addObject:indexPath];
    }
    return indexPaths;
}

- (NSArray*)cellsForRow:(NSInteger)row {
    if (row == PRIVACY_SECTION_INDEX) {
        return [self privacyAndSecurityCells];
    } else if (row == DEBUG_SECTION_INDEX) {
        return [self debugCells];
    }else {
        return @[];
    }
}

#pragma mark - Actions

- (void)registerTapped {
    [self presentViewController:[[RegisterViewController alloc] init] animated:YES completion:nil];
}

- (void)privacyAndSecurityTapped {
    [self toggleCells:&_privacyTableViewCells forRow:PRIVACY_SECTION_INDEX];
    BOOL columnExpanded = self.privacyTableViewCells != nil;
    [self.privacyAndSecurityHeaderView setColumnStateExpanded:columnExpanded andIsAnimated:YES];
}

- (void)debuggingTapped:(id)sender{
    [self toggleCells:&_debuggingTableViewCells forRow:DEBUG_SECTION_INDEX];
    BOOL columnExpanded = self.debuggingTableViewCells != nil;
    [self.debuggingHeaderView setColumnStateExpanded:columnExpanded andIsAnimated:YES];
}

- (void)toggleCells:(NSArray* __strong*)cells forRow:(NSInteger)row {
    [self.settingsTableView beginUpdates];
    if (*cells) {
        [self.settingsTableView deleteRowsAtIndexPaths:[self indexPathsForCells:*cells forRow:row]
                                      withRowAnimation:UITableViewRowAnimationFade];
        *cells = nil;
    } else {
        *cells = [self cellsForRow:row];
        [self.settingsTableView insertRowsAtIndexPaths:[self indexPathsForCells:*cells forRow:row]
                                      withRowAnimation:UITableViewRowAnimationFade];
    }
    [self.settingsTableView endUpdates];
}

- (IBAction)hideContactImagesButtonTapped {
    self.hideContactImagesButton.selected = !self.hideContactImagesButton.selected;
    [Environment.preferences setContactImagesEnabled:!self.hideContactImagesButton.selected];
}

- (IBAction)disableAutocorrectButtonTapped {
    self.disableAutocorrectButton.selected = !self.disableAutocorrectButton.selected;
    [Environment.preferences setAutocorrectEnabled:!self.disableAutocorrectButton.selected];
}

- (IBAction)disableHistoryButtonTapped {
    self.disableHistoryButton.selected = !self.disableHistoryButton.selected;
    [Environment.preferences setHistoryLogEnabled:!self.disableHistoryButton.selected];
}

- (IBAction)enableScreenSecurityTapped:(id)sender{
    self.enableScreenSecurityButton.selected = !self.enableScreenSecurityButton.selected;
    [Environment.preferences setScreenSecurity:self.enableScreenSecurityButton.selected];
}

- (IBAction)disableLogTapped:(id)sender{
    self.disableDebugLogsButton.selected = !self.disableDebugLogsButton.selected;
    
    BOOL loggingEnabled = !self.disableDebugLogsButton.selected;
    
    if (!loggingEnabled) {
        [DebugLogger.sharedInstance disableFileLogging];
        [[DebugLogger sharedInstance ] wipeLogs];
    } else{
        [DebugLogger.sharedInstance enableFileLogging];
    }

    [Environment.preferences setLoggingEnabled:loggingEnabled];
    self.debuggingTableViewCells = [self debugCells];
    [self.settingsTableView reloadData];
}

- (void)clearHistory {
    [Environment.getCurrent.recentCallManager clearRecentCalls];
#warning Deprecated method
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:SETTINGS_LOG_CLEAR_TITLE
                                                        message:SETTINGS_LOG_CLEAR_MESSAGE
                                                       delegate:nil
                                              cancelButtonTitle:nil
                                              otherButtonTitles:SETTINGS_LOG_CLEAR_CONFIRM, nil];
    [alertView show];
}

#pragma mark - UITableViewDelegate

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return (NSInteger)self.sectionHeaderViews.count;
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    return self.sectionHeaderViews[(NSUInteger)section];
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    return SECTION_HEADER_VIEW_HEIGHT;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    UIView* headerView = self.sectionHeaderViews[(NSUInteger)section];
    if (headerView == self.privacyAndSecurityHeaderView) {
        return (NSInteger)self.privacyTableViewCells.count;
    } else if (headerView == self.debuggingHeaderView) {
        return (NSInteger)self.debuggingTableViewCells.count;
    } else {
        return 0;
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    UIView* headerView = self.sectionHeaderViews[(NSUInteger)indexPath.section];
    UITableViewCell* cell = nil;
    if (headerView == self.privacyAndSecurityHeaderView) {
        cell = self.privacyTableViewCells[(NSUInteger)indexPath.row];
    } else if (headerView ==self.debuggingHeaderView) {
        cell = self.debuggingTableViewCells[(NSUInteger)indexPath.row];
    }
    [self findAndLocalizeLabelsForView:cell];
    
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    UITableViewCell* cell = [tableView cellForRowAtIndexPath:indexPath];
    if (cell == self.clearHistoryLogCell) {
        [self clearHistory];
    }
    
    if (cell == self.sendDebugLog) {
        [Pastelog submitLogs];
    }
}


- (void)findAndLocalizeLabelsForView:(UIView*)view {
    for (UIView* subview in view.subviews) {
        if ([subview respondsToSelector:@selector(localizationKey)]) {
            LocalizableCustomFontLabel* label = (LocalizableCustomFontLabel*)subview;
            if (label.localizationKey) {
                label.text = NSLocalizedString(label.localizationKey, @"");
            }
        }
        [self findAndLocalizeLabelsForView:subview];
    }
}

@end
