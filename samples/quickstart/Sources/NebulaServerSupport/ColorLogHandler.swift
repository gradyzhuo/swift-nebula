//
//  ColorLogHandler.swift
//
//
//  Created by Grady Zhuo on 2026/3/31.
//

import Foundation
import Logging

/// A LogHandler that writes colorized output to stdout using ANSI escape codes.
package struct ColorLogHandler: LogHandler {

    package var metadata: Logger.Metadata = [:]
    package var logLevel: Logger.Level = .info

    private let label: String

    package init(label: String) {
        self.label = label
    }

    package subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    package func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let color = level.ansiColor
        let reset = "\u{001B}[0m"
        let bold  = "\u{001B}[1m"
        let dim   = "\u{001B}[2m"

        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let levelTag  = "\(color)\(bold)[\(level.label)]\(reset)"
        let labelTag  = "\(dim)\(label)\(reset)"
        print("\(dim)\(timestamp)\(reset) \(levelTag) \(labelTag): \(color)\(message)\(reset)")
    }
}

// MARK: - Helpers

private extension Logger.Level {
    var ansiColor: String {
        switch self {
        case .trace:    return "\u{001B}[37m"    // white
        case .debug:    return "\u{001B}[36m"    // cyan
        case .info:     return "\u{001B}[32m"    // green
        case .notice:   return "\u{001B}[34m"    // blue
        case .warning:  return "\u{001B}[33m"    // yellow
        case .error:    return "\u{001B}[31m"    // red
        case .critical: return "\u{001B}[1;31m"  // bold red
        }
    }

    var label: String {
        switch self {
        case .trace:    return "TRACE"
        case .debug:    return "DEBUG"
        case .info:     return "INFO"
        case .notice:   return "NOTE"
        case .warning:  return "WARN"
        case .error:    return "ERROR"
        case .critical: return "CRIT"
        }
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
