//
//  TriggerViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 14/03/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import XcodeServerSDK
import BuildaUtils
import BuildaKit

protocol TriggerViewControllerDelegate: class {
    func triggerViewController(_ triggerViewController: NSViewController, didCancelEditingTrigger trigger: TriggerConfig)
    func triggerViewController(_ triggerViewController: NSViewController, didSaveTrigger trigger: TriggerConfig)
}

class TriggerViewController: NSViewController {

    static let storyboardID: String = "triggerViewController"

    var triggerConfig: TriggerConfig! = nil {
        didSet {
            self.updateTriggerConfig()
        }
    }
    var storageManager: StorageManager!

    weak var delegate: TriggerViewControllerDelegate?

    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var cancelButton: NSButton!
    @IBOutlet weak var closeButton: NSButton!
    @IBOutlet weak var nameTextField: NSTextField!
    @IBOutlet weak var kindPopup: NSPopUpButton!
    @IBOutlet weak var phasePopup: NSPopUpButton!
    @IBOutlet weak var emailConfigStackItem: NSStackView!
    @IBOutlet weak var postbuildConfigStackItem: NSStackView!

    @IBOutlet weak var bodyTextField: NSTextField!
    @IBOutlet weak var bodyDescriptionLabel: NSTextField!

    //conditions - enabled only for Postbuild
    @IBOutlet weak var conditionSuccessCheckbox: NSButton!
    @IBOutlet weak var conditionWarningsCheckbox: NSButton!
    @IBOutlet weak var conditionAnalyzerWarningsCheckbox: NSButton!
    @IBOutlet weak var conditionFailingTestsCheckbox: NSButton!
    @IBOutlet weak var conditionBuildErrorsCheckbox: NSButton!
    @IBOutlet weak var conditionInternalErrorCheckbox: NSButton!

    //email config - enabled only for Email
    @IBOutlet weak var emailEmailCommittersCheckbox: NSButton!
    @IBOutlet weak var emailIncludeCommitsCheckbox: NSButton!
    @IBOutlet weak var emailIncludeIssueDetailsCheckbox: NSButton!

    //state
    private var phases: [TriggerConfig.Phase] = TriggerViewController.allPhases() {
        didSet {
            self.updatePhases()
        }
    }
    private var kinds: [TriggerConfig.Kind] = [] {
        didSet {
            self.updateKinds()
        }
    }

    private var selectedKind: TriggerConfig.Kind = .runScript {
        didSet {
            if self.selectedKind == .emailNotification
                && self.bodyTextField.stringValue == self.triggerConfig?.scriptBody {
                self.bodyTextField.stringValue = ""
            }
            self.updateKind()
        }
    }
    private var selectedPhase: TriggerConfig.Phase = .prebuild {
        didSet {
            self.updatePhase()
        }
    }
    private var emailConfiguration: EmailConfiguration?
    private var conditions: TriggerConditions?
    private var isValid: Bool = false {
        didSet {
            self.saveButton.isEnabled = self.isValid
        }
    }
    private var generatedTrigger: TriggerConfig?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.nameTextField.delegate = self
        self.bodyTextField.delegate = self

        self.setupPhases()
        self.setupKinds()
        self.setupConditions()
        self.setupEmailConfiguration()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        self.updateTriggerConfig()

        self.updatePhases()
        self.updateKinds()

        self.validateAndGenerate()
    }

    // MARK: Setup

    private func updateKinds() {
        let popup = self.kindPopup
        popup?.removeAllItems()
        let displayNames = self.kinds.map { "\($0.toString())" }
        popup?.addItems(withTitles: displayNames)

        if let index = self.kinds.index(of: self.selectedKind) {
            popup?.selectItem(at: index)
        }
    }

    private func updateKind() {
        let title: String
        if self.selectedKind == .runScript {
            title = "Script Body"
        } else {
            title = "Additional Email Recipients (Comma separated)"
        }
        self.bodyDescriptionLabel.stringValue = title
        self.bodyTextField.placeholderString = title

        self.emailConfigStackItem.isHidden = self.selectedKind != .emailNotification
    }

    private func setupKinds() {
        if self.kinds.index(of: self.selectedKind) == nil {
            self.selectedKind = self.kinds.first!
            self.kindPopup.selectItem(at: 0)
        }

        self.kindPopup.onClick = { [weak self] _ in
            guard let sself = self else { return }

            let index = sself.kindPopup.indexOfSelectedItem
            let all = sself.kinds
            sself.selectedKind = all[index]
        }
    }

    private func updatePhases() {
        let popup = self.phasePopup
        popup?.removeAllItems()
        let displayNames = self.phases.map { "\($0.toString())" }
        popup?.addItems(withTitles: displayNames)

        if let index = self.phases.index(of: self.selectedPhase) {
            popup?.selectItem(at: index)
        }
    }

    private func updatePhase() {
        self.postbuildConfigStackItem.isHidden = self.selectedPhase != .postbuild
        self.kinds = TriggerViewController.allKinds(self.selectedPhase)
    }

    private func setupPhases() {
        self.updatePhase()
        self.phasePopup.onClick = { [weak self] _ in
            guard let sself = self else { return }

            let index = sself.phasePopup.indexOfSelectedItem
            let all = sself.phases
            sself.selectedPhase = all[index]
        }
    }

    private func setupConditions() {
        let updateConditions: (AnyObject?) -> Void = { [weak self] _ in
            self?.updateConditions()
        }
        self.conditionSuccessCheckbox.onClick = updateConditions
        self.conditionWarningsCheckbox.onClick = updateConditions
        self.conditionAnalyzerWarningsCheckbox.onClick = updateConditions
        self.conditionFailingTestsCheckbox.onClick = updateConditions
        self.conditionBuildErrorsCheckbox.onClick = updateConditions
        self.conditionInternalErrorCheckbox.onClick = updateConditions

        self.updateConditions()
    }

    private func updateConditions() {
        let success = self.conditionSuccessCheckbox.on
        let warnings = self.conditionWarningsCheckbox.on
        let analyzerWarnings = self.conditionAnalyzerWarningsCheckbox.on
        let testFailures = self.conditionFailingTestsCheckbox.on
        let buildErrors = self.conditionBuildErrorsCheckbox.on
        let internalErrors = self.conditionInternalErrorCheckbox.on

        if self.selectedPhase == .postbuild {
            self.conditions = TriggerConditions(onAnalyzerWarnings: analyzerWarnings, onBuildErrors: buildErrors, onFailingTests: testFailures, onInternalErrors: internalErrors, onSuccess: success, onWarnings: warnings)
        } else {
            self.conditions = nil
        }
    }

    private func setupEmailConfiguration() {
        let updateEmailConfiguration: (AnyObject?) -> Void = { [weak self] _ in
            self?.updateEmailConfiguration()
        }
        self.emailEmailCommittersCheckbox.onClick = updateEmailConfiguration
        self.emailIncludeCommitsCheckbox.onClick = updateEmailConfiguration
        self.emailIncludeIssueDetailsCheckbox.onClick = updateEmailConfiguration

        self.updateConditions()
    }

    private func updateEmailConfiguration() {
        let includeCommitters = self.emailEmailCommittersCheckbox.on
        let includeCommits = self.emailIncludeCommitsCheckbox.on
        let includeIssues = self.emailIncludeIssueDetailsCheckbox.on
        let additionalEmails = self.bodyTextField.stringValue
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "")
            .components(separatedBy: ",")
            .filter { !$0.isEmpty }

        if self.selectedKind == .emailNotification {
            self.emailConfiguration = EmailConfiguration(additionalRecipients: additionalEmails, emailCommitters: includeCommitters, includeCommitMessages: includeCommits, includeIssueDetails: includeIssues)
        } else {
            self.emailConfiguration = nil
        }
    }

    private func validateAndGenerate() {
        let name = self.nameTextField.stringValue
        let kind = self.selectedKind
        let body = self.bodyTextField.stringValue

        if name.isEmpty {
            self.isValid = false
            return
        }

        //if the type is script, the script body cannot be empty
        if kind == .runScript && body.isEmpty {
            self.isValid = false
            return
        }

        self.isValid = true
        self.generateTemplate()
    }

    private func generateTemplate() {
        guard self.isValid else { return }

        let name = self.nameTextField.stringValue
        let kind = self.selectedKind
        let phase = self.selectedPhase
        let body = self.bodyTextField.stringValue
        let conditions = self.conditions
        let emailConfiguration = self.emailConfiguration
        let original = self.triggerConfig

        var trigger = original!
        trigger.phase = phase
        trigger.kind = kind
        let scriptBody = (kind == .runScript) ? body : ""
        trigger.scriptBody = scriptBody
        trigger.name = name
        trigger.conditions = conditions
        trigger.emailConfiguration = emailConfiguration

        self.generatedTrigger = trigger
    }

    private func updateTriggerConfig() {
        self.nameTextField.stringValue = self.triggerConfig.name

        self.selectedPhase = self.triggerConfig.phase
        let phaseIndex = self.phases.index(of: self.triggerConfig.phase) ?? 0
        self.phasePopup.selectItem(at: phaseIndex)

        self.selectedKind = self.triggerConfig.kind
        let kindIndex = self.kinds.index(of: self.triggerConfig.kind) ?? 0
        self.kindPopup.selectItem(at: kindIndex)

        //kinds?
        if self.triggerConfig.kind == .emailNotification {
            let emailConfig = self.triggerConfig.emailConfiguration!

            let body = emailConfig.additionalRecipients.joined(separator: ", ")
            self.bodyTextField.stringValue = body
            self.emailEmailCommittersCheckbox.on = emailConfig.emailCommitters
            self.emailIncludeCommitsCheckbox.on = emailConfig.includeCommitMessages
            self.emailIncludeIssueDetailsCheckbox.on = emailConfig.includeIssueDetails
        } else {
            self.bodyTextField.stringValue = self.triggerConfig.scriptBody
        }

        //phases?
        if self.triggerConfig.phase == .postbuild {
            let con = self.triggerConfig.conditions!
            self.conditionAnalyzerWarningsCheckbox.on = con.onAnalyzerWarnings
            self.conditionBuildErrorsCheckbox.on = con.onBuildErrors
            self.conditionFailingTestsCheckbox.on = con.onFailingTests
            self.conditionInternalErrorCheckbox.on = con.onInternalErrors
            self.conditionSuccessCheckbox.on = con.onSuccess
            self.conditionWarningsCheckbox.on = con.onWarnings
        }
    }

    // MARK: actions

    @IBAction func saveButtonClicked(_ sender: NSButton) {

        let currentTrigger = self.generatedTrigger!

        //save current trigger
        self.storageManager.addTriggerConfig(triggerConfig: currentTrigger)

        //notify delegate
        self.delegate?.triggerViewController(self, didSaveTrigger: currentTrigger)
    }

    @IBAction func cancelButtonClicked(_ sender: NSButton) {

        //in case of cancel we could never have had a valid trigger, so just
        //use the original trigger in that case. we only care about the id anyway.
        let currentTrigger = self.generatedTrigger ?? self.triggerConfig!
        self.delegate?.triggerViewController(self, didCancelEditingTrigger: currentTrigger)
    }

    // MARK: consts

    static func allPhases() -> [TriggerConfig.Phase] {
        return [
            TriggerConfig.Phase.prebuild,
            TriggerConfig.Phase.postbuild
        ]
    }

    static func allKinds(_ phase: TriggerConfig.Phase) -> [TriggerConfig.Kind] {
        var kinds = [TriggerConfig.Kind.runScript]
        if phase == .postbuild {
            kinds.append(TriggerConfig.Kind.emailNotification)
        }
        return kinds
    }
}

extension TriggerViewController: NSTextFieldDelegate {
    override func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            self.validateAndGenerate()

            if textField == self.bodyDescriptionLabel && self.selectedKind == .emailNotification {
                self.updateEmailConfiguration()
            }
        }
    }

    //Taken from https://developer.apple.com/library/mac/qa/qa1454/_index.html
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control == self.bodyDescriptionLabel else {
            return false
        }

        let result: Bool
        switch commandSelector {

        case #selector(insertNewline(_:)):
            // new line action:
            // always insert a line-break character and don’t cause the receiver to end editing
            textView.insertNewlineIgnoringFieldEditor(self)
            result = true

        case #selector(insertTab(_:)):
            // tab action:
            // always insert a tab character and don’t cause the receiver to end editing
            textView.insertTabIgnoringFieldEditor(self)
            result = true

        default:
            result = false
        }

        return result
    }
}
