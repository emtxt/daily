import AppKit
import PDFKit
import SwiftUI

struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.backgroundColor = .windowBackgroundColor
        view.setAccessibilityLabel("Plan PDF preview")
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document !== document else { return }
        view.document = document
        view.autoScales = true
    }
}

struct PrintSplitButton: NSViewRepresentable {
    let document: PDFDocument?
    let onPrinted: (String) -> Void
    let onError: (any Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: self)
    }

    func makeNSView(context: Context) -> NSComboButton {
        let menu = NSMenu()
        let dialog = NSMenuItem(
            title: "Print Dialog…",
            action: #selector(Coordinator.openDialog),
            keyEquivalent: ""
        )
        dialog.target = context.coordinator
        menu.addItem(dialog)

        let button = NSComboButton(
            title: "Print",
            menu: menu,
            target: context.coordinator,
            action: #selector(Coordinator.printDirectly)
        )
        button.style = .split
        button.toolTip = "Print to the default printer"
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSComboButton, context: Context) {
        context.coordinator.configuration = self
        button.isEnabled = document != nil
    }

    @MainActor
    final class Coordinator: NSObject {
        var configuration: PrintSplitButton
        weak var button: NSComboButton?

        init(configuration: PrintSplitButton) {
            self.configuration = configuration
        }

        @objc func printDirectly() {
            guard let document = configuration.document else { return }
            do {
                configuration.onPrinted(try sendToPrinter(document))
            } catch {
                configuration.onError(error)
            }
        }

        @objc func openDialog() {
            guard let document = configuration.document, let window = button?.window else { return }
            do {
                try showPrintDialog(for: document, in: window)
            } catch {
                configuration.onError(error)
            }
        }
    }
}
