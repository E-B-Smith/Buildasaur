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
import ReactiveCocoa
import ReactiveSwift
import Result

protocol BuildTemplateViewControllerDelegate: class {
    func didCancelEditingOfBuildTemplate(_ template: BuildTemplate)
    func didSaveBuildTemplate(_ template: BuildTemplate)
}

class BuildTemplateViewController: ConfigEditViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    let buildTemplate = MutableProperty<BuildTemplate>(BuildTemplate())
    weak var delegate: BuildTemplateViewControllerDelegate?
    var projectRef: RefType!
    var xcodeServerRef: RefType!
    
    // ---
    
    fileprivate var project = MutableProperty<Project!>(nil)
    fileprivate var xcodeServer = MutableProperty<XcodeServer!>(nil)
    
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
    
    fileprivate let isDevicesUpToDate = MutableProperty<Bool>(true)
    fileprivate let isPlatformsUpToDate = MutableProperty<Bool>(true)
    fileprivate let isDeviceFiltersUpToDate = MutableProperty<Bool>(true)
    
    fileprivate let testingDevices = MutableProperty<[Device]>([])
    fileprivate let schemes = MutableProperty<[XcodeScheme]>([])
    fileprivate let schedules = MutableProperty<[BotSchedule.Schedule]>([])
    fileprivate let cleaningPolicies = MutableProperty<[BotConfiguration.CleaningPolicy]>([])
    fileprivate var deviceFilters = MutableProperty<[DeviceFilter.FilterType]>([])
    
    fileprivate var selectedScheme: MutableProperty<String>!
    fileprivate var platformType: SignalProducer<DevicePlatform.PlatformType, NoError>!
    fileprivate let cleaningPolicy = MutableProperty<BotConfiguration.CleaningPolicy>(.never)
    fileprivate let deviceFilter = MutableProperty<DeviceFilter.FilterType>(.selectedDevicesAndSimulators)
    fileprivate let selectedSchedule = MutableProperty<BotSchedule>(BotSchedule.manualBotSchedule())
    fileprivate let selectedDeviceIds = MutableProperty<[String]>([])
    fileprivate let triggers = MutableProperty<[TriggerConfig]>([])
    
    fileprivate let isValid = MutableProperty<Bool>(false)
    fileprivate var generatedTemplate: MutableProperty<BuildTemplate>!
    
    fileprivate var triggerToEdit: TriggerConfig?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupBindings()
    }
    
    fileprivate func setupBindings() {
        
        //request project and server for specific refs from the syncer manager
        self.syncerManager
            .projectWithRef(ref: self.projectRef)
            .startWithValues { [weak self] in
                self?.project.value = $0
        }
        self.syncerManager
            .xcodeServerWithRef(ref: self.xcodeServerRef)
            .startWithValues { [weak self] in
                self?.xcodeServer.value = $0
        }
        
        self.project.producer.startWithValues { [weak self] in
            self?.schemes.value = $0.schemes().sorted { $0.name < $1.name }
        }
        
        self.triggers.producer.startWithValues { [weak self] _ in
            self?.triggersTableView.reloadData()
        }
        
        //ui
        self.testDevicesActivityIndicator.rac_animating <~ self.isDevicesUpToDate.producer.map { !$0 }
        let devicesTableViewChangeSources = SignalProducer.combineLatest(self.testingDevices.producer, self.selectedDeviceIds.producer)
        devicesTableViewChangeSources.startWithValues { [weak self] _ -> () in
            self?.devicesTableView.reloadData()
        }
        
        let buildTemplate = self.buildTemplate.value
        self.selectedScheme = MutableProperty<String>(buildTemplate.scheme)
        
        self.automaticallyRegisterDevices.rac_enabled <~ self.allowServerToManageCertificate.rac_on
        self.automaticallyRegisterDevices.isEnabled = false

        self.selectedScheme.producer
            .startWithValues { [weak self] _ in
                self?.isDeviceFiltersUpToDate.value = false
                self?.isDevicesUpToDate.value = false
                self?.isPlatformsUpToDate.value = false
        }
        
        self.platformType = self.selectedScheme
            .producer
            .observe(on: QueueScheduler())
            .flatMap(.latest) { [weak self] schemeName in
                return self?.devicePlatformFromScheme(schemeName) ?? SignalProducer<DevicePlatform.PlatformType, NoError>.never
            }.observe(on: UIScheduler())
            .on(starting: nil, started: nil, event: nil, failed: nil, completed: nil, interrupted: nil, terminated: nil, disposed: nil, value: { [weak self] _ in
                Log.verbose("Finished fetching platform")
                self?.isPlatformsUpToDate.value = true
            })

        self.platformType.startWithValues { [weak self] platform in
            //refetch/refilter devices
            
            self?.isDevicesUpToDate.value = false
            self?.fetchDevices(platform) { () -> () in
                Log.verbose("Finished fetching devices")
                self?.isDevicesUpToDate.value = true
            }
        }

        self.setupSchemes()
        self.setupSchedules()
        self.setupCleaningPolicies()
        self.setupDeviceFilter()

        let nextAllowed = SignalProducer.combineLatest(
            self.isValid.producer,
            self.isDevicesUpToDate.producer,
            self.isPlatformsUpToDate.producer,
            self.isDeviceFiltersUpToDate.producer
        ).map {
            $0 && $1 && $2 && $3
        }
        self.nextAllowed <~ nextAllowed
        
        self.devicesTableView.rac_enabled <~ self.deviceFilter.producer.map {
            filter in
            return filter == .selectedDevicesAndSimulators
        }
        
        //initial dump
        self.buildTemplate
            .producer
            .startWithValues {
            [weak self] (buildTemplate: BuildTemplate) -> () in
            
            guard let sself = self else { return }
            sself.nameTextField.stringValue = buildTemplate.name
            
            sself.selectedScheme.value = buildTemplate.scheme
            if sself.schemesPopup.doesContain(buildTemplate.scheme) {
                sself.schemesPopup.selectItem(withTitle: buildTemplate.scheme)
            } else {
                sself.schemesPopup.selectItem(at: 0)
            }
            let index = sself.schemesPopup.indexOfSelectedItem
            let schemes = sself.schemes.value
            let scheme = schemes[index]
            sself.selectedScheme.value = scheme.name
            
            sself.analyzeButton.on = buildTemplate.shouldAnalyze
            sself.testButton.on = buildTemplate.shouldTest
            sself.archiveButton.on = buildTemplate.shouldArchive
                
            sself.allowServerToManageCertificate.on = buildTemplate.manageCertsAndProfiles
            sself.automaticallyRegisterDevices.on = buildTemplate.addMissingDevicesToTeams
            
            let schedule = buildTemplate.schedule
            let scheduleIndex = sself.schedules.value.index(of: schedule.schedule)
            sself.schedulePopup.selectItem(at: scheduleIndex ?? 0)
            sself.selectedSchedule.value = schedule
            
            let cleaningPolicyIndex = sself.cleaningPolicies.value.index(of: buildTemplate.cleaningPolicy)
            sself.cleaningPolicyPopup.selectItem(at: cleaningPolicyIndex ?? 0)
            sself.deviceFilter.value = buildTemplate.deviceFilter
            sself.selectedDeviceIds.value = buildTemplate.testingDeviceIds
            
            sself.triggers.value = sself.storageManager.triggerConfigsForIds(ids: buildTemplate.triggers)
        }
        
        let notTesting = self.testButton.rac_on.map { !$0 }
        self.deviceFilterStackItem.rac_hidden <~ notTesting
        self.testDevicesStackItem.rac_hidden <~ notTesting
        
        //when we switch to not-testing, clean up the device filter and testing device ids
        notTesting.startWithValues { [weak self] in
            if $0 {
                self?.selectedDeviceIds.value = []
                self?.deviceFilter.value = .allAvailableDevicesAndSimulators
                self?.deviceFilterPopup.selectItem(at: DeviceFilter.FilterType.allAvailableDevicesAndSimulators.rawValue)
            }
        }
        
        //this must be ran AFTER the initial dump (runs synchronously), othwerise
        //the callback for name text field doesn't contain the right value.
        //the RAC text signal doesn't fire on code-trigger text changes :(
        self.setupGeneratedTemplate()
    }
    
    fileprivate func devicePlatformFromScheme(_ schemeName: String) -> SignalProducer<DevicePlatform.PlatformType, NoError> {
        return SignalProducer { [weak self] sink, _ in
            guard let sself = self else { return }
            guard let scheme = sself.schemes.value.filter({ $0.name == schemeName }).first else {
                return
            }
            
            do {
                let platformType = try XcodeDeviceParser.parseDeviceTypeFromProjectUrlAndScheme(projectUrl: sself.project.value.url, scheme: scheme).toPlatformType()
                sink.send(value: platformType)
                sink.sendCompleted()
            } catch {
                UIUtils.showAlertWithError(error)
            }
        }
    }
    
    fileprivate func setupSchemes() {
        
        //data source
        let schemeNames = self.schemes.producer
            .map { $0.map { $0.name } }
        schemeNames.startWithValues { [weak self] in
            self?.schemesPopup.replaceItems($0)
        }
        
        //action
        let handler = SignalProducer<AnyObject, NoError> { [weak self] sink, _ in
            if let sself = self {
                let index = sself.schemesPopup.indexOfSelectedItem
                let schemes = sself.schemes.value
                let scheme = schemes[index]
                sself.selectedScheme.value = scheme.name
            }
            sink.sendCompleted()
        }
        let action = Action { (_: ()) in handler }
        self.schemesPopup.reactive.pressed = CocoaAction(action)
    }
    
    fileprivate func setupSchedules() {
        
        self.schedules.value = self.allSchedules()
        let scheduleNames = self.schedules
            .producer
            .map { $0.map { $0.toString() } }
        scheduleNames.startWithValues { [weak self] in
            self?.schedulePopup.replaceItems($0)
        }
        
        //action
        let handler = SignalProducer<AnyObject, NoError> { [weak self] sink, _ in
            if let sself = self {
                let index = sself.schedulePopup.indexOfSelectedItem
                let schedules = sself.schedules.value
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
                
                sself.selectedSchedule.value = schedule
            }
            sink.sendCompleted()
        }
        let action = Action { (_: ()) in handler }
        self.schedulePopup.reactive.pressed = CocoaAction(action)
    }
    
    fileprivate func setupCleaningPolicies() {
        
        //data source
        self.cleaningPolicies.value = self.allCleaningPolicies()
        let cleaningPolicyNames = self.cleaningPolicies
            .producer
            .map { $0.map { $0.toString() } }
        cleaningPolicyNames.startWithValues { [weak self] in
            self?.cleaningPolicyPopup.replaceItems($0)
        }
        
        //action
        let handler = SignalProducer<AnyObject, NoError> { [weak self] sink, _ in
            if let sself = self {
                let index = sself.cleaningPolicyPopup.indexOfSelectedItem
                let policies = sself.cleaningPolicies.value
                let policy = policies[index]
                sself.cleaningPolicy.value = policy
            }
            sink.sendCompleted()
        }
        let action = Action { (_: ()) in handler }
        self.cleaningPolicyPopup.reactive.pressed = CocoaAction(action)
    }
    
    fileprivate func setupDeviceFilter() {
        
        //data source
        self.deviceFilters <~ self.platformType.map {
            BuildTemplateViewController.allDeviceFilters($0)
        }
        let filterNames = self.deviceFilters
            .producer
            .map { $0.map { $0.toString() } }
        filterNames.startWithValues { [weak self] in
            self?.deviceFilterPopup.replaceItems($0)
        }
        
        self.deviceFilters.producer.startWithValues { [weak self] in
            
            //ensure that when the device filters change that we
            //make sure our selected one is still valid
            guard let sself = self else { return }
            
            sself.isDeviceFiltersUpToDate.value = false

            if $0.index(of: sself.deviceFilter.value) == nil {
                sself.deviceFilter.value = .allAvailableDevicesAndSimulators
            }
            
            //also ensure that the selected filter is in fact visually selected
            let deviceFilterIndex = $0.index(of: sself.deviceFilter.value)
            sself.deviceFilterPopup.selectItem(at: deviceFilterIndex ?? DeviceFilter.FilterType.allAvailableDevicesAndSimulators.rawValue)
            
            Log.verbose("Finished fetching devices")
            sself.isDeviceFiltersUpToDate.value = true
        }
        
        self.deviceFilter.producer.startWithValues { [weak self] in
            if $0 != .selectedDevicesAndSimulators {
                self?.selectedDeviceIds.value = []
            }
        }
        
        //action
        let handler = SignalProducer<AnyObject, NoError> { [weak self] sink, _ in
            if let sself = self {
                let index = sself.deviceFilterPopup.indexOfSelectedItem
                let filters = sself.deviceFilters.value
                let filter = filters[index]
                sself.deviceFilter.value = filter
            }
            sink.sendCompleted()
        }
        let action = Action { (_: ()) in handler }
        self.deviceFilterPopup.reactive.pressed = CocoaAction(action)
    }
    
    fileprivate func setupGeneratedTemplate() {
        
        //sources
        let name = self.nameTextField.rac_text
        let scheme = self.selectedScheme.producer
        let platformType = self.platformType!
        let analyze = self.analyzeButton.rac_on
        let test = self.testButton.rac_on
        let archive = self.archiveButton.rac_on
        let allowServerToManageCertificate = self.allowServerToManageCertificate.rac_on
        let automaticallyRegisterDevices = self.automaticallyRegisterDevices.rac_on
        let schedule = self.selectedSchedule.producer
        let cleaningPolicy = self.cleaningPolicy.producer
        let triggers = self.triggers.producer
        let deviceFilter = self.deviceFilter.producer
        let deviceIds = self.selectedDeviceIds.producer
        
        let original = self.buildTemplate.producer
        let combined = combineLatest(original, name, scheme, platformType, analyze, test, archive, allowServerToManageCertificate, automaticallyRegisterDevices, schedule, cleaningPolicy, triggers, deviceFilter, deviceIds)
        
        let validated = combined.map { [weak self]
            original, name, scheme, platformType, analyze, test, archive, allowServerToManageCertificate, automaticallyRegisterDevices, schedule, cleaningPolicy, triggers, deviceFilter, deviceIds -> Bool in
            
            guard let sself = self else { return false }
            
            //make sure the name isn't empty
            if name.isEmpty {
                return false
            }
            
            //make sure the selected scheme is valid
            if sself.schemes.value.filter({ $0.name == scheme }).count == 0 {
                return false
            }
            
            //at least one of the three actions has to be selected
            if !analyze && !test && !archive {
                return false
            }
            
            return true
        }
        
        self.isValid <~ validated
        
        let generated = combined.forwardIf(condition: validated).map { [weak self]
            original, name, scheme, platformType, analyze, test, archive, allowServerToManageCertificate, automaticallyRegisterDevices, schedule, cleaningPolicy, triggers, deviceFilter, deviceIds -> BuildTemplate in
            
            var mod = original
            mod.projectName = self?.project.value.config.value.name
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
            
            return mod
        }
        
        self.generatedTemplate = MutableProperty<BuildTemplate>(self.buildTemplate.value)
        self.generatedTemplate <~ generated
    }
    
    func fetchDevices(_ platform: DevicePlatform.PlatformType, completion: @escaping () -> ()) {
        
        SignalProducer<[Device], NSError> { [weak self] sink, _ in
            guard let sself = self else { return }
            
            sself.xcodeServer.value.getDevices { (devices, error) -> () in
                if let error = error {
                    sink.send(error: error as NSError)
                } else {
                    sink.send(value: devices!)
                }
                sink.sendCompleted()
            }
            }
            .observe(on: UIScheduler())
            .start(Signal.Observer(
                value: { [weak self] (devices) -> () in
                    let processed = BuildTemplateViewController
                        .processReceivedDevices(devices, platform: platform)
                    self?.testingDevices.value = processed
                }, failed: { UIUtils.showAlertWithError($0) },
                   completed: completion))
    }
    
    fileprivate static func processReceivedDevices(_ devices: [Device], platform: DevicePlatform.PlatformType) -> [Device] {
        
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
            
            let triggerToEdit = self.triggerToEdit ?? TriggerConfig()
            triggerViewController.triggerConfig.value = triggerToEdit
            triggerViewController.storageManager = self.storageManager
            triggerViewController.delegate = self
            self.triggerToEdit = nil
        }
        else if let selectTriggerViewController = destinationController as? SelectTriggerViewController {
            
            selectTriggerViewController.storageManager = self.storageManager
            selectTriggerViewController.delegate = self
        }
        
        super.prepare(for: segue, sender: sender)
    }

    @IBAction func addTriggerButtonClicked(_ sender: AnyObject) {
        let buttons = ["Add new", "Add existing", "Cancel"]
        UIUtils.showAlertWithButtons("Would you like to add a new trigger or add existing one?", buttons: buttons, style: .informational, completion: { (tappedButton) -> () in
            switch (tappedButton) {
            case "Add new":
                self.editTrigger(nil)
            case "Add existing":
                self.performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "selectTriggers"), sender: nil)
            default: break
            }
        })
    }
    
    override func shouldGoNext() -> Bool {
        
        guard self.isValid.value else { return false }
        
        let newBuildTemplate = self.generatedTemplate.value
        self.buildTemplate.value = newBuildTemplate
        self.storageManager.addBuildTemplate(buildTemplate: newBuildTemplate)
        self.delegate?.didSaveBuildTemplate(newBuildTemplate)
        
        return true
    }
    
    override func delete() {
        
        UIUtils.showAlertAskingForRemoval("Are you sure you want to delete this Build Template?", completion: { (remove) -> () in
            if remove {
                let template = self.generatedTemplate.value
                self.storageManager.removeBuildTemplate(buildTemplate: template)
                self.delegate?.didCancelEditingOfBuildTemplate(template)
            }
        })
    }
    
    //MARK: triggers table view
    func numberOfRows(in tableView: NSTableView) -> Int {
        
        if tableView == self.triggersTableView {
            return self.triggers.value.count
        } else if tableView == self.devicesTableView {
            return self.testingDevices.value.count
        }
        return 0
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if tableView == self.triggersTableView {
            let triggers = self.triggers.value
            if tableColumn!.identifier.rawValue == "names" {
                
                let trigger = triggers[row]
                return trigger.name
            }
        } else if tableView == self.devicesTableView {
            
            let device = self.testingDevices.value[row]
            
            switch tableColumn!.identifier.rawValue {
            case "name":
                let simString = device.simulator ? "Simulator " : ""
                let connString = device.connected ? "" : "[disconnected]"
                let string = "\(simString)\(device.name) (\(device.osVersion)) \(connString)"
                return string
            case "enabled":
                if let index = self.selectedDeviceIds.value
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
        let trigger = self.triggers.value[index]
        self.editTrigger(trigger)
    }
    
    @IBAction func triggerTableViewDeleteTapped(_ sender: AnyObject) {
        let index = self.triggersTableView.selectedRow
        self.triggers.value.remove(at: index)
    }
    
    @IBAction func testDevicesTableViewRowCheckboxTapped(_ sender: AnyObject) {
        
        //toggle selection in model and reload data
        
        //get device at index first
        let device = self.testingDevices.value[self.devicesTableView.selectedRow]
        
        //see if we are checking or unchecking
        let foundIndex = self.selectedDeviceIds.value.indexOfFirstObjectPassingTest(test: { $0 == device.id })
        
        if let foundIndex = foundIndex {
            //found, remove it
            self.selectedDeviceIds.value.remove(at: foundIndex)
        } else {
            //not found, add it
            self.selectedDeviceIds.value.append(device.id)
        }
    }
}

extension BuildTemplateViewController: TriggerViewControllerDelegate {
    
    func triggerViewController(_ triggerViewController: NSViewController, didSaveTrigger trigger: TriggerConfig) {
        var mapped = self.triggers.value.dictionarifyWithKey { $0.id }
        mapped[trigger.id] = trigger
        self.triggers.value = Array(mapped.values)
        triggerViewController.dismiss(nil)
    }
    
    func triggerViewController(_ triggerViewController: NSViewController, didCancelEditingTrigger trigger: TriggerConfig) {
        triggerViewController.dismiss(nil)
    }
}

extension BuildTemplateViewController: SelectTriggerViewControllerDelegate {
    
    func selectTriggerViewController(_ viewController: SelectTriggerViewController, didSelectTriggers selectedTriggers: [TriggerConfig]) {
        var mapped = self.triggers.value.dictionarifyWithKey { $0.id }
        //mapped.merging(selectedTriggers.dictionarifyWithKey(key: { $0.id }))
        self.triggers.value = Array(mapped.values)
    }
}

extension BuildTemplateViewController {
    
    fileprivate func allSchedules() -> [BotSchedule.Schedule] {
        //scheduled not yet supported, just manual vs commit
        return [
            BotSchedule.Schedule.manual,
            BotSchedule.Schedule.commit
            //TODO: add UI support for proper schedule - hourly/daily/weekly
        ]
    }
    
    fileprivate func allCleaningPolicies() -> [BotConfiguration.CleaningPolicy] {
        return [
            BotConfiguration.CleaningPolicy.never,
            BotConfiguration.CleaningPolicy.always,
            BotConfiguration.CleaningPolicy.once_a_Day,
            BotConfiguration.CleaningPolicy.once_a_Week
        ]
    }
    
    fileprivate static func allDeviceFilters(_ platform: DevicePlatform.PlatformType) -> [DeviceFilter.FilterType] {
        let allFilters = DeviceFilter.FilterType.availableFiltersForPlatform(platform)
        return allFilters
    }
}
