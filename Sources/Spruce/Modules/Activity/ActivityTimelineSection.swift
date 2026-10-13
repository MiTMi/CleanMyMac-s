import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Recent activity, grouped by day, newest first.
struct ActivityTimelineSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var showsAll = false

    private let calendar = ActivityMonthly.calendar()
    private let collapsedLimit = 12
    private let expandedLimit = 300

    var body: some View {
        let history = model.history.history
        let days = ActivityTimeline.recent(history, limit: showsAll ? expandedLimit : collapsedLimit, calendar: calendar)
        let now = Date()
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Recent Activity",
                          trailing: history.entries.isEmpty ? nil : CountFormat.items(history.entries.count, singular: "event"))
            if days.isEmpty {
                Text("Scans, cleanups, uninstalls and maintenance runs are listed here as you use Spruce.")
                    .font(SpruceFont.callout)
                    .foregroundStyle(PrismInk(contrast).secondary)
                    .padding(.vertical, Spacing.s)
            } else {
                GlassCard(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(days) { day in
                            ActivityTimelineDayHeader(title: ActivityTimeline.dayTitle(day.day, now: now, calendar: calendar))
                            ForEach(day.entries) { entry in
                                ActivityTimelineRow(entry: entry, time: ActivityTimeline.timeLabel(entry.date, calendar: calendar))
                            }
                        }
                    }
                    .padding(.vertical, Spacing.s)
                }
                if history.entries.count > collapsedLimit {
                    PrismTextButton(title: showsAll ? "Show less" : "Show more",
                                    symbol: showsAll ? "chevron.up" : "chevron.down", module: .activity) {
                        withAnimation(Motion.standard) { showsAll.toggle() }
                    }
                }
            }
        }
    }
}

struct ActivityTimelineDayHeader: View {
    var title: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(title)
            .font(SpruceFont.overline)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(PrismInk(contrast).tertiary)
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ActivityTimelineRow: View {
    var entry: ActivityEntry
    var time: String

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Spacing.m) {
            PrismCategoryBadge(symbol: entry.kind.activitySymbol, module: entry.module, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.summary.isEmpty ? entry.kind.activityTitle : entry.summary)
                    .font(SpruceFont.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(entry.module.title) · \(entry.kind.activityTitle)")
                    .font(SpruceFont.caption)
                    .foregroundStyle(PrismInk(contrast).tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.m)
            if showsBytes {
                SizeBadge(bytes: entry.bytes, module: entry.module)
            }
            Text(time)
                .font(SpruceFont.captionDigits)
                .foregroundStyle(PrismInk(contrast).tertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 6)
        .background(hovering ? Ink.subtleFill : Color.clear)
        .onHover { hovering = $0 }
        .help(entry.summary)
        .accessibilityElement(children: .combine)
    }

    /// Bytes are shown where they mean space that was given back.
    private var showsBytes: Bool {
        guard entry.bytes > 0 else { return false }
        switch entry.kind {
        case .clean, .uninstall, .threatRemoved, .startupItems, .cloudFreed: return true
        default: return false
        }
    }
}

// MARK: - Operations log

/// The append-only log of every file operation, newest first.
struct ActivityOperationsLogSheet: View {
    var onClose: () -> Void

    @State private var lines: [ActivityLogLine] = []
    @State private var query = ""
    @State private var isLoading = true
    @Environment(\.colorSchemeContrast) private var contrast

    private static let lineLimit = 1_000

    var body: some View {
        let filtered = lines.filter { $0.matches(query) }
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Operations Log")
                        .font(SpruceFont.title)
                        .foregroundStyle(Ink.primary)
                    Text("Every item Spruce moved to the Trash or deleted, newest first. It never leaves this Mac.")
                        .font(SpruceFont.callout)
                        .foregroundStyle(PrismInk(contrast).secondary)
                }
                Spacer(minLength: Spacing.m)
                PrismSearchField(text: $query, prompt: "Filter", width: 220)
            }
            logList(filtered)
            HStack(spacing: Spacing.s) {
                CapsuleButton(title: "Show in Finder", symbol: "folder") {
                    revealLog()
                }
                .disabled(lines.isEmpty)
                CapsuleButton(title: "Copy", symbol: "doc.on.doc") {
                    copy(filtered)
                }
                .disabled(filtered.isEmpty)
                Spacer()
                Text(lines.count >= Self.lineLimit ? "Latest \(CountFormat.grouped(Self.lineLimit)) entries" : CountFormat.items(lines.count, singular: "entry", plural: "entries"))
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(PrismInk(contrast).tertiary)
                Button("Done", action: onClose)
                    .buttonStyle(PrismCapsuleButtonStyle(role: .primary, large: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 820, height: 560)
        .task { await load() }
    }

    @ViewBuilder
    private func logList(_ filtered: [ActivityLogLine]) -> some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            Text(lines.isEmpty ? "Nothing has been removed yet." : "No entries match \u{201C}\(query)\u{201D}.")
                .font(SpruceFont.body)
                .foregroundStyle(PrismInk(contrast).secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { line in
                        ActivityLogRow(line: line)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Ink.subtleFill))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Ink.hairline))
            .frame(maxHeight: .infinity)
        }
    }

    private func load() async {
        let limit = Self.lineLimit
        let parsed = await Task.detached(priority: .userInitiated) {
            ActivityLogLine.parseAll(OperationLog.shared.tail(limit))
        }.value
        lines = parsed
        isLoading = false
    }

    private func revealLog() {
        let url = OperationLog.shared.url
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func copy(_ lines: [ActivityLogLine]) {
        let text = lines.map { line in
            [line.dateText, line.module, line.action, line.result, String(line.bytes), line.detail].joined(separator: "\t")
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ActivityLogRow: View {
    var line: ActivityLogLine
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Image(systemName: line.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(line.isSuccess ? StatusColor.success : StatusColor.warning)
            Text(dateLabel)
                .font(SpruceFont.mono)
                .foregroundStyle(PrismInk(contrast).tertiary)
                .frame(width: 128, alignment: .leading)
            Text(line.action.isEmpty ? "—" : "\(line.module) · \(line.action)")
                .font(SpruceFont.mono)
                .foregroundStyle(PrismInk(contrast).secondary)
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)
            Text(line.detail.abbreviatingHome)
                .font(SpruceFont.mono)
                .foregroundStyle(Ink.primary.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: Spacing.s)
            if line.bytes > 0 {
                Text(ByteFormat.string(line.bytes))
                    .font(SpruceFont.captionDigits)
                    .foregroundStyle(PrismInk(contrast).tertiary)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 5)
        .help(line.isSuccess ? line.detail : "\(line.result): \(line.detail)")
    }

    private var dateLabel: String {
        guard let date = line.date else { return line.dateText }
        let calendar = ActivityMonthly.calendar()
        let month = ActivityMonthly.shortName(date, calendar: calendar)
        let day = calendar.component(.day, from: date)
        return "\(month) \(day), \(ActivityTimeline.timeLabel(date, calendar: calendar))"
    }
}
