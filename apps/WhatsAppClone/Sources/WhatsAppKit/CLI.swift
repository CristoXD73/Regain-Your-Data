import Foundation

/// Command-line test modes (`--check`, `--scan` …). Returns when no mode was asked for.
public enum WhatsAppCLI {
    public static func run() throws {

        // `WhatsVault --check <folder>` parses every chat zip and prints counts (no message content).
        if let i = CommandLine.arguments.firstIndex(of: "--check"), i + 1 < CommandLine.arguments.count {
            for file in WhatsAppScanner.chats(under: URL(fileURLWithPath: CommandLine.arguments[i + 1])) {
                let t = Date()
                let c = try WhatsAppScanner.load(file)
                let kinds = Dictionary(grouping: c.messages, by: { "\($0.kind)" }).mapValues(\.count).sorted { $0.value > $1.value }
                print("""
                chat: participants \(c.participants.count), me found: \(!c.me.isEmpty), messages \(c.messages.count), mine \(c.messages.filter(\.mine).count)
                  kinds: \(kinds.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                  attachments with a file: \(c.messages.filter { $0.file != nil }.count); span \(c.messages.first?.time.formatted(date: .abbreviated, time: .omitted) ?? "-") – \(c.messages.last?.time.formatted(date: .abbreviated, time: .omitted) ?? "-"); out of order: \(zip(c.messages, c.messages.dropFirst()).filter { $0.time > $1.time }.count)
                  parsed in \(String(format: "%.2f", Date().timeIntervalSince(t)))s
                """)
            }
            exit(0)
        }
    }
}
