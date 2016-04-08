//
//  ViewController.m
//  TestWKWebView
//
//  Created by Gena on 08.04.16.
//  Copyright © 2016 Gennadiy Mishin. All rights reserved.
//

#import "ViewController.h"

@import WebKit;

@interface ViewController () <WKNavigationDelegate, UISearchBarDelegate, UIScrollViewDelegate, UITableViewDelegate, UITableViewDataSource>

@property (weak, nonatomic) WKWebView *webView;

@property (strong, nonatomic) UISearchBar *searchBar;
@property (nonatomic, strong) UIColor *searchBarDefaultColor;
@property (weak, nonatomic) UITextField *searchBarTextField;
@property (nonatomic) BOOL editing;

@property (nonatomic, strong) NSString *currentSiteString;
@property (strong, nonatomic) UITableView *tableView;

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSArray *items;

@property (nonatomic, strong) UIProgressView *progressView;
@property (weak, nonatomic) UIToolbar *toolBar;

@property (nonatomic, strong) NSMutableArray *visitedLinks;
@property (nonatomic) NSInteger currentPageIndex;
@property (nonatomic) BOOL reloading;

@end

@implementation ViewController


#pragma mark - Life cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.currentPageIndex = 0;
    self.visitedLinks = [NSMutableArray new];
    
    [self configureWebView];
    [self configureSearchBar];
    
    self.navigationItem.titleView = self.searchBar;
    
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self configureTableView];
    [self configureProgressView];
    [self configureToolBar];
}

- (void)dealloc {
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    
    [self.webView setNavigationDelegate:nil];
    [self.webView setUIDelegate:nil];
}

#pragma mark - Configure methods

- (void)configureWebView {
    WKWebView *webView = [WKWebView new];
    webView.navigationDelegate = self;
    self.view = webView;
    webView.scrollView.delegate = self;
    webView.allowsLinkPreview = YES;
    
    [webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];
    
    self.currentSiteString = @"about:blank";
    NSURL *url = [NSURL URLWithString:self.currentSiteString];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    [self.visitedLinks addObject: url];
    
    self.webView.allowsBackForwardNavigationGestures = YES;
    
    self.webView = webView;
}

- (void)configureSearchBar {
    UISearchBar *searchBar = [UISearchBar new];
    searchBar.delegate = self;
    searchBar.placeholder = @"Search here";
    searchBar.text = self.currentSiteString;
    searchBar.showsBookmarkButton = YES;
    
    [searchBar setImage:[UIImage imageNamed:@"icon-refresh"] forSearchBarIcon:UISearchBarIconBookmark state:UIControlStateNormal];
    [searchBar setImage:[UIImage imageNamed:@"icon-stop-refresh"] forSearchBarIcon:UISearchBarIconBookmark state:UIControlStateHighlighted];
    
    UITextField *textField = [searchBar valueForKey:@"_searchField"];
    [textField setClearButtonMode:UITextFieldViewModeWhileEditing];
    [textField setTextAlignment:NSTextAlignmentCenter];
    self.searchBarTextField = textField;
    textField.leftView = nil;
    
    self.searchBarDefaultColor = textField.backgroundColor;
    
    self.searchBar = searchBar;
}

- (void)configureTableView {
    CGRect frame = self.view.frame;
    frame.origin.y = 64.0;
    frame.size.height -= 64.0;
    UITableView *tableView = [[UITableView alloc] initWithFrame:frame style:UITableViewStylePlain];
    tableView.delegate = self;
    tableView.dataSource = self;
    
    self.tableView = tableView;
}

- (void)configureProgressView {
    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    [self.navigationController.navigationBar addSubview:progressView];
    
    CGRect frame = progressView.frame;
    frame.size.width = self.view.frame.size.width;
    progressView.frame = frame;
    
    self.progressView = progressView;
}

- (void)configureToolBar {
    CGRect viewFrame = self.view.frame;
    CGRect frame = CGRectMake(0, viewFrame.size.height - 44, viewFrame.size.width, 44.0);
    UIToolbar *toolBar = [[UIToolbar alloc] initWithFrame:frame];
    
    UIBarButtonItem *prev = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemUndo target:self action:@selector(previousButtonPressed:)];
    UIBarButtonItem *next = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRedo target:self action:@selector(nextButtonPressed:)];
    
    toolBar.items = @[prev, next];
    
    [self.view addSubview:toolBar];
    self.toolBar = toolBar;
}

#pragma mark - Actions

- (void)previousButtonPressed:(UIBarButtonItem *)sender {
    if (self.currentPageIndex > 0) {
        self.currentPageIndex--;
        
        NSURL *url = self.visitedLinks[self.currentPageIndex];
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        
        self.searchBar.text = url.absoluteString;
    }
}

- (void)nextButtonPressed:(UIBarButtonItem *)sender {
    if (self.visitedLinks.count > 0 && self.currentPageIndex < self.visitedLinks.count - 1) {
        self.currentPageIndex++;
        
        NSURL *url = self.visitedLinks[self.currentPageIndex];
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        
        self.searchBar.text = url.absoluteString;
    }
}

#pragma mark - UISearchBar

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
    [self searchBarStartTyping];
    
    return YES;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    self.currentSiteString = searchBar.text;
    
    [self searchBarEndTyping];
    [self searchText:searchBar.text];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [self searchBarEndTyping];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length > 0) {
        [self searchSuggesionsWithText:searchText];
    } else {
        self.items = nil;
        [self.tableView reloadData];
    }
}

- (void)searchBarBookmarkButtonClicked:(UISearchBar *)searchBar {
    if (self.reloading) {
        self.reloading = NO;
        [searchBar setImage:[UIImage imageNamed:@"icon-refresh"] forSearchBarIcon:UISearchBarIconBookmark state:UIControlStateNormal];
        
        [self.webView stopLoading];
    } else {
        self.reloading = YES;
        [searchBar setImage:[UIImage imageNamed:@"icon-stop-refresh"] forSearchBarIcon:UISearchBarIconBookmark state:UIControlStateNormal];
        
        NSURL *url = self.visitedLinks[self.currentPageIndex];
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    }
}

- (void)searchBarStartTyping {
    [self.searchBar setShowsCancelButton:YES animated:YES];
    
    CGRect frame = self.navigationController.navigationBar.frame;
    frame.size.height = 44;
    self.navigationController.navigationBar.frame = frame;
    
    self.searchBarTextField.backgroundColor = self.searchBarDefaultColor;
    [self.searchBarTextField setTextAlignment:NSTextAlignmentLeft];
    
    self.editing = YES;
    
    [self showTableView];
    [self searchSuggesionsWithText:self.searchBar.text];
}

- (void)searchBarEndTyping {
    [self.searchBar endEditing:YES];
    
    [self.searchBarTextField setTextAlignment:NSTextAlignmentCenter];
    self.searchBar.text = self.currentSiteString;
    self.editing = NO;
    [self.searchBar setShowsCancelButton:NO animated:YES];
    
    [self hideTableVeiw];
}

#pragma mark - ScrollView

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!self.editing) {
        CGRect frame = self.navigationController.navigationBar.frame;
        
        if (scrollView.contentOffset.y <= -64.0) {
            frame.size.height = 44;
            self.searchBar.showsBookmarkButton = YES;
            self.searchBarTextField.backgroundColor = self.searchBarDefaultColor;
        } else {
            frame.size.height = 24;
            self.searchBar.showsBookmarkButton = NO;
            self.searchBarTextField.backgroundColor = [UIColor clearColor];
        }
        
        if (self.navigationController.navigationBar.frame.size.height != frame.size.height) {
            self.navigationController.navigationBar.frame = frame;
        }
    }
    [self.searchBar endEditing:YES];
}

#pragma mark - Search text in google

- (void)searchSuggesionsWithText:(NSString *)text {
    text = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://google.com/complete/search?output=firefox&q=%@", text]];
    
    [[self.session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (!error) {
            NSArray *resultArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (!error) {
                NSArray *results = resultArray[1];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateTableWithResults:results forSearchText:text];
                });
            }
        }
    }] resume];
}

- (void)searchText:(NSString *)text {
    text = [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
    NSString *urlString = [NSString stringWithFormat:@"https://www.google.com/search?q=%@", text];
    NSURL *url = [NSURL URLWithString:urlString];
    
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
    
    self.currentPageIndex++;
    [self.visitedLinks addObject:url];
}

#pragma mark - Load progress

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"] && object == self.webView) {
        [self updateProgressWithValue:self.webView.estimatedProgress];
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)updateProgressWithValue:(float)value {
    [UIView animateWithDuration:0.2 animations:^{
        self.progressView.progress = value;
    } completion:^(BOOL finished) {
        if (value == 1) {
            self.progressView.progress = 0;
            
            self.reloading = NO;
            [self.searchBar setImage:[UIImage imageNamed:@"icon-refresh"] forSearchBarIcon:UISearchBarIconBookmark state:UIControlStateNormal];
        }
    }];
}

#pragma mark - UITableView

- (void)updateTableWithResults:(NSArray *)result forSearchText:(NSString *)text {
    if ([self.searchBar.text isEqualToString:text]) {
        self.items = result;
        [self.tableView reloadData];
    }
}

- (void)showTableView {
    [self.tableView removeFromSuperview];
    [self.view addSubview:self.tableView];
}

- (void)hideTableVeiw {
    [self.tableView removeFromSuperview];
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"CellId"];
    
    NSString *item = self.items[indexPath.row];
    cell.textLabel.text = item;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *item = (NSString *)self.items[indexPath.row];
    self.currentSiteString = item;
    
    [self searchBarEndTyping];
    [self searchText:item];
}

#pragma mark - WKWebView

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        [webView loadRequest:navigationAction.request];
        
        self.currentPageIndex++;
        [self.visitedLinks addObject:navigationAction.request.URL];
        
        self.searchBar.text = navigationAction.request.URL.absoluteString;
        
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}


@end
