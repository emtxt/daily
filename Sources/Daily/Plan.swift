import Foundation

struct DailyError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

struct Plan {
    static func title(for date: Date) -> String {
        date.formatted(.verbatim(
            "\(weekday: .wide), \(day: .defaultDigits) \(month: .wide) \(year: .padded(4))",
            locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: Calendar(identifier: .gregorian)
        ))
    }

    static func hasDraftContent(_ source: String, generatedTitle: String) -> Bool {
        let content = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return !content.isEmpty && content != generatedTitle
    }

    struct Event {
        let text: String
        let time: Time
        let lineNumber: Int
    }

    struct Todo {
        let text: String
        let lineNumber: Int
        let isHighPriority: Bool
    }

    struct Time {
        static let minutesPerDay = 24 * 60

        let start: Int
        let end: Int?

        var endOnPage: Int {
            min(end ?? start, Self.minutesPerDay)
        }

        var label: String {
            label(rangeSeparator: "-")
        }

        func label(rangeSeparator: String) -> String {
            let startLabel = Self.label(for: start)
            guard let end else { return startLabel }
            let clockEnd = end > Self.minutesPerDay ? end % Self.minutesPerDay : end
            return "\(startLabel)\(rangeSeparator)\(Self.label(for: clockEnd))"
        }

        static func label(for minutes: Int) -> String {
            String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
    }

    private(set) var title = ""
    private(set) var events: [Event] = []
    private(set) var todos: [Todo] = []
    private var remainingLines: [String] = []

    var isEmpty: Bool { events.isEmpty && todos.isEmpty }

    init(_ source: String) {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                remainingLines.append(String(rawLine))
                continue
            }
            if title.isEmpty {
                title = line
                continue
            }

            if line.hasPrefix("-") || line.hasPrefix("*") {
                let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if text.isEmpty {
                    remainingLines.append(String(rawLine))
                } else {
                    todos.append(Todo(text: text, lineNumber: lineNumber, isHighPriority: line.hasPrefix("*")))
                }
            } else if let event = Self.parseEvent(line, lineNumber: lineNumber) {
                events.append(event)
            } else {
                remainingLines.append(String(rawLine))
            }
        }

        events.sort { $0.time.start < $1.time.start }
    }

    var formattedSource: String {
        let eventLines = events.map { event in
            "\(event.time.label(rangeSeparator: " - ")) \(Self.capitalizingFirstLetter(of: event.text))"
        }
        let orderedTodos = todos.filter(\.isHighPriority) + todos.filter { !$0.isHighPriority }
        let todoLines = orderedTodos.map { todo in
            let marker = todo.isHighPriority ? "*" : "-"
            return "\(marker) \(Self.capitalizingFirstLetter(of: todo.text))"
        }
        let scheduleHeading = "# Schedule"
        let todoHeading = "# To-dos"
        let scheduleSection = eventLines.isEmpty ? [] : [scheduleHeading] + eventLines
        let todoSection = todoLines.isEmpty ? [] : [todoHeading] + todoLines
        let otherLines = remainingLines.filter { line in
            switch line.trimmingCharacters(in: .whitespaces) {
            case scheduleHeading: eventLines.isEmpty
            case todoHeading: todoLines.isEmpty
            default: true
            }
        }
        let titleLines = title.isEmpty ? [] : [title]
        let sections = [titleLines, scheduleSection, todoSection, otherLines].filter { !$0.isEmpty }
        guard !sections.isEmpty else { return "" }
        return sections
            .map { $0.joined(separator: "\n") }
            .joined(separator: "\n\n") + "\n"
    }

    private static func capitalizingFirstLetter(of text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        return text[..<index] + text[index].uppercased() + text[text.index(after: index)...]
    }

    private static func parseEvent(_ line: String, lineNumber: Int) -> Event? {
        let pattern = #/
            (?<start>[0-9]{1,2}:[0-9]{2}|[0-9]{1,4})
            (?:
                [\x20\t]*
                (?:
                    [-–][\x20\t]*(?<end>[0-9]{1,2}:[0-9]{2}|[0-9]{1,4})
                  | \+[\x20\t]*(?<duration>[0-9]+)
                )
            )?
            [\x20\t]+(?<text>\S.*)
            /#
        guard let match = try? pattern.wholeMatch(in: line),
              let start = clock(match.start), start < Time.minutesPerDay else { return nil }

        let text = match.text
        var end: Int?
        if let endToken = match.end {
            guard let clockEnd = clock(endToken) else { return nil }
            end = clockEnd <= start ? clockEnd + Time.minutesPerDay : clockEnd
        } else if let durationToken = match.duration {
            guard let minutes = Int(durationToken), (1...Time.minutesPerDay).contains(minutes) else { return nil }
            end = start + minutes
        } else if text.hasPrefix("+") || text.hasPrefix("-") || text.hasPrefix("–") {
            return nil
        }

        return Event(text: String(text), time: Time(start: start, end: end), lineNumber: lineNumber)
    }

    private static func clock(_ token: Substring) -> Int? {
        guard let value = Int(token.filter({ $0 != ":" })) else { return nil }
        let hasMinutes = token.count > 2
        let hours = hasMinutes ? value / 100 : value
        let minutes = hasMinutes ? value % 100 : 0
        guard minutes < 60, hours < 24 || (hours == 24 && minutes == 0) else { return nil }
        return hours * 60 + minutes
    }
}
