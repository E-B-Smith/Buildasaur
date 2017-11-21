import AppKit

extension NSStepper {
    private struct NSStepperKeys {
        static var valueChanged = "NSStepper_valueChanged"
    }

    @objc var onValueChanged: ((Any?) -> Void)? {
        get {
            return objc_getAssociatedObject(self, &NSStepperKeys.valueChanged) as? ((Any?) -> Void)
        }
        set {
            if let newValue = newValue {
                objc_setAssociatedObject(self,
                                         &NSStepperKeys.valueChanged,
                                         newValue,
                                         .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                self.target = self
                self.action = #selector(valueChanged(_:))
            }
        }
    }

    @objc private func valueChanged(_ sender: Any?) {
        self.onValueChanged?(sender)
    }
}
