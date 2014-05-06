#import <UIKit/UIKit.h>

/**
 *
 * PreferenceListViewController displays a list of options and highlights a selected one indicated by selectedValueBlock.
 * When selected, the selected block is called and the value should be updated manually.
 *
 */

typedef void (^SelectedBlock) (NSString *newValue);
typedef NSString* (^GetSelectedValueBlock) ();

@interface PreferenceListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
	@private SelectedBlock selectedBlock;
	@private GetSelectedValueBlock getSelectedValueBlock;
	@private NSString *settingsValue;
}

@property (nonatomic, strong) IBOutlet UITableView *optionTableView;
@property (nonatomic, strong) NSArray *options;

+ (PreferenceListViewController *)preferenceListViewControllerForSelectedValue:(GetSelectedValueBlock)selectedValueBlock
                                                                    andOptions:(NSArray *)options
                                                              andSelectedBlock:(SelectedBlock)block;

@end
