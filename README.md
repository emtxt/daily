# Daily

Daily is a macOS app for turning a plain-text plan into a printable, single-page A4 PDF. The calendar appears on the left and the to-do checklist on the right. Both use checkboxes you can mark by hand.

## Build and open

Daily requires macOS 14 (Sonoma) or later. Build with Xcode 26 or later and Swift 6.2 or later.

```sh
./build.sh
open .build/local/Daily.app
```

The script builds and signs `Daily.app` for local use. Run `./deploy.sh` to build and install it at `~/Applications/Daily.app`. Deployment replaces an existing Daily bundle after verifying the new build's signature.

## Write and print a plan

1. Type or paste a plan into the editor. Daily remembers the draft between launches. **Today** and **Tomorrow** start a plan for that date. **Blank** clears the editor. Daily asks before replacing existing content.
2. Use **Format** to normalize times and group entries, or click **?** for the format guide.
3. Click **Create Preview** to generate the PDF. After editing the plan, create a fresh preview to enable printing.
4. Click **Print** to send the preview to the macOS default printer. Use the arrow beside **Print** and choose **Print Dialog…** to select a printer, change print settings, or save a PDF through the system dialog.

```text
Monday, 9 November

# Schedule
8 Breakfast
845 - 9:30 Walk to the library
1000+45 Draft the project outline
13:30 Lunch with Sam

# To-dos
* Send the outline by 15:00
- Return library books
```

The first nonblank, noncomment line is the title. Put one event or to-do on each subsequent line. Start an event with a 24-hour time, then a space and the event text. A colon is optional. One or two digits give the hour. Three or four digits give the hour and minute, so `8`, `845`, and `1330` mean 08:00, 08:45, and 13:30.

Use `-` for an end time or `+` for a duration in minutes. Spaces around either operator are optional. An end time at or before the start time means the event ends the next day. Overnight events are shown through midnight.

Start to-dos with `-` or use `*` for high priority. Events and to-dos can be interleaved. The PDF groups them into separate sections, sorts events by start time, and keeps to-dos in input order. High-priority items appear in bold on a light gray background.

Lines starting with `#` are comments. The preview skips comments, blank lines, and unrecognized entries. **Format** adds `# Schedule` and `# To-dos` above their sections, writes event times as `HH:MM` or `HH:MM - HH:MM`, capitalizes descriptions, and puts high-priority to-dos first. It moves other comments and unrecognized lines to the end in their original order.

The calendar shows an hourly grid from 08:00 to 18:00 by default and extends to include earlier or later events. Daily tightens spacing when needed and reports an error if the plan still exceeds one page.

A plan without events or to-dos prints as a worksheet with the hourly grid and empty checklist rows for handwriting. An empty draft also leaves room to write the title by hand.

## Run tests

Run `swift test` from this directory. The Swift Testing suites cover the plan format, preview snapshots, PDF layout, and print setup.
