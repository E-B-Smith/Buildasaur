//
//  BranchWatchingViewController.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 23/05/2015.
//  Copyright (c) 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import AppKit
import BuildaGitServer
import BuildaUtils
import BuildaKit
import ReactiveCocoa
import ReactiveSwift

protocol BranchWatchingViewControllerDelegate: class {
    
    func didUpdateWatchedBranches(_ branches: [String])
}

private struct ShowableBranch {
    let name: String
    let pr: Int?
}

class BranchWatchingViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    
    //these two must be set before viewDidLoad by its presenting view controller
    var syncer: StandardSyncer!
    var watchedBranchNames: Set<String>!
    weak var delegate: BranchWatchingViewControllerDelegate?
    
    fileprivate var branches: [ShowableBranch] = []
    
    @IBOutlet weak var branchActivityIndicator: NSProgressIndicator!
    @IBOutlet weak var branchesTableView: NSTableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        assert(self.syncer != nil, "Syncer has not been set")
        self.watchedBranchNames = Set(self.syncer.config.value.watchedBranchNames)
        
        self.branchesTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        let branches = self.fetchBranchesProducer()
        let prs = self.fetchPRsProducer()
        
        let combined = SignalProducer.combineLatest(branches, prs)
        let showables = combined.on(starting: { [weak self] in
            
            self?.branchActivityIndicator.startAnimation(nil)
            
        }).map { branches, prs -> [ShowableBranch] in
            
            //map branches to PR numbers
            let mappedPRs = prs.dictionarifyWithKey { $0.headName }
            
            return branches.map {
                let pr = mappedPRs[$0.name]?.number
                return ShowableBranch(name: $0.name, pr: pr)
            }
        }
        
        
        showables.start(Signal.Observer(value: { [weak self] (branches) -> () in
            self?.branches = branches
            self?.branchesTableView.reloadData()
        }, failed: { (error) -> () in
                UIUtils.showAlertWithError(error)
        }, completed: { [weak self] () -> () in
            self?.branchActivityIndicator.stopAnimation(nil)
        }, interrupted: nil))
    }
    
    func fetchBranchesProducer() -> SignalProducer<[BranchType], NSError> {
        
        let repoName = self.syncer.project.serviceRepoName()!
        
        return SignalProducer { [weak self] sink, _ in
            guard let sself = self else { return }
            
            sself.syncer.sourceServer.getBranchesOfRepo(repo: repoName) { (branches, error) -> () in
                if let error = error {
                    sink.send(error: error as NSError)
                } else {
                    sink.send(value:branches!)
                    sink.sendCompleted()
                }
            }
            }.observe(on: UIScheduler())
    }
    
    func fetchPRsProducer() -> SignalProducer<[PullRequestType], NSError> {
        
        let repoName = self.syncer.project.serviceRepoName()!
        
        return SignalProducer { [weak self] sink, _ in
            guard let sself = self else { return }
            
            sself.syncer.sourceServer.getOpenPullRequests(repo: repoName) { (prs, error) -> () in
                if let error = error {
                    sink.send(error: error as NSError)
                } else {
                    sink.send(value: prs!)
                    sink.sendCompleted()
                }
            }
        }.observe(on: UIScheduler())
    }
    
    @IBAction func cancelTapped(_ sender: AnyObject) {
        self.dismiss(nil)
    }
    
    @IBAction func doneTapped(_ sender: AnyObject) {
        let updated = Array(self.watchedBranchNames)
        self.delegate?.didUpdateWatchedBranches(updated)
        self.dismiss(nil)
    }
    
    //MARK: branches table view
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        
        if tableView == self.branchesTableView {
            return self.branches.count
        }
        return 0
    }
    
    func getTypeOfReusableView<T: NSView>(_ column: String) -> T {
        guard let view = self.branchesTableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: column), owner: self) else {
            fatalError("Couldn't get a reusable view for column \(column)")
        }
        guard let typedView = view as? T else {
            fatalError("Couldn't type view \(view) into type \(T.className())")
        }
        return typedView
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        guard let tcolumn = tableColumn else { return nil }
        let columnIdentifier = tcolumn.identifier
        
        let branch = self.branches[row]
        
        switch columnIdentifier.rawValue {
            
        case "name":
            let view: NSTextField = self.getTypeOfReusableView(columnIdentifier.rawValue)
            var name = branch.name
            if let pr = branch.pr {
                name += " (watched as PR #\(pr))"
            }
            view.stringValue = name
            return view
        case "enabled":
            let checkbox: BuildaNSButton = self.getTypeOfReusableView(columnIdentifier.rawValue)
            if let _ = branch.pr {
                checkbox.on = true
                checkbox.isEnabled = false
            } else {
                checkbox.on = self.watchedBranchNames.contains(branch.name)
                checkbox.isEnabled = true
            }
            checkbox.row = row
            return checkbox
        default:
            return nil
        }
    }
    
    @IBAction func branchesTableViewRowCheckboxTapped(_ sender: BuildaNSButton) {
        
        //toggle selection in model
        let branch = self.branches[sender.row!]
        let branchName = branch.name
        
        //see if we are checking or unchecking
        let previouslyEnabled = self.watchedBranchNames.contains(branchName)
        
        if previouslyEnabled {
            //disable
            self.watchedBranchNames.remove(branchName)
        } else {
            //enable
            self.watchedBranchNames.insert(branchName)
        }
    }

}
