import AppKit
import PDFKit
import Testing
@testable import daily

@Suite
struct PlannerPDFTests {
    @Test
    func rendersOneA4PageWithTwoColumnsAndTimestamp() throws {
        let plan = Plan("""
            Thursday checklist
            - Ordinary task
            9 Morning event
            * Priority task
            """)
        let document = try openPlannerPDF(PlannerPDF.make(from: plan))
        #expect(document.pageCount == 1)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == plan.title)
        let page = try #require(document.page(at: 0))
        let paper = page.bounds(for: .mediaBox)
        #expect(abs(paper.width * 25.4 / 72 - 210) <= 0.05)
        #expect(abs(paper.height * 25.4 / 72 - 297) <= 0.05)

        let schedule = try bounds(of: "Schedule", on: page)
        let todos = try bounds(of: "To-do", on: page)
        #expect(abs(schedule.midY - todos.midY) <= 1)
        #expect(try bounds(of: "Morning event", on: page).maxX < todos.minX)

        let normal = try bounds(of: "Ordinary task", on: page)
        let priority = try bounds(of: "Priority task", on: page)
        #expect(normal.minX >= todos.minX)
        #expect(normal.midY > priority.midY)
        #expect(abs(normal.minX - priority.minX) <= 1)
        #expect(page.string?.contains("08:00") == true)
        #expect(page.string?.contains("18:00") == true)

        let text = try #require(page.string)
        let timestamp = try #require(text.firstMatch(of: #/Generated [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/#))
        let footer = try bounds(of: String(timestamp.output), on: page)
        #expect(footer.minX > paper.midX)
        #expect(footer.maxY < 42)
    }

    @Test
    func rendersCheckboxesAndShadesPriorityRows() throws {
        let document = try openPlannerPDF(PlannerPDF.make(from: Plan("""
            Day
            9 + 15 Morning event
            - Ordinary task
            * Priority task
            """)))
        let page = try #require(document.page(at: 0))
        let normal = try bounds(of: "Ordinary task", on: page)
        let priority = try bounds(of: "Priority task", on: page)
        let eventTime = try bounds(of: "09:00-09:15", on: page)

        // Sample the box-sized areas immediately left of the printed labels.
        for (label, offset) in [(normal, 20.0), (priority, 20.0), (eventTime, 17.0)] {
            let area = CGRect(x: label.minX - offset - 2, y: label.midY - 6, width: 14, height: 12)
            #expect(try minimumGray(in: area, on: page) < 150)
        }

        // Sample the gap between the checkbox and the text in each to-do row.
        let normalBackground = CGRect(x: normal.minX - 6, y: normal.midY - 1, width: 2, height: 2)
        let priorityBackground = CGRect(x: priority.minX - 6, y: priority.midY - 1, width: 2, height: 2)
        let white = try minimumGray(in: normalBackground, on: page)
        let shaded = try minimumGray(in: priorityBackground, on: page)
        #expect(white == 255)
        #expect(shaded > 220)
        #expect(shaded < white)
    }

    @Test
    func calendarExtendsToMidnightAndSeparatesOverlappingEvents() throws {
        let document = try openPlannerPDF(PlannerPDF.make(from: Plan("""
            Extended calendar
            23:50-1 Late train
            6:15-7 First event
            6:30-7 Second event with a long title that should wrap
            6:45 Third event
            """)))
        let page = try #require(document.page(at: 0))
        let early = try bounds(of: "06:00", on: page)
        let midnight = try bounds(of: "24:00", on: page)
        let first = try bounds(of: "First event", on: page)
        let second = try bounds(of: "Second event", on: page)
        let wrapped = try bounds(of: "should wrap", on: page)
        let third = try bounds(of: "Third event", on: page)
        let late = try bounds(of: "23:50-01:00", on: page)

        #expect(early.midY > first.maxY)
        #expect(first.minY > second.maxY)
        #expect(second.minY > wrapped.maxY)
        #expect(wrapped.minY > third.maxY)
        #expect(late.midY > midnight.midY)
        #expect(page.string?.contains("To-do") == false)
    }

    @Test
    func compactsDenseChecklistToFitOnePage() throws {
        let items = (1...23).map { "- Task \($0)" }.joined(separator: "\n")
        let document = try openPlannerPDF(PlannerPDF.make(from: Plan("Dense checklist\n" + items)))
        let page = try #require(document.page(at: 0))

        #expect(document.pageCount == 1)
        #expect(page.string?.contains("Task 23") == true)
        #expect(page.string?.contains("Schedule") == false)
    }

    @Test
    func reportsOverflowInTitleCalendarAndChecklist() throws {
        let title = String(repeating: "Long title ", count: 250)
        let titleError = try #require(throws: DailyError.self) {
            try PlannerPDF.make(from: Plan(title + "\n- Todo"))
        }
        #expect(titleError.localizedDescription.contains("The title is too long"))

        for prefix in ["- ", "8 "] {
            let item = prefix + String(repeating: "Very long description ", count: 250)
            let itemError = try #require(throws: DailyError.self) {
                try PlannerPDF.make(from: Plan("Day\n# Comment\n" + item))
            }
            #expect(itemError.localizedDescription.contains("near line 3"))
        }

        let crowdedHour = Array(repeating: "8 Short event", count: 60).joined(separator: "\n")
        let crowdedHourError = try #require(throws: DailyError.self) {
            try PlannerPDF.make(from: Plan("Day\n" + crowdedHour + "\n17 Final unrelated event"))
        }
        #expect(crowdedHourError.localizedDescription == "The calendar does not fit on one A4 page. Shorten or remove schedule items.")
    }

    @Test
    func rejectsInvalidPDFData() throws {
        let error = try #require(throws: DailyError.self) {
            try openPlannerPDF(Data("invalid PDF".utf8))
        }
        #expect(error.localizedDescription == "Could not open the generated PDF.")
    }

    @MainActor
    @Test
    func preparesA4PrintOperation() throws {
        let document = try openPlannerPDF(PlannerPDF.make(from: Plan("Print this plan\n- Todo")))
        let operation = try plannerPrintOperation(for: document)
        let info = operation.printInfo

        #expect(operation.jobTitle == "Print this plan")
        #expect(info.orientation == .portrait)
        #expect(abs(info.paperSize.width - PlannerPDF.paperSize.width) <= 0.1)
        #expect(abs(info.paperSize.height - PlannerPDF.paperSize.height) <= 0.1)
        #expect(info.leftMargin == 0)
        #expect(info.rightMargin == 0)
        #expect(info.topMargin == 0)
        #expect(info.bottomMargin == 0)
        #expect(info.jobDisposition == .spool)

        document.documentAttributes = nil
        #expect(try plannerPrintOperation(for: document).jobTitle == "Daily")
    }

    private func bounds(of text: String, on page: PDFPage) throws -> CGRect {
        let selection = try #require(page.document?.findString(text, withOptions: .literal).first,
                                      "Missing PDF text: \(text)")
        return selection.bounds(for: page)
    }

    private func minimumGray(in area: CGRect, on page: PDFPage) throws -> UInt8 {
        let width = Int(area.width * 2)
        let height = Int(area.height * 2)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: 2, y: 2)
        context.translateBy(x: -area.minX, y: -area.minY)
        context.drawPDFPage(try #require(page.pageRef))
        let data = try #require(context.data)
        return try #require(UnsafeRawBufferPointer(start: data, count: width * height).min())
    }
}
