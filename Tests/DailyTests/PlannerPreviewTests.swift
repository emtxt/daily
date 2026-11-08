import PDFKit
import Testing
@testable import daily

@Suite
struct PlannerPreviewTests {
    @Test
    func previewOnlyPrintsForTheSourceItRendered() throws {
        let source = "Monday\n8 Breakfast\n- Buy coffee\nInvalid entry"
        let preview = try PlannerPreview(source: source)
        let document = try #require(preview.document(for: source))

        #expect(document === preview.document)
        #expect(document.pageCount == 1)
        #expect(document.string?.contains("Buy coffee") == true)
        #expect(document.string?.contains("Invalid entry") == false)
        #expect(preview.document(for: source + "\n- New task") == nil)
    }

    @Test(arguments: ["": nil, "# Comment": nil, "Monday\n# Comment\nInvalid entry": "Monday"] as [String: String?])
    func previewWithoutItemsProducesAnA4Worksheet(source: String, title: String?) throws {
        let preview = try PlannerPreview(source: source)
        let document = try #require(preview.document(for: source))
        let page = try #require(document.page(at: 0))
        let size = page.bounds(for: .mediaBox).size

        #expect(document.pageCount == 1)
        #expect(abs(size.width - PlannerPDF.paperSize.width) < 0.1)
        #expect(abs(size.height - PlannerPDF.paperSize.height) < 0.1)
        let text = try #require(page.string)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == title)
        if let title {
            #expect(text.contains(title))
        } else {
            #expect(!text.contains(Plan.title(for: .now)))
        }
        #expect(text.contains("Schedule"))
        #expect(text.contains("08:00"))
        #expect(text.contains("18:00"))
        #expect(text.contains("To-do"))
        #expect(!text.contains("Invalid entry"))
    }
}
