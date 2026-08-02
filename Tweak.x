#import <UIKit/UIKit.h>

// 安全清除背景，增加防崩溃判断
static void safeCleanWidgetBackground(UIView *view) {
    if (!view || ![view isKindOfClass:[UIView class]]) return;
    
    // 隐藏毛玻璃材质层（使用 safer class check）
    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"VisualEffect"] || [className containsString:@"MTMaterialView"]) {
        view.hidden = YES;
        return;
    }
    
    // 避免对系统关键私有 View 强行改背景色
    if (![className hasPrefix:@"_UI"]) {
        if (view.backgroundColor && ![view.backgroundColor isEqual:[UIColor clearColor]]) {
            view.backgroundColor = [UIColor clearColor];
        }
    }
    
    // 安全递归
    NSArray *subviews = [view.subviews copy]; // 避免遍历过程中数组被修改导致崩溃
    for (UIView *subview in subviews) {
        safeCleanWidgetBackground(subview);
    }
}

%hook SBHWidgetContainerView

- (void)layoutSubviews {
    %orig;
    
    UIView *selfView = (UIView *)self;
    if (!selfView) return;
    
    // 使用 safer 的方式读取 _materialView，防止 KVC 变量名变化抛出 Exception 崩溃
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
    
    // 安全递归清理微博等第三方 App 内部背景
    safeCleanWidgetBackground(selfView);
}

%end

// Hook 指定类而不是全局 UIViewController，避免与系统或其他插件冲突
%hook CHUISWidgetHostViewController

- (void)viewDidLoad {
    %orig;
    if ([self respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    }
}

%end
