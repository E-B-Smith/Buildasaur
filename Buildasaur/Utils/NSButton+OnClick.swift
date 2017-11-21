import AppKit

extension NSButton {
    private struct NSButtonKeys {
        static var click = "NSButton_click"
    }

    @objc var onClick: ((AnyObject?) -> Void)? {
        get {
            return objc_getAssociatedObject(self, &NSButtonKeys.click) as? ((AnyObject?) -> Void)
        }
        set {
            if let newValue = newValue {
                objc_setAssociatedObject(self,
                                         &NSButtonKeys.click,
                                         newValue,
                                         .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                self.target = self
                self.action = #selector(click(_:))
            }
        }
    }

    @objc private func click(_ sender: AnyObject?) {
        self.onClick?(sender)
    }
}
