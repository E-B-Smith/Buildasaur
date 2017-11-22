//
//  SlackIntegration.swift
//  BuildaKit
//
//  Created by Sylvain Fay-Chatelard on 21/11/2017.
//  Copyright © 2017 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaUtils

private extension String {
    func reformat(issues: String?) -> String {
        var result = self.replacingOccurrences(of: "**", with: "")
        if let regexLink = try? NSRegularExpression(pattern: "Result of.*\n", options: .caseInsensitive) {
            result = regexLink.stringByReplacingMatches(in: result,
                                                        options: .withTransparentBounds,
                                                        range: NSRange(location: 0, length: result.count),
                                                        withTemplate: "")
        }
        if let issues = issues {
            result = result.replacingOccurrences(of: "---", with: "---\n\(issues)---\n")
        }
        return result.split(separator: "\n").dropLast().joined(separator: "\n")
    }
}

public class SlackNotifier: Notifier {
    private let webhookURL: URL
    private let session: URLSession

    public init(webhookURL: URL) {
        self.webhookURL = webhookURL
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config)
    }

    public func postCommentOnIssue(notification: NotifierNotification, completion: @escaping (_ comment: CommentType?, _ error: Error?) -> Void) {
        let color: String
        switch notification.status.state {
        case .Error, .Failure:
            color = "danger"
        case .NoState, .Pending:
            color = "warning"
        case .Success:
            color = "good"
        }

        guard let link = notification.linksToIntegration?["xcode"],
            let linkToIntegration = URL(string: link),
            let integrationResult = notification.integrationResult else { return }

        var slackNotification: [String: Any] = [:]

        let title: String
        if let issueNumber = notification.issueNumber {
            title = "#\(issueNumber) |-> \(notification.branch) \(integrationResult.capitalized)"
            slackNotification["fallback"] = "[\(notification.repo)] <\(linkToIntegration)|PR #\(issueNumber)> |-> \(notification.branch): \(notification.status.state.rawValue)"
            slackNotification["pretext"] = "[\(notification.repo)] <\(linkToIntegration)|PR #\(issueNumber)> |-> \(notification.branch): \(notification.status.state.rawValue)"
        } else {
            title = "Branch \(notification.branch) \(integrationResult.capitalized)"
            slackNotification["fallback"] = "[\(notification.repo)] |-> <\(linkToIntegration)|\(notification.branch)>: \(notification.status.state.rawValue)"
            slackNotification["pretext"] = "[\(notification.repo)] |-> <\(linkToIntegration)|\(notification.branch)>: \(notification.status.state.rawValue)"
        }
        slackNotification["color"] = color
        slackNotification["mrkdwn_in"] = [ "pretext", "text", "fallback", "fields" ]
        slackNotification["unfurl_links"] = false
        let field: [String: Any] = [
            "title": title,
            "value": notification.comment.reformat(issues: notification.issues),
            "short": false
        ]
        slackNotification["fields"] = [ field ]
        let attachements = [ "attachments": [slackNotification] ]
        let body = try! JSONSerialization.data(withJSONObject: attachements, options: [])
        let urlRequest = NSMutableURLRequest(url: self.webhookURL)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body

        self.session.dataTask(with: urlRequest as URLRequest, completionHandler: { (data, response, error) in
            if let response = response as? HTTPURLResponse,
                let data = data {
                if response.statusCode != 200 {
                    Log.error("SlackIntegration: statusCode=\(response.statusCode) data=\(data)")
                }
            } else {
                Log.error(error!)
            }
        }).resume()
    }
}
