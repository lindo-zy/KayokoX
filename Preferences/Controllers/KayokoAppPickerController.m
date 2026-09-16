//
//  KayokoAppPickerController.m
//  Kayoko
//

#import "KayokoAppPickerController.h"

#import "KayokoAppInfo.h"

@interface KayokoAppPickerController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, copy) NSString *searchText;
@property(nonatomic, copy) NSArray<KayokoAppInfo *> *apps;
@property(nonatomic, strong) NSBundle *localizationBundle;
@end

// Subtitle style: app name on top, bundle identifier underneath.
@interface KayokoAppPickerCell : UITableViewCell
@end

@implementation KayokoAppPickerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
@end

@implementation KayokoAppPickerController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _localizationBundle = [NSBundle bundleForClass:[self class]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    [self setTitle:[self localizedStringForKey:@"Select App"]];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView registerClass:[KayokoAppPickerCell class] forCellReuseIdentifier:@"KayokoAppPickerCell"];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    [_searchController setSearchResultsUpdater:self];
    [_searchController setObscuresBackgroundDuringPresentation:NO];
    [_searchController setDefinesPresentationContext:YES];
    [[_searchController searchBar] setPlaceholder:[self localizedStringForKey:@"Search"]];
    [[self navigationItem] setSearchController:_searchController];
    [[self navigationItem] setHidesSearchBarWhenScrolling:NO];

    [self loadApps];
}

- (void)loadApps {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray<KayokoAppInfo *> *apps = [KayokoAppInfo installedApps];
      dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf setApps:apps];
        [[strongSelf tableView] reloadData];
      });
    });
}

#pragma mark - Data

- (NSArray<KayokoAppInfo *> *)filteredApps {
    NSString *query = [[self searchText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([query length] == 0) {
        return [self apps];
    }
    NSMutableArray<KayokoAppInfo *> *result = [NSMutableArray array];
    for (KayokoAppInfo *app in [self apps]) {
        if ([[app name] localizedCaseInsensitiveContainsString:query] ||
            [[app bundleID] localizedCaseInsensitiveContainsString:query]) {
            [result addObject:app];
        }
    }
    return result;
}

- (NSArray<KayokoAppInfo *> *)selectedApps {
    NSString *currentBundleID = [self currentBundleID];
    NSMutableArray<KayokoAppInfo *> *result = [NSMutableArray array];
    for (KayokoAppInfo *app in [self filteredApps]) {
        if ([currentBundleID length] > 0 && [[app bundleID] isEqualToString:currentBundleID]) {
            [result addObject:app];
        }
    }
    return result;
}

- (NSArray<KayokoAppInfo *> *)unselectedApps {
    NSString *currentBundleID = [self currentBundleID];
    NSMutableArray<KayokoAppInfo *> *result = [NSMutableArray array];
    for (KayokoAppInfo *app in [self filteredApps]) {
        if ([currentBundleID length] > 0 && [[app bundleID] isEqualToString:currentBundleID]) continue;
        [result addObject:app];
    }
    return result;
}

- (BOOL)hasSelectedSection {
    return [[self selectedApps] count] > 0;
}

- (NSArray<KayokoAppInfo *> *)appsForSection:(NSInteger)section {
    if (section == 0 && [self hasSelectedSection]) {
        return [self selectedApps];
    }
    return [self unselectedApps];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [self hasSelectedSection] ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return (section == 0 && [self hasSelectedSection]) ? [self localizedStringForKey:@"Selected"]
                                                       : [self localizedStringForKey:@"Not Selected"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[[self appsForSection:section] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return 60.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    KayokoAppPickerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KayokoAppPickerCell" forIndexPath:indexPath];
    KayokoAppInfo *app = [self appsForSection:[indexPath section]][(NSUInteger)[indexPath row]];
    [[cell textLabel] setText:[app name]];
    [[cell detailTextLabel] setText:[app bundleID]];
    [[cell detailTextLabel] setTextColor:[UIColor secondaryLabelColor]];
    [[cell detailTextLabel] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [[cell imageView] setImage:[KayokoAppInfo iconForBundleID:[app bundleID]]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    KayokoAppInfo *app = [self appsForSection:[indexPath section]][(NSUInteger)[indexPath row]];
    if (!app) {
        return;
    }
    void (^completionHandler)(NSString *, NSString *) = [self completionHandler];
    if (completionHandler) {
        completionHandler([app name], [app bundleID]);
    }
    [[self navigationController] popViewControllerAnimated:YES];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self setSearchText:[[searchController searchBar] text]];
    [[self tableView] reloadData];
}

#pragma mark - Localization

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"CustomJumps"] ?: key;
}

@end
