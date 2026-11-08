# Daily

Daily is a macOS app that turns a plain-text plan into a printable, single-page A4 PDF. The SwiftPM package uses Swift 6.2 and targets macOS 14 or later.

## Project layout

- `Sources/Daily/DailyApp.swift` declares the SwiftUI app and window.
- `Sources/Daily/PlannerView.swift` manages the editor, format help, and preview.
- `Sources/Daily/PlannerControls.swift` embeds the PDFKit preview and AppKit split print button.
- `Sources/Daily/Plan.swift` owns the plan format, event and to-do models, and formatting.
- `Sources/Daily/PlannerPDF.swift` renders the calendar and checklist using Core Graphics and Core Text.
- `Sources/Daily/PlannerPrinting.swift` configures print jobs using PDFKit and AppKit.
- `Tests/DailyTests/` contains Swift Testing suites for the plan, preview, PDF, and print setup.

## Working conventions

- Keep changes small and use native Swift and macOS APIs where they fit. Prefer a clear error for unexpected input or system state.
- Keep the documented plan format in `README.md` and the in-app guide in `PlannerView.swift` in sync. Preserve comments and invalid entries when formatting.
- Generate previews on demand. Print the current preview and ask for a fresh one after edits.
- Keep PDF output printable in grayscale on one A4 page, with the calendar on the left and the to-do checklist on the right.
- Use Swift Testing for regressions. Verify print setup without sending real print jobs.

## Build and verify

- Run `swift test` from the project root.
- Run `./build.sh` to build and sign `.build/local/Daily.app` for local use.
- Open the app and paste `example.txt` into the editor to check the GUI and preview.
- Keep generated PDFs and app bundles out of version control.
