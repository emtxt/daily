import Foundation
import Testing
@testable import daily

@Suite
struct PlanTests {
    @Test
    func parsesUnicodeAndIgnoresWhitespaceCommentsAndInvalidLines() throws {
        let source = "\r\n  # instructions\r\n  Café #1  \r\n  - Acheter du thé #2  \r\n"
            + "garbage\r\n  * Réserver\r\n  8 Petit-déjeuner\r\n  *  \r\n  # footer\r\n"
        let plan = Plan(source)

        #expect(plan.title == "Café #1")
        #expect(plan.todos.map(\.text) == ["Acheter du thé #2", "Réserver"])
        #expect(plan.todos.map(\.isHighPriority) == [false, true])
        #expect(plan.todos.map(\.lineNumber) == [4, 6])

        let event = try #require(plan.events.first)
        #expect(event.text == "Petit-déjeuner")
        #expect(event.lineNumber == 7)
    }

    @Test
    func leavesTitleEmptyForBlankAndCommentOnlyDrafts() {
        let plan = Plan("\n # instructions only\n")

        #expect(plan.title.isEmpty)
        #expect(plan.events.isEmpty)
        #expect(plan.todos.isEmpty)
        #expect(plan.formattedSource == " # instructions only\n")
        #expect(Plan("  \n").formattedSource.isEmpty)
    }

    @Test
    func replacementProtectsUserContentEvenWhenItDoesNotRender() {
        let generatedTitle = "Monday, 9 November 2026"
        #expect(!Plan.hasDraftContent(" \n", generatedTitle: generatedTitle))
        #expect(!Plan.hasDraftContent(generatedTitle + "\n\n", generatedTitle: generatedTitle))

        for content in ["Custom title", "# reminder", generatedTitle + "\n- Task",
                        generatedTitle + "\ninvalid entry"] {
            #expect(Plan.hasDraftContent(content, generatedTitle: generatedTitle))
        }
    }

    typealias ClockCase = (input: String, start: Int, end: Int?, label: String)

    private static let clockCases: [ClockCase] = [
        ("0", 0, nil, "00:00"),
        ("8", 480, nil, "08:00"),
        ("08", 480, nil, "08:00"),
        ("0800", 480, nil, "08:00"),
        ("845", 525, nil, "08:45"),
        ("8:45", 525, nil, "08:45"),
        ("09:01", 541, nil, "09:01"),
        ("13", 780, nil, "13:00"),
        ("1330", 810, nil, "13:30"),
        ("9-930", 540, 570, "09:00-09:30"),
        ("9 \t-\t 9:30", 540, 570, "09:00-09:30"),
        ("9 – 930", 540, 570, "09:00-09:30"),
        ("1000+45", 600, 645, "10:00-10:45"),
        ("10 + 045", 600, 645, "10:00-10:45"),
        ("23:59+1", 1439, 1440, "23:59-24:00"),
        ("23 - 2400", 1380, 1440, "23:00-24:00"),
        ("23 - 1", 1380, 1500, "23:00-01:00"),
        ("22 + 180", 1320, 1500, "22:00-01:00"),
        ("8-8", 480, 1920, "08:00-08:00"),
        ("8+1440", 480, 1920, "08:00-08:00")
    ]

    @Test(arguments: clockCases)
    func parsesClockAndDurationSyntax(_ example: ClockCase) throws {
        let plan = Plan("Day\n  \(example.input)\t👩🏽‍💻 Écrire # notes")
        let event = try #require(plan.events.first)
        let time = event.time
        #expect(time.start == example.start)
        #expect(time.end == example.end)
        #expect(time.label == example.label)
        #expect(time.endOnPage == min(example.end ?? example.start, 1440))
        #expect(event.text == "👩🏽‍💻 Écrire # notes")
    }

    @Test
    func ignoresInvalidCalendarEntriesWithoutFallingBackToEventText() {
        let lines = [
            "24 No start at midnight", "2401 Out of range", "9:60 Invalid minute",
            "25 Invalid hour", "12345 Too many digits", "8:5 Missing zero", "８ Non-ASCII time",
            "8 No time modifier here", "8 -", "8 – garbage", "8 + forty", "8 - 2500 Invalid end",
            "8 + 0 No duration", "8 + 1441 Too long", "8 + 99999999999999999999 Overflow",
            "8 + -45 Negative", "8+4.5 Fraction", "8NoSpace", "8"
        ]
        let plan = Plan((["Day"] + lines).joined(separator: "\n"))

        #expect(plan.events.map(\.text) == ["No time modifier here"])
    }

    @Test
    func groupsEntriesAndSortsEventsStably() {
        let plan = Plan("""
            Day
            14 Late
            - Normal first
            8 Early first
            * Important first
            08:00 Early second
            - Normal second
            *Important second
            """)

        #expect(plan.events.map(\.text) == ["Early first", "Early second", "Late"])
        #expect(plan.todos.map(\.text) == ["Normal first", "Important first", "Normal second", "Important second"])
    }

    @Test
    func formatNormalizesEntriesAndPreservesOtherLinesInOrder() {
        let plan = Plan("""
            # comment
              Friday #1
              # Schedule
              2300 + 90  late train
              # To-dos
              - normal first
              * «écrire»
              8 breakfast
              9-10 plan the day
              * important second
              invalid entry
              ! ignored
              # reminder
              *
              8 + oops
              - normal second
            """)

        let formattedSource = plan.formattedSource
        #expect(formattedSource == """
            Friday #1

            # Schedule
            08:00 Breakfast
            09:00 - 10:00 Plan the day
            23:00 - 00:30 Late train

            # To-dos
            * «Écrire»
            * Important second
            - Normal first
            - Normal second

            # comment
              invalid entry
              ! ignored
              # reminder
              *
              8 + oops

            """)
        let reparsed = Plan(formattedSource)
        #expect(reparsed.formattedSource == formattedSource)
        #expect(reparsed.events.count == 3)
        #expect(reparsed.todos.count == 4)
    }

    @Test
    func exclamationMarkIsLiteralText() {
        let plan = Plan("!Day\n- 123\n!!")
        #expect(plan.title == "!Day")
        #expect(plan.formattedSource == "!Day\n\n# To-dos\n- 123\n\n!!\n")
    }
}
