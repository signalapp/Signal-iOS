#import "PreferenceListTableViewCell.h"

@implementation PreferenceListTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil] firstObject];
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass([self class]);
}

@end
