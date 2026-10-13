import SpruceCore
import SpruceMac
import SwiftUI

/// The in-app Notification Center: alerts, reminders and results kept for later.
/// Opened from the bell in the sidebar (or ⇧⌘N).
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast

    private var inbox: InboxStore { model.inbox }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
                .padding(.bottom, Spacing.s)
            Divider().overlay(Ink.hairline)
            if inbox.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xxs, pinnedViews: []) {
                        section("Today", items: inbox.items.filter { Calendar.current.isDateInToday($0.date) })
                        section("Earlier", items: inbox.items.filter { !Calendar.current.isDateInToday($0.date) })
                    }
                    .padding(.vertical, Spacing.s)
                }
                .frame(maxHeight: 440)
            }
        }
        .frame(width: 360)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Text("Notifications")
                .font(SpruceFont.headline)
                .foregroundStyle(Ink.primary)
            Spacer()
            Button("Mark All Read") { inbox.markAllRead() }
                .buttonStyle(.plain)
                .font(SpruceFont.caption.weight(.medium))
                .foregroundStyle(inbox.hasUnread ? Ink.secondary : Ink.disabled)
                .disabled(!inbox.hasUnread)
            Button("Clear All") { inbox.clearAll() }
                .buttonStyle(.plain)
                .font(SpruceFont.caption.weight(.medium))
                .foregroundStyle(inbox.items.isEmpty ? Ink.disabled : Ink.secondary)
                .disabled(inbox.items.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: "bell.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(PrismInk(contrast).tertiary)
            Text("You're all caught up")
                .font(SpruceFont.bodyStrong)
                .foregroundStyle(Ink.primary)
            Text("Alerts, reminders and finished cleanups appear here.")
                .font(SpruceFont.caption)
                .foregroundStyle(PrismInk(contrast).secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
        .padding(.horizontal, Spacing.l)
    }

    @ViewBuilder
    private func section(_ title: String, items: [InboxItem]) -> some View {
        if !items.isEmpty {
            SectionHeader(title: title)
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xxs)
            ForEach(items) { item in
                InboxRow(item: item) {
                    open(item)
                } onDismiss: {
                    inbox.remove(id: item.id)
                }
            }
        }
    }

    private func open(_ item: InboxItem) {
        inbox.markRead(id: item.id)
        model.showsInbox = false
        if let raw = item.module, let module = ModuleID(rawValue: raw) {
            model.open(module, tool: item.tool)
        }
    }
}

private struct InboxRow: View {
    var item: InboxItem
    var onOpen: () -> Void
    var onDismiss: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.14), in: Circle())
                if !item.isRead {
                    Circle()
                        .fill(StatusColor.info)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: -1)
                        .accessibilityLabel("Unread")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(item.isRead ? SpruceFont.body : SpruceFont.bodyStrong)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.s)
                    Text(item.date, format: .relative(presentation: .named))
                        .font(SpruceFont.caption)
                        .foregroundStyle(PrismInk(contrast).tertiary)
                        .lineLimit(1)
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(SpruceFont.caption)
                        .foregroundStyle(PrismInk(contrast).secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if hovering {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 18, height: 18)
                        .background(Ink.controlFill, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss \(item.title)")
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(hovering ? Ink.subtleFill : Color.clear)
        }
        .padding(.horizontal, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Dismiss", onDismiss)
    }

    private var tint: Color {
        switch item.kind {
        case .alert: return StatusColor.warning
        case .reminder: return StatusColor.info
        case .result: return StatusColor.success
        case .tip: return Ink.secondary
        }
    }
}
