#import "CCWebView.h"

#import "CCEAGLView.h"
#import "CCFileUtils.h"
#import "CCGLView.h"
#import "CCDirector.h"

@interface UIWebViewWithCloseHandler : UIWebView
{
    void *_ccWebView;
}
- (void)setCCWebView:(void*) ccWebView;
- (void)closeWebView;
@end

@implementation UIWebViewWithCloseHandler

- (void)setCCWebView:(void *)webView
{
    _ccWebView = webView;
}

- (void)closeWebView
{
    if (_ccWebView) {
        ((cocos2d::webview_plugin::CCWebView*)_ccWebView)->destroy();
    }
}

@end

@interface WebViewDelegate : NSObject<UIWebViewDelegate>
{
    // store c++ instance information related to this delegate
    void *object;
}

@property (nonatomic, readwrite) BOOL bannerModeEnable;

@end

@implementation WebViewDelegate
-(id)initWithDelegate:(void *)delegate
{
    self = [super init];
    object = delegate;
    _bannerModeEnable = NO;
    return self;
}

-(BOOL)webView:(UIWebView*)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSString *url = [[request URL] absoluteString];
    cocos2d::webview_plugin::CCWebView *pDelegate = (cocos2d::webview_plugin::CCWebView *)object;
    if([url hasPrefix:@"cocos2dx:"]){
        if(pDelegate != NULL){
            pDelegate->handleCalledFromJS([url UTF8String]);
        }
        return NO;
    }else{
        if (pDelegate != NULL) {
            return !pDelegate->handleShouldOverrideUrlLoading([url UTF8String]);
        }
        if (_bannerModeEnable) {
            [[UIApplication sharedApplication] openURL:[request URL]];
            return NO;
        }
        return YES;
    }
}

-(void)webViewDidFinishLoad:(UIWebView *)webView
{
    cocos2d::webview_plugin::CCWebView *pDelegate = (cocos2d::webview_plugin::CCWebView *)object;
    if (pDelegate != NULL) {
        NSString* url = [[[webView request] URL] absoluteString];
        pDelegate->handleOnPageFinished([url UTF8String]);
    }
}

-(void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    cocos2d::webview_plugin::CCWebView *pDelegate = (cocos2d::webview_plugin::CCWebView *)object;
    if (pDelegate != NULL) {
        NSString* url = [[[webView request] URL] absoluteString];
        pDelegate->handleOnLoadError([url UTF8String]);
    }
}

@end

namespace cocos2d { namespace webview_plugin {

CCWebViewDelegate *CCWebView::s_pWebViewDelegate = NULL;

CCWebView::CCWebView(void *obj){
    mWebView = obj;
    mCloseButton = NULL;
    m_fullScreenMode = false;
}

CCWebView* CCWebView::create(bool fullScreenMode){
    CCWebView *webview = NULL;
    auto glView = Director::getInstance()->getOpenGLView();
    UIView *view = (UIView*) glView->getEAGLView();
    UIWebViewWithCloseHandler *uiView = [[UIWebViewWithCloseHandler alloc] init];
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    
    if(UIInterfaceOrientationIsPortrait(orientation)){
        uiView.frame = CGRectMake(0, 0, view.frame.size.width, view.frame.size.height);
    }else{
        uiView.frame = CGRectMake(0, 0, view.frame.size.height, view.frame.size.width);
    }
    uiView.hidden = YES;
    uiView.dataDetectorTypes = UIDataDetectorTypeNone;
    [view addSubview:uiView];
    webview = new CCWebView((void*)uiView);
    webview->autorelease();
    [uiView setCCWebView:webview];
    
    uiView.delegate = (id<UIWebViewDelegate>)[[WebViewDelegate alloc] initWithDelegate:(void *)webview];
    webview->m_fullScreenMode = fullScreenMode;
    
    return webview;
}

void CCWebView::disableEffect(){
    UIWebView *uiView = (UIWebView*)mWebView;
    for (UIView *view in [[[uiView subviews] objectAtIndex:0] subviews]) {
        if ([view isKindOfClass:[UIImageView class]]) view.hidden = YES;
    }
}
    
CGPoint convertDesignCoordToScreenCoord(const Point& designCoord, bool fullScreenMode = false)
{
    auto glView = Director::getInstance()->getOpenGLView();
    CCEAGLView *eaglView = (CCEAGLView*) glView->getEAGLView();
    float viewH = (float)[eaglView getHeight];
    Point visiblePos = Point(designCoord.x * glView->getScaleX(), designCoord.y * glView->getScaleY());
    Point screenGLPos = visiblePos;
    if(!fullScreenMode){
        screenGLPos = screenGLPos +  glView->getViewPortRect().origin;
    }
    CGPoint screenPos = CGPointMake(screenGLPos.x, viewH - screenGLPos.y);
    screenPos.x = screenPos.x /  [eaglView contentScaleFactor] ;
    screenPos.y = screenPos.y /  [eaglView contentScaleFactor] ;
    
    return screenPos;
}

CGSize convertDesignSizeToScreenSize(const Size& size)
{
    auto glView = Director::getInstance()->getOpenGLView();
    CCEAGLView *eaglView = (CCEAGLView*) glView->getEAGLView();
    CGSize controlSize = CGSizeMake(size.width * glView->getScaleX(),size.height * glView->getScaleY());
    controlSize.width /=  [eaglView contentScaleFactor] ;
    controlSize.height /=  [eaglView contentScaleFactor] ;
    return controlSize;
}

inline CGRect getRectForIOS(int x, int y, int w, int h, bool fullScreenMode = false) {
    CGPoint point = convertDesignCoordToScreenCoord(Point(x,y + h), fullScreenMode);
    CGSize size = convertDesignSizeToScreenSize(Size(w,h));
    CCLOG("getRectForIOS %f %f %f %f", point.x, point.y, size.width, size.height);
    return CGRectMake(point.x, point.y, size.width, size.height);
}
    
void CCWebView::setRect(int x, int y, int w, int h){
    auto glView = Director::getInstance()->getOpenGLView();
    CCEAGLView *eaglView = (CCEAGLView*) glView->getEAGLView();
    UIWebView *uiView = (UIWebView*)mWebView;
    if(m_fullScreenMode){
        uiView.frame = CGRectMake(0,
                                  0,
                                  [eaglView getWidth]  / [eaglView contentScaleFactor],
                                  [eaglView getHeight] / [eaglView contentScaleFactor]);
    }else{
        uiView.frame = getRectForIOS(x, y, w, h);
    }
}

void CCWebView::loadUrl(const char *url, bool transparent/* =false */){
    NSString *nsStr = NSLocalizedString([[NSString alloc] initWithUTF8String:url], @"Url");
    NSURL *nsUrl = [NSURL URLWithString:nsStr];
    NSURLRequest *request = [NSURLRequest requestWithURL:nsUrl];

    UIWebView *uiView = (UIWebView*)mWebView;
    if (transparent) {
        [uiView setBackgroundColor:[UIColor clearColor]];
        [uiView setOpaque:NO];
    }
    [uiView loadRequest:request];
}

void CCWebView::loadHtml(const char *filepath, bool transparent/* =false */){
    NSString *path = [[NSBundle mainBundle] pathForResource:[[NSString alloc] initWithUTF8String:filepath] ofType:@"html"];
    NSURLRequest *request =[NSURLRequest requestWithURL:[NSURL fileURLWithPath:path]];
    
    UIWebView *uiView = (UIWebView*)mWebView;
    if (transparent) {
        [uiView setBackgroundColor:[UIColor clearColor]];
        [uiView setOpaque:NO];
    }
    [uiView loadRequest:request];
}

void CCWebView::clearCache(){
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}
    
void CCWebView::setVisibility(bool enable){
    UIWebView *uiView = (UIWebView*)mWebView;
    uiView.hidden = enable ? NO : YES;
    if (mCloseButton) {
        UIView* button = (UIView*)mCloseButton;
        button.hidden = uiView.hidden;
    }
}

std::string CCWebView::evaluateJS(const char* js){
    UIWebView *uiView = (UIWebView*)mWebView;
    NSString *jsStr = NSLocalizedString([[NSString alloc] initWithUTF8String:js], @"JS");
    NSString* result = [uiView stringByEvaluatingJavaScriptFromString:jsStr];
    return std::string([result UTF8String]);
}

void CCWebView::destroy(){
    if (mWebView) {
        UIWebView *uiView = (UIWebView*)mWebView;
        WebViewDelegate *delegate = uiView.delegate;
        [delegate release];
        [uiView removeFromSuperview];
        [uiView release];
        mWebView = NULL;
    }
    if (mCloseButton) {
        UIView* button = (UIView*)mCloseButton;
        [button removeFromSuperview];
        [button release];
        mCloseButton = NULL;
    }
}

void CCWebView::handleCalledFromJS(const char *message){
    CCWebViewDelegate *delegate = CCWebView::getWebViewDelegate();
    if(delegate != NULL){
        auto str = std::string(message);
        delegate->callbackFromJS(this, str);
    }
}
    
bool CCWebView::handleShouldOverrideUrlLoading(const char* url) {
    CCWebViewDelegate *delegate = CCWebView::getWebViewDelegate();
    if (delegate) {
        std::string str = std::string(url);
        return delegate->shouldOverrideUrlLoading(this, str);
    }
    return false;
}
    
void CCWebView::handleOnPageFinished(const char* url) {
    CCWebViewDelegate *delegate = CCWebView::getWebViewDelegate();
    if (delegate) {
        std::string str = std::string(url);
        return delegate->onPageFinished(this, str);
    }
}

void CCWebView::handleOnLoadError(const char* url) {
    CCWebViewDelegate *delegate = CCWebView::getWebViewDelegate();
    if (delegate) {
        std::string str = std::string(url);
        return delegate->onLoadError(this, str);
    }
}

    
void CCWebView::setBannerModeEnable(bool enable)
{
    UIWebView* webview = (UIWebView *)mWebView;
    WebViewDelegate* delegate = webview.delegate;
    delegate.bannerModeEnable = enable;
}
    
    
    
    void CCWebView::setCloseButton(const char * imageName, int x, int y, int w, int h)
    {
        auto glView = Director::getInstance()->getOpenGLView();
        UIView* uiView = (CCEAGLView*) glView->getEAGLView();
//        UIView* uiView = [EAGLView sharedEGLView];
        UIWebViewWithCloseHandler *webView = (UIWebViewWithCloseHandler*)mWebView;
        
        std::string imagePath = FileUtils::getInstance()->fullPathForFilename(imageName);
        
        UIButton* button = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage* image = [[UIImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:imagePath.c_str()]];
        [button setImage:image forState:UIControlStateNormal];
        [image release];
        [button addTarget:webView action:@selector(closeWebView) forControlEvents:UIControlEventTouchUpInside];
        
        button.frame = getRectForIOS(x, y, w, h, m_fullScreenMode);
        if (mCloseButton) {
            UIView* view = (UIView*)mCloseButton;
            [view removeFromSuperview];
            [view release];
        }
        [button retain];
        button.hidden = webView.hidden;
        mCloseButton = button;
        
        [uiView addSubview:button];
    }
    
    void CCWebView::setUrlSchemeNotFoundMessage(const char *message)
    {
        // Do nothing
    }

}}

