#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 声明私有类继承关系，供 Clang 识别属性
@interface CHUISWidgetHostViewController : UIViewController
@property (nonatomic, assign) UIUserInterfaceStyle overrideUserInterfaceStyle;
@end

// 安全清除背景，增加防崩溃与类型安全判断
static void safeCleanWidgetBackground(UIView *view) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    
    // 隐藏毛玻璃材质层
    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"VisualEffect"] || [className containsString:@"MTMaterialView"]) {
        view.hidden = YES;
        return;
    }
    
    // 避免对系统底层私有 View 强行修改背景色
    if (![className hasPrefix:@"_UI"]) {
        if (view.backgroundColor && ![view.backgroundColor isEqual:[UIColor clearColor]]) {
            view.backgroundColor = [UIColor clearColor];
        }
    }
    
    // 安全递归（copy 子视图数组，防止遍历时数组被修改导致 Crash）
    NSArray *subviews = [view.subviews copy];
    for (UIView *subview in subviews) {
        safeCleanWidgetBackground(subview);
    }
}

%hook SBHWidgetContainerView

- (void)layoutSubviews {
    %orig;
    
    UIView *selfView = (UIView *)self;
    if (!selfView) return;
    
    // 使用 Runtime 安全获取 _materialView，防止 KVC Exception 导致 Safe Mode
    @try {
        Ivar ivar = class_getInstanceVariable([self class], "_materialView");
        if (ivar) {
            UIView *materialView = object_getIvar(self, ivar);
            if (materialView && [materialView isKindOfClass:[UIView class]]) {
                materialView.hidden = YES;
            }
        }
    } @catch (NSException *exception) {
        // 捕获异常，防止 Safe Mode
    }
    
    // 清理微博等第三方 App 内部背景
    safeCleanWidgetBackground(selfView);
}

%end

// 修复负一屏暗色模式错乱
%hook CHUISWidgetHostViewController

- (void)viewDidLoad {
    %orig;
    if ([self respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    }
}

%end
