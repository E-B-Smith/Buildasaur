//
//  SlackIntegration.swift
//  BuildaKit
//
//  Created by Sylvain Fay-Chatelard on 21/11/2017.
//  Copyright © 2017 Honza Dvorsky. All rights reserved.
//

import Foundation
import BuildaGitServer
import BuildaUtils
import XcodeServerSDK

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
class SlackIntegration {
    private let webhook: String
    private let session: URLSession

    init(webhook: String) {
        self.webhook = webhook
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config)
    }

    func postCommentOnIssue(statusWithComment: StatusAndComment, repo: String, branch: String, prNumber: Int?, issues: String?) {
        let color: String
        switch statusWithComment.status.state {
        case .Error, .Failure:
            color = "danger"
        case .NoState, .Pending:
            color = "warning"
        case .Success:
            color = "good"
        }

        guard let integration = statusWithComment.integration,
                let links = statusWithComment.links else { return }

        var notification: [String: Any] = [:]

        let linkToIntegration = links["xcode"]!

        let title: String
        if let prNumber = prNumber {
            title = "#\(prNumber) |-> \(branch) \(integration.result!.rawValue.capitalized)"
            notification["fallback"] = "[\(repo)] <\(linkToIntegration)|PR #\(prNumber)> |-> \(branch): \(statusWithComment.status.state.rawValue)"
            notification["pretext"] = "[\(repo)] <\(linkToIntegration)|PR #\(prNumber)> |-> \(branch): \(statusWithComment.status.state.rawValue)"
        } else {
            title = "Branch \(branch) \(integration.result!.rawValue.capitalized)"
            notification["fallback"] = "[\(repo)] |-> <\(linkToIntegration)|\(branch)>: \(statusWithComment.status.state.rawValue)"
            notification["pretext"] = "[\(repo)] |-> <\(linkToIntegration)|\(branch)>: \(statusWithComment.status.state.rawValue)"
        }
        notification["color"] = color
        notification["mrkdwn_in"] = [ "pretext", "text", "fallback", "fields" ]
        notification["unfurl_links"] = false
        let field: [String: Any] = [
            "title": title,
            "value": statusWithComment.comment?.reformat(issues: issues) ?? "",
            "short": false
        ]
        notification["fields"] = [ field ]
        let attachements = [ "attachments": [notification] ]
        let body = try! JSONSerialization.data(withJSONObject: attachements, options: [])
        let urlRequest = NSMutableURLRequest(url: URL(string: self.webhook)!)
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
