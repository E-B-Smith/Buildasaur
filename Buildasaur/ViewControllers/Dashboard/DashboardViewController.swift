//
//  DashboardViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 28/09/2015.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Cocoa
import BuildaKit

protocol EditeeDelegate: EmptyXcodeServerViewControllerDelegate, XcodeServerViewControllerDelegate, EmptyProjectViewControllerDelegate, ProjectViewControllerDelegate, EmptyBuildTemplateViewControllerDelegate, BuildTemplateViewControllerDelegate, SyncerViewControllerDelegate { }

class DashboardViewController: PresentableViewController {

    @IBOutlet weak var syncersTableView: NSTableView!
    @IBOutlet weak var startAllButton: NSButton!
    @IBOutlet weak var stopAllButton: NSButton!
    @IBOutlet weak var autostartButton: NSButton!
    @IBOutlet weak var launchOnLoginButton: NSButton!

    private(set) var config: [String: AnyObject] = [:] {
        didSet {
            self.syncerManager.storageManager.config = config
        }
    }

    //injected before viewDidLoad
    var syncerManager: SyncerManager! {
        didSet {
            // Something is wrong here, the list doesn't show up
            let present: SyncerViewModel.PresentEditViewControllerType = {
                self.showSyncerEditViewControllerWithTriplet($0.toEditable(), state: .syncer)
            }
            let update: ([StandardSyncer]) -> Void = { [weak self] syncers in
                guard let sself = self else { return }
                sself.syncerViewModels = syncers
                    .map { SyncerViewModel(syncer: $0, presentEditViewController: present) }
                    .sorted { (o1, o2) in o1.initialProjectName < o2.initialProjectName }
            }
            self.syncerManager.onSyncersChange = update
            update(self.syncerManager.syncers)
        }
    }
    var serviceAuthenticator: ServiceAuthenticator!

    private var syncerViewModels: [SyncerViewModel] = [] {
        didSet {
            self.updateSyncerViewModels()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.configTitle()
        self.configTableView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        self.configHeaderView()

        if let window = self.view.window {
            window.minSize = CGSize(width: 700, height: 300)
        }
    }

    private func configTitle() {
        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
        self.title = "Buildasaur \(version), at your service!"
    }

    private func configHeaderView() {
        //setup config
        self.config = self.syncerManager.storageManager.config
        self.autostartButton.on = self.config["autostart"] as? Bool ?? false

        self.autostartButton.onClick = { [weak self] sender in
            if let sender = sender as? NSButton {
                self?.config["autostart"] = sender.on as AnyObject
            }
        }

        //setup login item
        self.launchOnLoginButton.on = self.syncerManager.loginItem.isLaunchItem
    }

    private func configTableView() {
        let tableView = self.syncersTableView
        tableView?.dataSource = self
        tableView?.delegate = self
        tableView?.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    }

    private func updateSyncerViewModels() {
        //startAll is enabled if >0 is NOT ACTIVE
        let startAllEnabled = !self.syncerViewModels.filter { !$0.syncer.active }.isEmpty
        self.startAllButton.isEnabled = startAllEnabled

        //stopAll is enabled if >0 is ACTIVE
        let stopAllEnabled = !self.syncerViewModels.filter { $0.syncer.active }.isEmpty
        self.stopAllButton.isEnabled = stopAllEnabled

        self.syncersTableView.reloadData()
    }

    // MARK: Responding to button inside of cells

    private func syncerViewModelFromSender(_ sender: BuildaNSButton) -> SyncerViewModel {
        let selectedRow = sender.row!
        let syncerViewModel = self.syncerViewModels[selectedRow]
        return syncerViewModel
    }

    @IBAction func startAllButtonClicked(_ sender: AnyObject) {
        self.syncerViewModels.forEach { $0.startButtonClicked() }
        self.updateSyncerViewModels()
    }

    @IBAction func stopAllButtonClicked(_ sender: AnyObject) {
        self.syncerViewModels.forEach { $0.stopButtonClicked() }
        self.updateSyncerViewModels()
    }

    @IBAction func newSyncerButtonClicked(_ sender: AnyObject) {
        self.showNewSyncerViewController()
    }

    @IBAction func editButtonClicked(_ sender: BuildaNSButton) {
        self.syncerViewModelFromSender(sender).viewButtonClicked()
        self.updateSyncerViewModels()
    }

    @IBAction func controlButtonClicked(_ sender: BuildaNSButton) {
        self.syncerViewModelFromSender(sender).controlButtonClicked()
        self.updateSyncerViewModels()
    }

    @IBAction func doubleClickedRow(_ sender: AnyObject?) {
        let clickedRow = self.syncersTableView.clickedRow
        guard clickedRow >= 0 else { return }

        let syncerViewModel = self.syncerViewModels[clickedRow]
        syncerViewModel.viewButtonClicked()
    }

    @IBAction func infoButtonClicked(_ sender: AnyObject) {
        openLink("https://github.com/czechboy0/Buildasaur#buildasaur")
    }

    @IBAction func launchOnLoginClicked(_ sender: NSButton) {
        let newValue = sender.on
        let loginItem = self.syncerManager.loginItem
        loginItem.isLaunchItem = newValue

        //to be in sync in the UI, in case setting fails
        self.launchOnLoginButton.on = loginItem.isLaunchItem
    }

    @IBAction func checkForUpdatesClicked(_ sender: NSButton) {
        (NSApp.delegate as! AppDelegate).checkForUpdates(sender)
    }
}

extension DashboardViewController {
    func showNewSyncerViewController() {
        //configure an editing window with a brand new syncer
        let triplet = self.syncerManager.factory.newEditableTriplet()

//        //Debugging hack - insert the first server and project we have
//        triplet.server = self.syncerManager.storageManager.serverConfigs.value.first!.1
//        triplet.project = self.syncerManager.storageManager.projectConfigs.value["E94BAED5-7D91-426A-B6B6-5C39BF1F7032"]!
//        triplet.buildTemplate = self.syncerManager.storageManager.buildTemplates.value["EB0C3E74-C303-4C33-AF0E-012B650D2E9F"]

        self.showSyncerEditViewControllerWithTriplet(triplet, state: .noServer)
    }

    func showSyncerEditViewControllerWithTriplet(_ triplet: EditableConfigTriplet, state: EditorState) {
        let uniqueIdentifier = triplet.syncer.id
        let viewController: MainEditorViewController = self.storyboardLoader.presentableViewControllerWithStoryboardIdentifier("editorViewController", uniqueIdentifier: uniqueIdentifier, delegate: self.presentingDelegate)

        var context = EditorContext()
        context.configTriplet = triplet
        context.syncerManager = self.syncerManager
        viewController.factory = EditorViewControllerFactory(storyboardLoader: self.storyboardLoader, serviceAuthenticator: self.serviceAuthenticator)
        context.editeeDelegate = viewController
        viewController.context = context
        self.presentingDelegate?.presentViewControllerInUniqueWindow(viewController)

        viewController.loadInState(state)
    }
}

extension DashboardViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.syncerViewModels.count
    }

    enum Column: String {
        case Status = "status"
        case XCSHost = "xcs_host"
        case ProjectName = "project_name"
        case BuildTemplate = "build_template"
        case Control = "control"
        case Edit = "edit"
    }

    func getTypeOfReusableView<T: NSView>(_ column: Column) -> T {
        guard let view = self.syncersTableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: column.rawValue), owner: self) else {
            fatalError("Couldn't get a reusable view for column \(column)")
        }
        guard let typedView = view as? T else {
            fatalError("Couldn't type view \(view) into type \(T.className())")
        }
        return typedView
    }

    func bindTextView(_ view: NSTableCellView, column: Column, viewModel: SyncerViewModel) {
        switch column {
        case .Status:
            view.textField!.stringValue = viewModel.status
            viewModel.onStatusChanged = { status in
                view.textField!.stringValue = status
            }
        case .XCSHost:
            view.textField!.stringValue = viewModel.host
            viewModel.onHostChanged = { host in
                view.textField!.stringValue = host
            }
        case .ProjectName:
            view.textField!.stringValue = viewModel.projectName
            viewModel.onProjectNameChanged = { projectName in
                view.textField!.stringValue = projectName
            }
        case .BuildTemplate:
            view.textField!.stringValue = viewModel.buildTemplateName
            viewModel.onBuildTemplateNameChanged = { buildTemplateName in
                view.textField!.stringValue = buildTemplateName
            }
        default: break
        }
    }

    func bindButtonView(_ view: BuildaNSButton, column: Column, viewModel: SyncerViewModel) {
        switch column {
        case .Edit:
            view.title = viewModel.editButtonTitle
            viewModel.onEditButtonTitleChanged = { title in
                view.title = title
            }
            view.isEnabled = viewModel.editButtonEnabled
            viewModel.onEditButtonEnabledChanged = { enabled in
                view.isEnabled = enabled
            }
        case .Control:
            view.title = viewModel.controlButtonTitle
            viewModel.onControlButtonTitleChanged = { title in
                view.title = title
            }
        default: break
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tcolumn = tableColumn else { return nil }
        let columnIdentifier = tcolumn.identifier
        guard let column = Column(rawValue: columnIdentifier.rawValue) else { return nil }
        let syncerViewModel = self.syncerViewModels[row]

        //based on the column decide which reuse identifier we'll use
        switch column {
        case .Status, .XCSHost, .ProjectName, .BuildTemplate:
            //basic text view
            let view: NSTableCellView = self.getTypeOfReusableView(column)
            self.bindTextView(view, column: column, viewModel: syncerViewModel)
            return view

        case .Control, .Edit:
            //push button
            let view: BuildaNSButton = self.getTypeOfReusableView(column)
            self.bindButtonView(view, column: column, viewModel: syncerViewModel)
            view.row = row
            return view
        }
    }
}

extension DashboardViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 30
    }
}

class BuildaNSButton: NSButton {
    var row: Int?
}
