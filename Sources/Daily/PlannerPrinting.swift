import AppKit
import PDFKit

@MainActor
func sendToPrinter(_ document: PDFDocument) throws -> String {
    guard let printer = NSPrintInfo.defaultPrinter else {
        throw DailyError("No default printer is configured in macOS.")
    }

    let operation = try plannerPrintOperation(for: document, printer: printer)
    operation.showsPrintPanel = false
    operation.showsProgressPanel = false
    guard operation.run() else {
        throw DailyError("macOS could not submit the print job to \(printer.name).")
    }
    return printer.name
}

@MainActor
func showPrintDialog(for document: PDFDocument, in window: NSWindow) throws {
    let operation = try plannerPrintOperation(for: document)
    operation.showsPrintPanel = true
    operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
}

func openPlannerPDF(_ data: Data) throws -> PDFDocument {
    guard let document = PDFDocument(data: data) else {
        throw DailyError("Could not open the generated PDF.")
    }
    return document
}

@MainActor
func plannerPrintOperation(for document: PDFDocument, printer: NSPrinter? = nil) throws -> NSPrintOperation {
    let info = NSPrintInfo()
    if let printer {
        info.printer = printer
    }
    info.orientation = .portrait
    info.paperSize = PlannerPDF.paperSize
    info.leftMargin = 0
    info.rightMargin = 0
    info.topMargin = 0
    info.bottomMargin = 0
    info.jobDisposition = .spool

    guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: false) else {
        throw DailyError("Could not prepare the PDF for printing.")
    }
    operation.jobTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? "Daily"
    return operation
}
