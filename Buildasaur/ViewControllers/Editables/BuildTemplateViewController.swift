//
//  BuildTemplateViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 09/03/15.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import AppKit
import BuildaUtils
import XcodeServerSDK
import BuildaKit

protocol BuildTemplateViewControllerDelegate: class {
    func didCancelEditingOfBuildTemplate(_ template: BuildTemplate)
    func didSaveBuildTemplate(_ template: BuildTemplate)
}

class BuildTemplateViewController: ConfigEditViewController, NSTableViewDataSource, NSTableViewDelegate {

    var buildTemplate: BuildTemplate = BuildTemplate() {
        didSet {
            self.nameTextField.stringValue = self.buildTemplate.name

            self.selectedScheme = self.buildTemplate.scheme
            if self.schemesPopup.doesContain(self.buildTemplate.scheme) {
                self.schemesPopup.selectItem(withTitle: self.buildTemplate.scheme)
            } else {
                self.schemesPopup.selectItem(at: 0)
            }
            let index = self.schemesPopup.indexOfSelectedItem
            let schemes = self.schemes
            let scheme = schemes[index]
            self.selectedScheme = scheme.name

            self.analyzeButton.on = self.buildTemplate.shouldAnalyze
            self.testButton.on = self.buildTemplate.shouldTest
            self.archiveButton.on = self.buildTemplate.shouldArchive

            self.allowServerToManageCertificate.on = self.buildTemplate.manageCertsAndProfiles
            self.automaticallyRegisterDevices.on = self.buildTemplate.addMissingDevicesToTeams
            self.automaticallyRegisterDevices.isEnabled = self.allowServerToManageCertificate.on

            let schedule = self.buildTemplate.schedule
            let scheduleIndex = self.schedules.index(of: schedule.schedule)
            self.schedulePopup.selectItem(at: scheduleIndex ?? 0)
            self.selectedSchedule = schedule

            let cleaningPolicyIndex = self.cleaningPolicies.index(of: self.buildTemplate.cleaningPolicy)
            self.cleaningPolicyPopup.selectItem(at: cleaningPolicyIndex ?? 0)
            self.deviceFilter = self.buildTemplate.deviceFilter
            self.selectedDeviceIds = self.buildTemplate.testingDeviceIds

            self.triggers = self.storageManager.triggerConfigsForIds(ids: self.buildTemplate.triggers)

            self.validateAndGenerate()
        }
    }
    weak var delegate: BuildTemplateViewControllerDelegate?
    var projectRef: RefType! {
        didSet {
            self.project = self.syncerManager.projectWithRef(ref: self.projectRef)
        }
    }
    var xcodeServerRef: RefType! {
        didSet {
            self.xcodeServer = self.syncerManager.xcodeServerWithRef(ref: self.xcodeServerRef)
        }
    }

    // ---

    private var project: Project! = nil {
        didSet {
            self.schemes = self.project.schemes().sorted { $0.name < $1.name }
        }
    }
    private var xcodeServer: XcodeServer! = nil

    @IBOutlet weak var stackView: NSStackView!
    @IBOutlet weak var nameTextField: NSTextField!
    @IBOutlet weak var testDevicesActivityIndicator: NSProgressIndicator!
    @IBOutlet weak var schemesPopup: NSPopUpButton!
    @IBOutlet weak var analyzeButton: NSButton!
    @IBOutlet weak var testButton: NSButton!
    @IBOutlet weak var archiveButton: NSButton!
    @IBOutlet weak var allowServerToManageCertificate: NSButton!
    @IBOutlet weak var automaticallyRegisterDevices: NSButton!
    @IBOutlet weak var schedulePopup: NSPopUpButton!
    @IBOutlet weak var cleaningPolicyPopup: NSPopUpButton!
    @IBOutlet weak var triggersTableView: NSTableView!
    @IBOutlet weak var deviceFilterPopup: NSPopUpButton!
    @IBOutlet weak var devicesTableView: NSTableView!
    @IBOutlet weak var deviceFilterStackItem: NSStackView!
    @IBOutlet weak var testDevicesStackItem: NSStackView!

    private var isDevicesUpToDate: Bool = true {
        didSet {
            if !self.isDevicesUpToDate {
                self.testDevicesActivityIndicator.startAnimation(nil)
            } else {
                self.testDevicesActivityIndicator.stopAnimation(nil)
            }
            self.updateNextAllowed()
        }
    }
    private var isPlatformsUpToDate: Bool = true {
        didSet {
            self.updateNextAllowed()
        }
    }
    private var isDeviceFiltersUpToDate: Bool = true {
        didSet {
            self.updateNextAllowed()
        }
    }

    private var testingDevices: [Device] = [] {
        didSet {
            self.devicesTableView.reloadData()
        }
    }
    private var schemes: [XcodeScheme] = [] {
        didSet {
            self.schemesPopup.replaceItems(self.schemes.map { $0.name })
        }
    }
    private var schedules: [BotSchedule.Schedule] = [] {
        didSet {
            self.schedulePopup.replaceItems(self.schedules.map { $0.toString() })
        }
    }
    private var cleaningPolicies: [BotConfiguration.CleaningPolicy] = [] {
        didSet {
            self.cleaningPolicyPopup.replaceItems(self.cleaningPolicies.map { $0.toString() })
        }
    }
    private var deviceFilters: [DeviceFilter.FilterType] = [] {
        didSet {
            self.deviceFilterPopup.replaceItems(self.deviceFilters.map { $0.toString() })

            //ensure that when the device filters change that we
            //make sure our selected one is still valid
            self.isDeviceFiltersUpToDate = false

            if self.deviceFilters.index(of: self.deviceFilter) == nil {
                self.deviceFilter = .allAvailableDevicesAndSimulators
            }

            //also ensure that the selected filter is in fact visually selected
            let deviceFilterIndex = self.deviceFilters.index(of: self.deviceFilter)
            self.deviceFilterPopup.selectItem(at: deviceFilterIndex ?? DeviceFilter.FilterType.allAvailableDevicesAndSimulators.rawValue)

            Log.verbose("Finished fetching devices")
            self.isDeviceFiltersUpToDate = true
        }
    }

    private var selectedScheme: String! {
        didSet {
            self.isDeviceFiltersUpToDate = false
            self.isDevicesUpToDate = false
            self.isPlatformsUpToDate = false

            self.devicePlatformFromScheme(self.selectedScheme) { [weak self] platformType in
                self?.platformType = platformType
            }

            self.validateAndGenerate()
        }
    }
    private var platformType: DevicePlatform.PlatformType? {
        didSet {
            if let platformType = self.platformType {
                //refetch/refilter devices
                self.isDevicesUpToDate = false
                self.fetchDevices(platformType) { () -> Void in
                    Log.verbose("Finished fetching devices")
                    self.isDevicesUpToDate = true
                }
                self.deviceFilters = BuildTemplateViewController.allDeviceFilters(platformType)
                Log.verbose("Finished fetching platform")
                self.isPlatformsUpToDate = true
            }

            self.validateAndGenerate()
        }
    }
    private var cleaningPolicy: BotConfiguration.CleaningPolicy = .never {
        didSet {
            self.validateAndGenerate()
        }
    }
    private var deviceFilter: DeviceFilter.FilterType = .selectedDevicesAndSimulators {
        didSet {
            self.devicesTableView.isEnabled = self.deviceFilter == .selectedDevicesAndSimulators
            if self.deviceFilter != .selectedDevicesAndSimulators {
                self.selectedDeviceIds = []
            }
            self.validateAndGenerate()
        }
    }
    private var selectedSchedule: BotSchedule = BotSchedule.manualBotSchedule() {
        didSet {
            self.validateAndGenerate()
        }
    }
    private var selectedDeviceIds: [String] = [] {
        didSet {
            self.devicesTableView.reloadData()
            self.validateAndGenerate()
        }
    }
    private var triggers: [TriggerConfig] = [] {
        didSet {
            self.triggersTableView.reloadData()
            self.validateAndGenerate()
        }
    }

    private var isValid: Bool = false {
        didSet {
            self.updateNextAllowed()
        }
    }
    private var generatedTemplate: BuildTemplate!

    private var triggerToEdit: TriggerConfig?

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupBindings()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        self.updateNextAllowed()
    }

    private func updateNextAllowed() {
        self.nextAllowed = self.isValid && self.platformType != nil && self.isDevicesUpToDate && self.isPlatformsUpToDate && self.isDeviceFiltersUpToDate
    }

    private func setupBindings() {
        //ui
        self.selectedScheme = self.buildTemplate.scheme

        self.setupSchemes()
        self.setupSchedules()
        self.setupCleaningPolicies()
        self.setupDeviceFilter()

        self.nameTextField.delegate = self

        self.analyzeButton.onClick = { [weak self] _ in
            guard let sself = self else { return }
            sself.validateAndGenerate()
        }
        self.testButton.onClick = { [weak self] _ in
            guard let sself = self else { return }

            sself.deviceFilterStackItem.isHidden = !sself.testButton.on
            sself.testDevicesStackItem.isHidden = !sself.testButton.on
            if !sself.testButton.on {
                sself.selectedDeviceIds = []
                sself.deviceFilter = .allAvailableDevicesAndSimulators
                sself.deviceFilterPopup.selectItem(at: DeviceFilter.FilterType.allAvailableDevicesAndSimulators.rawValue)
            }
            sself.validateAndGenerate()
        }
        self.analyzeButton.onClick = { [weak self] _ in
            guard let sself = self else { return }
            sself.validateAndGenerate()
        }
        self.allowServerToManageCertificate.onClick = { [weak self] _ in
            guard let sself = self else { return }
            sself.automaticallyRegisterDevices.isEnabled = sself.allowServerToManageCertificate.on
            sself.validateAndGenerate()
        }
        self.automaticallyRegisterDevices.onClick = { [weak self] _ in
            guard let sself = self else { return }
            sself.validateAndGenerate()
        }

        self.generateTemplate()
    }

    private func devicePlatformFromScheme(_ schemeName: String, _ completion: ((DevicePlatform.PlatformType?) -> Void)?) {
        guard let scheme = self.schemes.first(where: { $0.name == schemeName }) else { return }

        DispatchQueue.global().async {
            do {
                let platformType = try XcodeDeviceParser.parseDeviceTypeFromProjectUrlAndScheme(projectUrl: self.project.url, scheme: scheme).toPlatformType()
                DispatchQueue.main.async {
                    completion?(platformType)
                }
            } catch {
                DispatchQueue.main.async {
                    UIUtils.showAlertWithError(error)
                }
            }
        }
    }

    private func setupSchemes() {
        //action
        self.schemesPopup.onClick = { [weak self] _ in
            guard let sself = self else { return }

            let index = sself.schemesPopup.indexOfSelectedItem
            let schemes = sself.schemes
            let scheme = schemes[index]
            sself.selectedScheme = scheme.name
        }
    }

    private func setupSchedules() {
        //data source
        self.schedules = self.allSchedules()

        //action
        self.schedulePopup.onClick = { [weak self] _ in
            guard let sself = self else { return }

            let index = sself.schedulePopup.indexOfSelectedItem
            let schedules = sself.schedules
            let scheduleType = schedules[index]
            var schedule: BotSchedule!

            switch scheduleType {
            case .commit:
                schedule = BotSchedule.commitBotSchedule()
            case .manual:
                schedule = BotSchedule.manualBotSchedule()
            default:
                assertionFailure("Other schedules not yet supported")
            }

            sself.selectedSchedule = schedule
        }
    }

    private func setupCleaningPolicies() {
        //data source
        self.cleaningPolicies = self.allCleaningPolicies()

        //action
        self.cleaningPolicyPopup.onClick = { [weak self] _ in
            guard let sself = self else { return }

            let index = sself.cleaningPolicyPopup.indexOfSelectedItem
            let policies = sself.cleaningPolicies
            let policy = policies[index]
            sself.cleaningPolicy = policy
        }
    }

    private func setupDeviceFilter() {
        //action
        self.deviceFilterPopup.onClick = { [weak self] _ in
            guard let sself = self else { return }

            let index = sself.deviceFilterPopup.indexOfSelectedItem
            let filters = sself.deviceFilters
            let filter = filters[index]
            sself.deviceFilter = filter
        }
    }

    private func validateAndGenerate() {
        let name = self.nameTextField.stringValue
        let scheme = self.selectedScheme
        let analyze = self.analyzeButton.on
        let test = self.testButton.on
        let archive = self.archiveButton.on

        if self.platformType == nil {
            self.isValid = false
            return
        }

        //make sure the name isn't empty
        if name.isEmpty {
            self.isValid = false
            return
        }

        //make sure the selected scheme is valid
        if self.schemes.filter({ $0.name == scheme }).isEmpty {
            self.isValid = false
            return
        }

        //at least one of the three actions has to be selected
        if !analyze && !test && !archive {
            self.isValid = false
            return
        }

        self.isValid = true
        self.generateTemplate()
    }

    private func generateTemplate() {
        guard self.isValid else { return }

        let name = self.nameTextField.stringValue
        let scheme = self.selectedScheme!
        let platformType = self.platformType!
        let analyze = self.analyzeButton.on
        let test = self.testButton.on
        let archive = self.archiveButton.on
        let allowServerToManageCertificate = self.allowServerToManageCertificate.on
        let automaticallyRegisterDevices = self.automaticallyRegisterDevices.on
        let schedule = self.selectedSchedule
        let cleaningPolicy = self.cleaningPolicy
        let triggers = self.triggers
        let deviceFilter = self.deviceFilter
        let deviceIds = self.selectedDeviceIds

        let original = self.buildTemplate

        var mod = original
        mod.projectName = self.project.config.name
        mod.name = name
        mod.scheme = scheme
        mod.platformType = platformType
        mod.shouldAnalyze = analyze
        mod.shouldTest = test
        mod.shouldArchive = archive
        mod.manageCertsAndProfiles = allowServerToManageCertificate
        mod.addMissingDevicesToTeams = automaticallyRegisterDevices
        mod.schedule = schedule
        mod.cleaningPolicy = cleaningPolicy
        mod.triggers = triggers.map { $0.id }
        mod.deviceFilter = deviceFilter
        mod.testingDeviceIds = deviceIds

        self.generatedTemplate = mod
    }

    func fetchDevices(_ platform: DevicePlatform.PlatformType, completion: @escaping () -> Void) {
        self.xcodeServer.getDevices { (devices, error) in
            if error != nil || devices == nil {
                UIUtils.showAlertWithError(error!)
            }

            self.testingDevices = BuildTemplateViewController.processReceivedDevices(devices!, platform: platform)
            completion()
        }
    }

    private static func processReceivedDevices(_ devices: [Device], platform: DevicePlatform.PlatformType) -> [Device] {
        let allowedPlatforms: Set<DevicePlatform.PlatformType>
        switch platform {
        case .iOS, .iOS_Simulator:
            allowedPlatforms = Set([.iOS, .iOS_Simulator])
        case .tvOS, .tvOS_Simulator:
            allowedPlatforms = Set([.tvOS, .tvOS_Simulator])
        default:
            allowedPlatforms = Set([platform])
        }

        //filter first
        let filtered = devices.filter { allowedPlatforms.contains($0.platform) }

        let sortDevices = {
            (a: Device, b: Device) -> (equal: Bool, shouldGoBefore: Bool) in

            if a.simulator == b.simulator {
                return (equal: true, shouldGoBefore: true)
            }
            return (equal: false, shouldGoBefore: !a.simulator)
        }

        let sortByName = {
            (a: Device, b: Device) -> (equal: Bool, shouldGoBefore: Bool) in

            if a.name == b.name {
                return (equal: true, shouldGoBefore: false)
            }
            return (equal: false, shouldGoBefore: a.name < b.name)
        }

        let sortByOSVersion = {
            (a: Device, b: Device) -> (equal: Bool, shouldGoBefore: Bool) in

            if a.osVersion == b.osVersion {
                return (equal: true, shouldGoBefore: false)
            }
            return (equal: false, shouldGoBefore: a.osVersion < b.osVersion)
        }

        //then sort, devices first and if match, then by name & os version
        let sortedDevices = filtered.sorted { (a, b) -> Bool in

            let (equalDevices, goBeforeDevices) = sortDevices(a, b)
            if !equalDevices {
                return goBeforeDevices
            }

            let (equalName, goBeforeName) = sortByName(a, b)
            if !equalName {
                return goBeforeName
            }

            let (equalOSVersion, goBeforeOSVersion) = sortByOSVersion(a, b)
            if !equalOSVersion {
                return goBeforeOSVersion
            }
            return true
        }

        return sortedDevices
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        let destinationController = segue.destinationController as! NSViewController

        if let triggerViewController = destinationController as? TriggerViewController {
            triggerViewController.loadView()
            let triggerToEdit = self.triggerToEdit ?? TriggerConfig()
            triggerViewController.triggerConfig = triggerToEdit
            triggerViewController.storageManager = self.storageManager
            triggerViewController.delegate = self
            self.triggerToEdit = nil
        } else if let selectTriggerViewController = destinationController as? SelectTriggerViewController {
            selectTriggerViewController.storageManager = self.storageManager
            selectTriggerViewController.delegate = self
        }

        super.prepare(for: segue, sender: sender)
    }

    @IBAction func addTriggerButtonClicked(_ sender: AnyObject) {
        if self.storageManager.triggerConfigs.isEmpty {
            self.editTrigger(nil)
            return
        }
        let buttons = ["Add new", "Add existing", "Cancel"]
        UIUtils.showAlertWithButtons("Would you like to add a new trigger or add existing one?", buttons: buttons, style: .informational, completion: { (tappedButton) -> Void in
            switch tappedButton {
            case "Add new":
                self.editTrigger(nil)
            case "Add existing":
                self.performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "selectTriggers"), sender: nil)
            default: break
            }
        })
    }

    override func shouldGoNext() -> Bool {

        guard self.isValid else { return false }

        let newBuildTemplate = self.generatedTemplate!
        self.buildTemplate = newBuildTemplate
        self.storageManager.addBuildTemplate(buildTemplate: newBuildTemplate)
        self.delegate?.didSaveBuildTemplate(newBuildTemplate)

        return true
    }

    override func delete() {

        UIUtils.showAlertAskingForRemoval("Are you sure you want to delete this Build Template?", completion: { (remove) -> Void in
            if remove {
                let template = self.generatedTemplate!
                self.storageManager.removeBuildTemplate(buildTemplate: template)
                self.delegate?.didCancelEditingOfBuildTemplate(template)
            }
        })
    }

    // MARK: triggers table view
    func numberOfRows(in tableView: NSTableView) -> Int {

        if tableView == self.triggersTableView {
            return self.triggers.count
        } else if tableView == self.devicesTableView {
            return self.testingDevices.count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if tableView == self.triggersTableView {
            let triggers = self.triggers
            if tableColumn!.identifier.rawValue == "names" {

                let trigger = triggers[row]
                return trigger.name
            }
        } else if tableView == self.devicesTableView {

            let device = self.testingDevices[row]

            switch tableColumn!.identifier.rawValue {
            case "name":
                let simString = device.simulator ? "Simulator " : ""
                let connString = device.connected ? "" : "[disconnected]"
                let string = "\(simString)\(device.name) (\(device.osVersion)) \(connString)"
                return string
            case "enabled":
                if let index = self.selectedDeviceIds
                    .indexOfFirstObjectPassingTest(test: { $0 == device.id }) {
                    let enabled = index > -1
                    return enabled
                }
                return false
            default:
                return nil
            }
        }
        return nil
    }

    func editTrigger(_ trigger: TriggerConfig?) {
        self.triggerToEdit = trigger
        self.performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "showTrigger"), sender: nil)
    }

    @IBAction func triggerTableViewEditTapped(_ sender: AnyObject) {
        let index = self.triggersTableView.selectedRow
        let trigger = self.triggers[index]
        self.editTrigger(trigger)
    }

    @IBAction func triggerTableViewDeleteTapped(_ sender: AnyObject) {
        let index = self.triggersTableView.selectedRow
        self.triggers.remove(at: index)
    }

    @IBAction func testDevicesTableViewRowCheckboxTapped(_ sender: AnyObject) {

        //toggle selection in model and reload data

        //get device at index first
        let device = self.testingDevices[self.devicesTableView.selectedRow]

        //see if we are checking or unchecking
        let foundIndex = self.selectedDeviceIds.indexOfFirstObjectPassingTest(test: { $0 == device.id })

        if let foundIndex = foundIndex {
            //found, remove it
            self.selectedDeviceIds.remove(at: foundIndex)
        } else {
            //not found, add it
            self.selectedDeviceIds.append(device.id)
        }
    }
}

extension BuildTemplateViewController: TriggerViewControllerDelegate {

    func triggerViewController(_ triggerViewController: NSViewController, didSaveTrigger trigger: TriggerConfig) {
        var mapped = self.triggers.dictionarifyWithKey { $0.id }
        mapped[trigger.id] = trigger
        self.triggers = Array(mapped.values)
        triggerViewController.dismiss(nil)
    }

    func triggerViewController(_ triggerViewController: NSViewController, didCancelEditingTrigger trigger: TriggerConfig) {
        triggerViewController.dismiss(nil)
    }
}

extension BuildTemplateViewController: SelectTriggerViewControllerDelegate {

    func selectTriggerViewController(_ viewController: SelectTriggerViewController, didSelectTriggers selectedTriggers: [TriggerConfig]) {
        var mapped = self.triggers.dictionarifyWithKey { $0.id }
        mapped = mapped.merging(selectedTriggers.dictionarifyWithKey(key: { $0.id })) { (t1, _) -> TriggerConfig in
            return t1
        }
        self.triggers = Array(mapped.values)
    }
}

extension BuildTemplateViewController {

    private func allSchedules() -> [BotSchedule.Schedule] {
        //scheduled not yet supported, just manual vs commit
        return [
            BotSchedule.Schedule.manual,
            BotSchedule.Schedule.commit
            //TODO: add UI support for proper schedule - hourly/daily/weekly
        ]
    }

    private func allCleaningPolicies() -> [BotConfiguration.CleaningPolicy] {
        return [
            BotConfiguration.CleaningPolicy.never,
            BotConfiguration.CleaningPolicy.always,
            BotConfiguration.CleaningPolicy.once_a_Day,
            BotConfiguration.CleaningPolicy.once_a_Week
        ]
    }

    private static func allDeviceFilters(_ platform: DevicePlatform.PlatformType) -> [DeviceFilter.FilterType] {
        let allFilters = DeviceFilter.FilterType.availableFiltersForPlatform(platform)
        return allFilters
    }
}

extension BuildTemplateViewController: NSTextFieldDelegate {
    override func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField,
            textField == self.nameTextField {
            self.validateAndGenerate()
        }
    }
}
