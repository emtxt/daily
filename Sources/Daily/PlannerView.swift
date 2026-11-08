import PDFKit
import SwiftUI

struct PlannerPreview {
    let source: String
    let document: PDFDocument

    init(source: String) throws {
        let plan = Plan(source)
        self.source = source
        document = try openPlannerPDF(PlannerPDF.make(from: plan))
    }

    func document(for source: String) -> PDFDocument? {
        self.source == source ? document : nil
    }
}

struct PlannerView: View {
    @AppStorage("planSource") private var source = ""
    @AppStorage("generatedPlanTitle") private var generatedTitle = ""
    @State private var preview: PlannerPreview?
    @State private var showsHelp = false
    @State private var showsError = false
    @State private var errorMessage = ""
    @State private var confirmsReplacement = false
    @State private var replacementTitle = ""
    @State private var printStatus: String?

    private var printableDocument: PDFDocument? {
        preview?.document(for: source)
    }

    var body: some View {
        HSplitView {
            editorPane
                .frame(minWidth: 350, idealWidth: 420, maxWidth: .infinity)
            previewPane
                .frame(minWidth: 420, idealWidth: 640, maxWidth: .infinity)
        }
        .onChange(of: source) { printStatus = nil }
        .alert("Daily", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Replace the current plan?", isPresented: $confirmsReplacement) {
            Button("Cancel", role: .cancel) {}
            Button("Replace Plan", role: .destructive) {
                replacePlan(with: replacementTitle)
            }
        } message: {
            if replacementTitle.isEmpty {
                Text("This will clear your draft and start an untitled plan.")
            } else {
                Text("This will replace your draft with a blank plan for \(replacementTitle).")
            }
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan").font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Button("Today") { startNewPlan(daysFromToday: 0) }
                    Button("Tomorrow") { startNewPlan(daysFromToday: 1) }
                    Button("Blank") { startNewPlan(with: "") }
                    Button("Format") {
                        source = Plan(source).formattedSource
                    }
                    Button {
                        showsHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 19))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Plan format help")
                    .help("Plan format help")
                    .popover(isPresented: $showsHelp, arrowEdge: .bottom) {
                        PlanFormatHelp()
                    }
                }
            }

            TextEditor(text: $source)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("Plan text")
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator)
                        .allowsHitTesting(false)
                }
        }
        .padding(16)
    }

    private func startNewPlan(daysFromToday: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: daysFromToday, to: .now) else {
            presentError(DailyError("Could not determine the date for the new plan."))
            return
        }
        startNewPlan(with: Plan.title(for: date))
    }

    private func startNewPlan(with title: String) {
        if Plan.hasDraftContent(source, generatedTitle: generatedTitle) {
            replacementTitle = title
            confirmsReplacement = true
        } else {
            replacePlan(with: title)
        }
    }

    private func replacePlan(with title: String) {
        generatedTitle = title
        source = title.isEmpty ? "" : title + "\n\n"
        preview = nil
        printStatus = nil
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PDF Preview").font(.headline)
                Spacer()
                Button("Create Preview", action: createPreview)
                PrintSplitButton(
                    document: printableDocument,
                    onPrinted: { printStatus = "Sent to \($0)." },
                    onError: presentError
                )
                .fixedSize()
            }

            Group {
                if let preview {
                    PDFPreview(document: preview.document)
                } else {
                    ContentUnavailableView(
                        "No Preview",
                        systemImage: "doc.richtext",
                        description: Text("Create a preview to see your printable plan.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.separator)
                    .allowsHitTesting(false)
            }

            if preview != nil && printableDocument == nil {
                Text("Plan changed. Create a new preview to print.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let printStatus {
                Text(printStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func createPreview() {
        printStatus = nil
        do {
            preview = try PlannerPreview(source: source)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: any Error) {
        printStatus = nil
        errorMessage = error.localizedDescription
        showsError = true
    }
}

private struct PlanFormatHelp: View {
    private static let example = """
        Monday, 9 November

        # Schedule
        8 Breakfast
        845 - 9:30 Walk to the library
        1000+45 Draft the project outline
        13:30 Lunch with Sam

        # To-dos
        * Send the outline by 15:00
        - Return library books
        """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Plan Format").font(.title3.bold())
                Text("Example").font(.headline)
                Text(verbatim: Self.example)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Text("Syntax").font(.headline)
                Text("**Title.** Use the first nonblank, noncomment line for the plan title.")
                Text("**Events.** Start with a 24-hour time. `8` means 08:00, `845` means 08:45, and `1330` means 13:30. Use `-` for an end time or `+` for a duration in minutes. Spaces around either are optional. An end time at or before the start means the event ends the next day.")
                Text("**To-dos.** Start with `-` for a regular task or `*` for high priority.")
                Text("**Comments.** Start a line with `#`. The preview skips comments and invalid entries.")
                Text("**Format** normalizes times, capitalizes descriptions, sorts events, and puts high-priority tasks first. Comments and invalid lines move to the end in their original order.")
            }
            .font(.callout)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 430, height: 510)
    }
}
