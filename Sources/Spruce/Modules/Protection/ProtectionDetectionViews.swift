import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

// What the malware scan checks against beyond its own list (Apple's XProtect rules, the
// downloaded threat list, VirusTotal), as the hub and a threat's details show it. Everything
// here reads `ProtectionEngine.detection`; network work happens in the engine, in the
// background.

// MARK: - Hub card

/// Built-in list · Threat list · Apple XProtect · VirusTotal, with a way to Settings.
struct ProtectionDetectionSourcesCard: View {
    @Bindable var screen: ProtectionScreenModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ModuleID.protection.palette.accentText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detection sources")
                            .font(SpruceFont.headline)
                            .foregroundStyle(Ink.primary)
                        Text("What the malware scan checks your files against.")
                            .font(SpruceFont.caption)
                            .foregroundStyle(ink.secondary)
                    }
                    Spacer(minLength: Spacing.s)
                    PrismTextButton(title: "Settings", symbol: "chevron.right", module: .protection) {
                        ProtectionSettingsLink.open(openSettings)
                    }
                    .help("Change detection sources in Settings › Protection")
                }
                HStack(alignment: .top, spacing: Spacing.s) {
                    ProtectionSourceTile(symbol: "list.bullet.rectangle", title: "Built-in list",
                                         value: CountFormat.items(ProtectionThreatCatalog.standard.families.count,
                                                                  singular: "family", plural: "families"),
                                         detail: "Always on", state: true)
                    ProtectionSourceTile(symbol: "arrow.down.circle", title: "Threat list", value: threatListValue,
                                         detail: threatListDetail, state: threatListState,
                                         help: screen.detection.threatList.lastError)
                    ProtectionSourceTile(symbol: "apple.logo", title: "Apple XProtect", value: appleRulesValue,
                                         detail: appleRulesDetail, state: appleRulesState,
                                         help: screen.detection.appleRules?.unavailableReason)
                    ProtectionSourceTile(symbol: "network.badge.shield.half.filled", title: "VirusTotal",
                                         value: virusTotalValue, detail: virusTotalDetail, state: virusTotalState,
                                         help: screen.detection.virusTotalNotice,
                                         actionTitle: screen.detection.hasVirusTotalKey ? nil : "Set Up",
                                         action: { ProtectionSettingsLink.open(openSettings) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Threat list

    private var threatListValue: String {
        let detection = screen.detection
        if !detection.isThreatListEnabled { return "Off" }
        if detection.isCheckingThreatList { return "Checking…" }
        if let updated = detection.threatList.lastUpdated { return "Updated \(DurationFormat.relative(updated))" }
        return "Not downloaded yet"
    }

    private var threatListDetail: String {
        let detection = screen.detection
        guard detection.isThreatListEnabled else { return "Built-in list only" }
        guard detection.threatList.version != nil else { return "Checked once a day" }
        var parts = [CountFormat.items(detection.threatListIndicatorsInUse, singular: "indicator")]
        if detection.threatListRulesInUse > 0 {
            parts.append(CountFormat.items(detection.threatListRulesInUse, singular: "rule"))
        }
        return parts.joined(separator: " · ")
    }

    private var threatListState: Bool? {
        let detection = screen.detection
        guard detection.isThreatListEnabled else { return false }
        if detection.threatList.lastError != nil { return false }
        return detection.threatList.version != nil ? true : nil
    }

    // MARK: Apple XProtect

    private var appleRulesValue: String {
        guard let rules = screen.detection.appleRules else { return "Checking…" }
        guard rules.isAvailable else { return "Unavailable" }
        return CountFormat.items(rules.activeRuleCount, singular: "rule")
    }

    private var appleRulesDetail: String {
        guard let rules = screen.detection.appleRules else { return "Read from macOS" }
        guard rules.isAvailable else { return "Not in use" }
        if let version = rules.version { return "Version \(version)" }
        return "Read from macOS"
    }

    private var appleRulesState: Bool? {
        guard let rules = screen.detection.appleRules else { return nil }
        return rules.isAvailable
    }

    // MARK: VirusTotal

    private var virusTotalValue: String {
        screen.detection.hasVirusTotalKey ? "Connected" : "Not set up"
    }

    private var virusTotalDetail: String {
        let detection = screen.detection
        guard detection.hasVirusTotalKey else { return "Uses your own key" }
        if detection.virusTotalNotice != nil { return "Needs attention" }
        return "\(CountFormat.grouped(detection.virusTotalLookupsLeftToday)) lookups left today"
    }

    private var virusTotalState: Bool? {
        let detection = screen.detection
        guard detection.hasVirusTotalKey else { return nil }
        return detection.virusTotalNotice == nil
    }
}

/// One source on the hub card: symbol, name, where it stands.
struct ProtectionSourceTile: View {
    var symbol: String
    var title: String
    var value: String
    var detail: String
    /// true = working, false = off or a problem, nil = not set up or unknown.
    var state: Bool?
    /// Shown on hover (why a source isn't working).
    var help: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ink.secondary)
                Text(title)
                    .font(SpruceFont.caption.weight(.semibold))
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(dotColor(ink))
                    .frame(width: 7, height: 7)
            }
            Text(value)
                .font(SpruceFont.callout.weight(.medium))
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            HStack(spacing: 4) {
                Text(detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let actionTitle, let action {
                    Spacer(minLength: 0)
                    Button(action: action) {
                        Text(actionTitle)
                            .font(SpruceFont.caption.weight(.semibold))
                            .foregroundStyle(ModuleID.protection.palette.accentText)
                    }
                    .buttonStyle(.plain)
                    .prismLinkPointer()
                }
            }
        }
        .padding(.horizontal, Spacing.s + 2)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(ink.subtleFill))
        .help(help ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }

    private func dotColor(_ ink: PrismInk) -> Color {
        switch state {
        case true?: return StatusColor.success
        case false?: return StatusColor.warning
        case nil: return ink.tertiary
        }
    }
}

// MARK: - VirusTotal on a threat

/// VirusTotal's answer for a threat's file, or a way to ask for it. Only the file's SHA-256
/// is ever sent; the lookup runs in the engine, in the background.
struct ProtectionVirusTotalPanel: View {
    @Bindable var screen: ProtectionScreenModel
    var item: ScanItem

    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ink = PrismInk(contrast)
        let look = presentation
        HStack(alignment: .top, spacing: Spacing.s) {
            Group {
                if look.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: look.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(look.color)
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(look.headline)
                    .font(SpruceFont.callout.weight(.semibold))
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(look.detail)
                    .font(SpruceFont.caption)
                    .foregroundStyle(ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let linkProblem = screen.virusTotalLinkProblems[item.id] {
                    Text(linkProblem)
                        .font(SpruceFont.caption)
                        .foregroundStyle(StatusColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions(look)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s + 2)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(look.color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(look.color.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("VirusTotal")
    }

    @ViewBuilder
    private func actions(_ look: ProtectionVirusTotalLook) -> some View {
        HStack(spacing: Spacing.m) {
            if look.offersCheck {
                PrismTextButton(title: look.checkTitle, symbol: "magnifyingglass", module: .protection) {
                    screen.checkWithVirusTotal(item)
                }
                .help("Sends only this file's SHA-256 fingerprint to VirusTotal, never the file")
            }
            if let setUpTitle = look.setUpTitle {
                PrismTextButton(title: setUpTitle, symbol: "key", module: .protection) {
                    ProtectionSettingsLink.open(openSettings)
                }
                .help("Settings › Protection › VirusTotal")
            }
            PrismTextButton(title: "Open in VirusTotal", symbol: "arrow.up.forward", module: .protection) {
                screen.openInVirusTotal(item)
            }
            .help("Opens this file's page on virustotal.com in your browser")
        }
    }

    /// What to show, from the row's answer, a lookup in progress, a problem or no key.
    private var presentation: ProtectionVirusTotalLook {
        let detection = screen.detection
        let hasKey = detection.hasVirusTotalKey
        let verdict = screen.virusTotalVerdict(for: item)
        let isFresh = verdict.map { $0.isFresh(maxAge: VirusTotalVerdictCache.maxAge(of: $0)) } ?? false
        var look = ProtectionVirusTotalLook()
        look.offersCheck = hasKey && !isFresh
        if !hasKey && !isFresh {
            look.setUpTitle = "Add Your Key"
        } else if hasKey && detection.virusTotalNotice != nil {
            // The key was refused or today's lookups are used up.
            look.setUpTitle = "Open Settings"
        }
        look.checkTitle = verdict == nil ? "Check with VirusTotal" : "Check Again"

        if screen.isCheckingVirusTotal(item) {
            look.isBusy = true
            look.offersCheck = false
            look.headline = "Checking with VirusTotal…"
            look.detail = "Only this file's SHA-256 fingerprint is sent. With a free key, Spruce may wait a little for a free lookup."
            look.color = StatusColor.info
            return look
        }
        if let verdict {
            look.headline = Self.headline(verdict)
            look.detail = Self.detail(verdict) + " Checked \(DurationFormat.relative(verdict.checked))."
            switch verdict.level {
            case .flagged:
                look.symbol = "xmark.shield.fill"
                look.color = StatusColor.danger
            case .someFlags:
                look.symbol = "exclamationmark.shield.fill"
                look.color = StatusColor.warning
            case .clean:
                look.symbol = "checkmark.shield.fill"
                look.color = StatusColor.success
            case .unknown:
                look.symbol = "questionmark.circle"
                look.color = StatusColor.info
            }
            return look
        }
        if let problem = detection.problem(for: item) {
            look.headline = "Couldn't check with VirusTotal"
            look.detail = problem
            look.symbol = "exclamationmark.triangle.fill"
            look.color = StatusColor.warning
            look.checkTitle = "Try Again"
            return look
        }
        if hasKey {
            look.headline = "Not checked with VirusTotal yet"
            look.detail = "See what dozens of security engines say about this file. Only its SHA-256 fingerprint is sent, never the file."
        } else {
            look.headline = "Check with VirusTotal"
            look.detail = "Add your own free VirusTotal key in Settings to see what dozens of security engines say about this file. Only its fingerprint is sent."
        }
        look.symbol = "shield.lefthalf.filled"
        look.color = ModuleID.protection.palette.accentText
        return look
    }

    /// "Flagged by 34 of 72 engines · trojan.adload/macos".
    static func headline(_ verdict: VirusTotalVerdict) -> String {
        guard let label = verdict.threatLabel, verdict.level == .flagged || verdict.level == .someFlags else {
            return verdict.title
        }
        return "\(verdict.title) · \(label)"
    }

    /// The verdict's explanation without the label sentence the headline already shows.
    static func detail(_ verdict: VirusTotalVerdict) -> String {
        var text = verdict.detail
        if let label = verdict.threatLabel, verdict.level == .flagged || verdict.level == .someFlags {
            let sentence = " Most call it \(label)."
            if text.hasSuffix(sentence) { text.removeLast(sentence.count) }
        }
        return text
    }
}

/// How the VirusTotal panel looks right now.
struct ProtectionVirusTotalLook {
    var headline = ""
    var detail = ""
    var symbol = "shield.lefthalf.filled"
    var color: Color = StatusColor.info
    var isBusy = false
    var offersCheck = false
    /// A link to Settings › Protection ("Add Your Key"), nil when not needed.
    var setUpTitle: String?
    var checkTitle = "Check with VirusTotal"
}
