#import "Environment.h"
#import "PreferencesUtil.h"
#import "PreferenceListTableViewCell.h"
#import "PreferenceListViewController.h"
#import "Util.h"

static NSString *const PREFERENCE_LIST_TABLE_VIEW_CELL = @"PreferenceListTableViewCell";

@implementation PreferenceListViewController

+ (PreferenceListViewController *)preferenceListViewControllerForSelectedValue:(GetSelectedValueBlock)selectedValueBlock
                                                                    andOptions:(NSArray *)options
                                                              andSelectedBlock:(SelectedBlock)block {
    require(selectedValueBlock != nil);
    require(block != nil);

    PreferenceListViewController *vc = [PreferenceListViewController new];
    vc.options = options;
    vc->selectedBlock = block;
    vc->getSelectedValueBlock = selectedValueBlock;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.barTintColor = [UIUtil darkBackgroundColor];
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    self.navigationController.navigationBar.translucent = NO;
    
    settingsValue = getSelectedValueBlock();
    [_optionTableView reloadData];
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[_options count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PreferenceListTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:PREFERENCE_LIST_TABLE_VIEW_CELL];
    if (!cell) {
        cell = [[PreferenceListTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                  reuseIdentifier:PREFERENCE_LIST_TABLE_VIEW_CELL];
    }

    if ([settingsValue isEqualToString:_options[(NSUInteger)indexPath.row]]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    NSString *date = _options[(NSUInteger)indexPath.row];
    cell.preferenceTextLabel.text = [date lowercaseString];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    selectedBlock(_options[(NSUInteger)indexPath.row]);
    settingsValue = getSelectedValueBlock();
    [_optionTableView reloadData];
}

@end
