#import <UIKit/UIKit.h>

#define SEARCH_BAR_DEFAULT_EMPTY_STRING @""

@class SearchBarTitleView;

@protocol SearchBarTitleViewDelegate <NSObject>

- (void)searchBarTitleView:(SearchBarTitleView *)view didSearchForTerm:(NSString *)term;
- (void)searchBarTitleViewDidEndSearching:(SearchBarTitleView *)view;
- (void)searchBarTitleViewDidTapMenu:(SearchBarTitleView *)view;

@end

@interface SearchBarTitleView : UIView <UITextFieldDelegate>

@property (nonatomic, strong) IBOutlet UILabel *titleLabel;
@property (nonatomic, strong) IBOutlet UIView *searchBarContainer;
@property (nonatomic, strong) IBOutlet UITextField *searchTextField;
@property (nonatomic, strong) IBOutlet UIButton *searchButton;
@property (nonatomic, strong) IBOutlet UIButton *cancelButton;
@property (nonatomic, strong) IBOutlet UIButton *menuButton;
@property (nonatomic, assign) IBOutlet id<SearchBarTitleViewDelegate> delegate;

- (void)updateAutoCorrectionType;

@end
