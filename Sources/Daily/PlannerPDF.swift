import AppKit
import CoreText

enum ScheduleRange: Equatable {
    case automatic
    case fixed(start: Int, end: Int)

    func hours(for events: [Plan.Event]) throws -> ClosedRange<Int> {
        let eventHours = events.first.map { first in
            let start = first.time.start / 60
            let latestEnd = events.map(\.time.endOnPage).max() ?? 0
            let latestStart = events.last?.time.start ?? first.time.start
            let end = max((latestEnd + 59) / 60, latestStart / 60 + 1)
            return start...end
        }

        switch self {
        case .automatic:
            return eventHours ?? 0...24
        case let .fixed(start, end):
            guard 0 <= start, start < end, end <= 24 else {
                throw DailyError("Choose a calendar start hour before its end hour.")
            }
            if let eventHours, eventHours.lowerBound < start || eventHours.upperBound > end {
                throw DailyError("The calendar hours must include all events. Adjust the range or turn on automatic hours.")
            }
            return start...end
        }
    }
}

enum PlannerPDF {
    static let paperSize = CGSize(width: 210 * 72 / 25.4, height: 297 * 72 / 25.4)
    private static let margin: CGFloat = 42
    private static let rightEdge = paperSize.width - margin
    private static let bottomEdge = paperSize.height - margin

    private struct Style {
        let taskSize: CGFloat
        let taskPadding: CGFloat
        let eventSize: CGFloat
        let eventSpacing: CGFloat
    }

    private struct CalendarEntry {
        let time: Plan.Time
        let lines: [CTLine]
        let height: CGFloat
    }

    private struct HourBand {
        let entries: [CalendarEntry]
        let minimumHeight: CGFloat
    }

    private enum Overflow: Error {
        case title
        case row(Int)
        case calendar
    }

    static func make(from plan: Plan, scheduleRange: ScheduleRange = .automatic) throws -> Data {
        let hours = try scheduleRange.hours(for: plan.events)
        do {
            return try render(plan, hours: hours, style: Style(taskSize: 12, taskPadding: 8, eventSize: 11, eventSpacing: 5))
        } catch is Overflow {
            do {
                return try render(plan, hours: hours, style: Style(taskSize: 10.5, taskPadding: 4, eventSize: 10, eventSpacing: 3))
            } catch Overflow.title {
                throw DailyError("The title is too long for one A4 page. Shorten it and try again.")
            } catch Overflow.row(let lineNumber) {
                throw DailyError("The plan does not fit on one A4 page. Shorten the text or remove items near line \(lineNumber).")
            } catch Overflow.calendar {
                throw DailyError("The calendar does not fit on one A4 page. Shorten or remove schedule items.")
            }
        }
    }

    private static func render(_ plan: Plan, hours: ClosedRange<Int>, style: Style) throws -> Data {
        let data = NSMutableData()
        var bounds = CGRect(origin: .zero, size: paperSize)
        let metadata = plan.title.isEmpty ? [:] : [kCGPDFContextTitle: plan.title]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, metadata as CFDictionary) else {
            throw DailyError("Could not create a PDF context.")
        }

        do {
            defer { context.closePDF() }
            context.beginPDFPage(nil)
            defer { context.endPDFPage() }
            try draw(plan, hours: hours, in: context, style: style)
        }
        return data as Data
    }

    private static func draw(_ plan: Plan, hours: ClosedRange<Int>, in context: CGContext, style: Style) throws {
        let titleFont = NSFont.systemFont(ofSize: 32, weight: .semibold)
        let sectionFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let labelFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let width = rightEdge - margin

        let label = CTLineCreateWithAttributedString(NSAttributedString(string: "DAILY PLAN", attributes: [
            .font: labelFont,
            .kern: 1.7,
            textColor: gray(0.35)
        ]))
        draw(label, x: margin, baseline: margin + 9, in: context)

        let titleTop = margin + 21
        let titleLeading: CGFloat = 38
        let titleGap: CGFloat = 17
        let titleLimit = Int((bottomEdge - titleTop - titleGap) / titleLeading)
        let titleLines = try wrap(plan.title, font: titleFont, width: width, limit: titleLimit, overflow: .title)
        for (index, line) in titleLines.enumerated() {
            draw(line, x: margin, baseline: titleTop + 32 + CGFloat(index) * titleLeading, in: context)
        }
        let headerBottom = titleTop + CGFloat(max(1, titleLines.count)) * titleLeading + titleGap
        rule(at: headerBottom, from: margin, to: rightEdge, shade: 0.20, weight: 0.85, in: context)

        let gutter: CGFloat = 24
        let calendarRight = margin + floor((width - gutter) * 0.62)
        let taskLeft = calendarRight + gutter
        let headingBaseline = headerBottom + 36
        let contentTop = headingBaseline + 15

        draw(line("Schedule", font: sectionFont), x: margin, baseline: headingBaseline, in: context)
        try drawCalendar(plan.events, hours: hours, top: contentTop, right: calendarRight, style: style, in: context)
        if !plan.todos.isEmpty || plan.isEmpty {
            draw(line("To-do", font: sectionFont), x: taskLeft,
                 baseline: headingBaseline, in: context)
            try drawTasks(plan.todos, top: contentTop, left: taskLeft, style: style, in: context)
        }

        let timestamp = Date.now.formatted(.verbatim(
            """
            \(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits) \
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)
            """,
            locale: Locale(identifier: "en_US_POSIX"), timeZone: .current, calendar: Calendar(identifier: .gregorian)
        ))
        let footer = line("Generated \(timestamp)", font: .systemFont(ofSize: 7), shade: 0.42)
        let footerWidth = CTLineGetTypographicBounds(footer, nil, nil, nil)
        draw(footer, x: rightEdge - footerWidth, baseline: paperSize.height - 25, in: context)
    }

    private static func drawTasks(_ todos: [Plan.Todo], top: CGFloat, left: CGFloat,
                                  style: Style, in context: CGContext) throws {
        let normalFont = NSFont.systemFont(ofSize: style.taskSize)
        let priorityFont = NSFont.systemFont(ofSize: style.taskSize, weight: .bold)
        let leading = ceil(style.taskSize * 1.35)
        let textX = left + 20
        var rowTop = top
        rule(at: rowTop, from: left, to: rightEdge, shade: 0.61, weight: 0.55, in: context)

        for todo in todos {
            let font = todo.isHighPriority ? priorityFont : normalFont
            let room = bottomEdge - rowTop - 2 * style.taskPadding
            let lines = try wrap(todo.text, font: font, width: rightEdge - textX,
                                 limit: Int(floor(room / leading)), overflow: .row(todo.lineNumber))
            let height = 2 * style.taskPadding + CGFloat(lines.count) * leading
            if todo.isHighPriority {
                context.setFillColor(gray(0.94))
                context.fill(CGRect(x: left, y: paperSize.height - rowTop - height + 0.5,
                                    width: rightEdge - left, height: height - 1))
            }
            let baseline = rowTop + style.taskPadding + ceil(font.ascender)
            checkbox(x: left + 0.5, baseline: baseline, in: context)
            for (index, line) in lines.enumerated() {
                draw(line, x: textX, baseline: baseline + CGFloat(index) * leading, in: context)
            }

            rowTop += height
            rule(at: rowTop, from: left, to: rightEdge, shade: 0.76, weight: 0.45, in: context)
        }

        let rowHeight = 2 * style.taskPadding + leading
        while rowTop + rowHeight <= bottomEdge {
            if todos.isEmpty {
                let baseline = rowTop + style.taskPadding + ceil(normalFont.ascender)
                checkbox(x: left + 0.5, baseline: baseline, in: context)
            }
            rowTop += rowHeight
            rule(at: rowTop, from: left, to: rightEdge, shade: 0.76, weight: 0.45, in: context)
        }
    }

    private static func drawCalendar(_ events: [Plan.Event], hours: ClosedRange<Int>, top: CGFloat, right: CGFloat,
                                     style: Style, in context: CGContext) throws {
        let gridLeft = margin + 37
        let clockFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let checkboxX = gridLeft + 4
        let timeX = checkboxX + 17
        let rangeLabel = line(Plan.Time(start: 0, end: 0).label, font: clockFont)
        let textX = timeX + ceil(CTLineGetTypographicBounds(rangeLabel, nil, nil, nil)) + 8
        let gridHeight = bottomEdge - 7 - top
        let font = NSFont.systemFont(ofSize: style.eventSize, weight: .medium)
        let leading = ceil(style.eventSize * 1.25)
        let bandPadding: CGFloat = 4
        let eventsByHour = Dictionary(grouping: events) { $0.time.start / 60 }
        let bands = try hours.dropLast().map { hour in
            let entries = try (eventsByHour[hour] ?? []).map { event in
                let lines = try wrap(event.text, font: font, width: right - textX,
                                     limit: Int(floor(gridHeight / leading)), overflow: .row(event.lineNumber))
                return CalendarEntry(time: event.time, lines: lines,
                                     height: CGFloat(lines.count) * leading + style.eventSpacing)
            }
            let entriesHeight = entries.reduce(CGFloat(0)) { $0 + $1.height }
            return HourBand(entries: entries, minimumHeight: max(16, 2 * bandPadding + entriesHeight))
        }
        let minimums = bands.map(\.minimumHeight)
        guard minimums.reduce(0, +) <= gridHeight else { throw Overflow.calendar }
        let hourHeight = fittedHourHeight(minimums, available: gridHeight)

        var hourTop = top
        for (offset, band) in bands.enumerated() {
            drawHour(hours.lowerBound + offset, top: hourTop, left: gridLeft, right: right, font: clockFont, in: context)
            let height = max(hourHeight, band.minimumHeight)
            let freeSpace = height - band.minimumHeight
            var entryTop = hourTop + bandPadding
            for entry in band.entries {
                let minuteOffset = freeSpace * CGFloat(entry.time.start % 60) / 60
                let baseline = entryTop + minuteOffset + ceil(font.ascender)
                draw(line(entry.time.label, font: clockFont, shade: 0.28), x: timeX, baseline: baseline, in: context)
                checkbox(x: checkboxX, baseline: baseline, in: context)
                for (index, line) in entry.lines.enumerated() {
                    draw(line, x: textX, baseline: baseline + CGFloat(index) * leading, in: context)
                }
                entryTop += entry.height
            }
            hourTop += height
        }
        drawHour(hours.upperBound, top: hourTop, left: gridLeft, right: right, font: clockFont, in: context)
    }

    private static func fittedHourHeight(_ minimums: [CGFloat], available: CGFloat) -> CGFloat {
        var remaining = available
        var count = minimums.count
        // Give crowded hours the space they need, then share the rest evenly.
        for minimum in minimums.sorted(by: >) {
            let height = remaining / CGFloat(count)
            if minimum <= height { return height }
            remaining -= minimum
            count -= 1
        }
        return 0
    }

    private static func drawHour(_ hour: Int, top: CGFloat, left: CGFloat, right: CGFloat,
                                 font: NSFont, in context: CGContext) {
        rule(at: top, from: left, to: right, shade: 0.72, weight: 0.5, in: context)
        draw(line(Plan.Time.label(for: hour * 60), font: font, shade: 0.36),
             x: margin, baseline: top + 3, in: context)
    }

    private static func wrap(_ text: String, font: NSFont, width: CGFloat,
                             limit: Int, overflow: Overflow) throws -> [CTLine] {
        let content = NSAttributedString(string: text, attributes: [.font: font, textColor: gray(0.12)])
        let typesetter = CTTypesetterCreateWithAttributedString(content)
        var lines: [CTLine] = []
        var start = 0

        while start < content.length {
            guard lines.count < limit else { throw overflow }
            let length = CTTypesetterSuggestLineBreak(typesetter, start, width)
            guard length > 0 else { throw overflow }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: length))
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            guard lineWidth - CTLineGetTrailingWhitespaceWidth(line) <= width else { throw overflow }
            lines.append(line)
            start += length
        }
        return lines
    }

    private static func line(_ text: String, font: NSFont, shade: CGFloat = 0.12) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            textColor: gray(shade)
        ]))
    }

    private static func draw(_ line: CTLine, x: CGFloat, baseline: CGFloat, in context: CGContext) {
        context.textPosition = CGPoint(x: x, y: paperSize.height - baseline)
        CTLineDraw(line, context)
    }

    private static func checkbox(x: CGFloat, baseline: CGFloat, in context: CGContext) {
        let box = CGRect(x: x, y: paperSize.height - baseline - 1, width: 10, height: 10)
        context.setStrokeColor(gray(0.28))
        context.setLineWidth(0.75)
        context.stroke(box)
    }

    private static func rule(at top: CGFloat, from left: CGFloat, to right: CGFloat,
                             shade: CGFloat, weight: CGFloat, in context: CGContext) {
        let y = paperSize.height - top
        context.setStrokeColor(gray(shade))
        context.setLineWidth(weight)
        context.move(to: CGPoint(x: left, y: y))
        context.addLine(to: CGPoint(x: right, y: y))
        context.strokePath()
    }

    private static func gray(_ value: CGFloat) -> CGColor {
        CGColor(gray: value, alpha: 1)
    }

    private static let textColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
}
