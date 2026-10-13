import AppKit
import SpruceCore
import SpruceMac
import SwiftUI

/// Protection: real-time protection, automatic background scans
/// (`ProtectionEngine.backgroundSchedule`), the malware scan depth (`SpruceSettings.scanDepth`)
/// and the detection sources: the downloaded threat list (`threatFeedEnabled`), Apple's
/// XProtect rules (status only) and VirusTotal (the key goes to the Keychain through the
/// engine, never into settings; `virusTotalAutoCheck`).
struct SettingsProtectionTab: View {
    @Bindable var store: SettingsStore
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsTab.storageKey) private var selectedTab: SettingsTab = .protection

    @State private var monitorActive = false
    @State private var noticedCount = 0

    /// The result of the last Check Now.
    @State private var threatListCheck: ProtectionThreatFeedCheckResult?
    @State private var showsRuleNotes = false
    /// The VirusTotal key being typed. It lives only in this field (and in the Keychain once
    /// saved) and is cleared after saving.
    @State private var keyDraft = ""
    @State private var isWorkingOnKey = false
    @State private var keyMessage: SettingsKeyMessage?
    /// VirusTotal couldn't be reached to check the key: offer to save it unchecked.
    @State private var offersSaveAnyway = false

    private var depth: ProtectionScanDepth { ProtectionScanDepth(setting: store.settings.scanDepth) }
    private var detection: ProtectionDetectionState { model.protection.detection }

    var body: some View {
        SettingsPage(tab: .protection) {
            realtimeSection
            automaticSection
            depthSection
            detectionSection
            virusTotalSection
            accessSection
        }
        .task(id: store.settings.realtimeProtection) {
            // The engine follows the setting asynchronously; read its state once it settled.
            try? await Task.sleep(for: .milliseconds(400))
            monitorActive = model.protection.isRealtimeProtectionActive
            noticedCount = model.protection.realtimeEvents.count
        }
        .task { await model.protection.refreshDetectionStatus() }
        .onChange(of: store.settings.threatFeedEnabled) { _, _ in threatListCheck = nil }
        .onChange(of: keyDraft) { _, _ in offersSaveAnyway = false }
    }

    // MARK: Sections

    private var realtimeSection: some View {
        Section {
            SettingsToggleRow(title: "Real-time protection",
                              detail: "Watches the folders malware uses to start with your Mac and alerts you as soon as a new startup item appears. It never removes anything on its own.",
                              symbol: "shield.lefthalf.filled", tint: ModuleID.protection.palette.accentText,
                              isOn: $store.settings.realtimeProtection)
            HStack(spacing: Spacing.s) {
                if store.settings.realtimeProtection {
                    StatusPill(text: monitorActive ? "Watching" : "Starting…", status: monitorActive ? .clear : .info)
                    if noticedCount > 0 {
                        Text(noticedCount == 1 ? "1 new startup item noticed since launch"
                             : "\(noticedCount) new startup items noticed since launch")
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                } else {
                    StatusPill(text: "Off", status: .attention)
                    Text("New startup items won't be checked until you scan.")
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                }
                Spacer()
            }
            SettingsToggleRow(title: "Alert me about threats",
                              detail: "Shows a notification when real-time protection spots something suspicious.",
                              symbol: "bell.badge", isOn: $store.settings.notifyThreats)
                .disabled(!store.settings.realtimeProtection)
        } header: {
            Text("Real-Time Protection")
        } footer: {
            HStack(spacing: 4) {
                Text("More alerts live in")
                Button("Notifications") { selectedTab = .notifications }
                    .buttonStyle(.link)
                Text(".")
            }
        }
    }

    /// Automatic Quick scans. Bound through the Protection screen model, which stores the
    /// choice on the engine (`ProtectionEngine.backgroundSchedule`) and keeps the Protection
    /// hub's own picker in step.
    private var automaticSection: some View {
        let screen = ProtectionScreenModel.shared(for: model.protection)
        let schedule = Binding(
            get: { screen.backgroundSchedule },
            set: { screen.backgroundSchedule = $0 }
        )
        return Section {
            Picker(selection: schedule) {
                ForEach(ProtectionBackgroundSchedule.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                SettingsRowLabel(title: "Background scan", detail: screen.backgroundSchedule.detail,
                                 symbol: "clock.arrow.circlepath", tint: ModuleID.protection.palette.accentText)
            }
        } header: {
            Text("Automatic Scans")
        } footer: {
            Text("Background scans are Quick scans. Any malware scan, including Checkup's, resets the clock. Findings wait for your review in Protection; nothing is removed on its own.")
        }
    }

    private var depthSection: some View {
        Section {
            ForEach(ProtectionScanDepth.allCases) { option in
                SettingsDepthOption(depth: option, isSelected: depth == option) {
                    store.settings.scanDepth = option.rawValue
                }
            }
        } header: {
            Text("Malware Scan Depth")
        } footer: {
            Text("Applies to scans from Protection › Malware Removal. Checkup and background scans always run a Quick scan so they stay light.")
        }
    }

    // MARK: Detection sources

    private var detectionSection: some View {
        let enabled = store.settings.threatFeedEnabled
        let checking = detection.isCheckingThreatList
        return Section {
            SettingsToggleRow(title: "Download threat list",
                              detail: "Adds new threats from Spruce's public list on GitHub, checked at most once a day. It can only add detections, and nothing is removed without you.",
                              symbol: "arrow.down.circle", tint: ModuleID.protection.palette.accentText,
                              isOn: $store.settings.threatFeedEnabled)
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(threatListSummary)
                        .font(SpruceFont.callout)
                        .foregroundStyle(enabled ? Ink.secondary : Ink.tertiary)
                    Text(threatListChecked)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                }
                Spacer()
                if checking {
                    ProgressView().controlSize(.small)
                }
                Button("Check Now", action: checkThreatList)
                    .controlSize(.small)
                    .disabled(!enabled || checking)
            }
            .padding(.leading, 30)
            if let threatListCheck {
                let style = Self.style(of: threatListCheck.outcome)
                SettingsNote(text: threatListCheck.message, symbol: style.symbol, color: style.color)
                    .padding(.leading, 30)
            } else if enabled, let problem = detection.threatList.lastError {
                SettingsNote(text: "The last check didn't work: \(problem)")
                    .padding(.leading, 30)
            }
            appleRulesRow
        } header: {
            Text("Detection Sources")
        } footer: {
            Text("Spruce always checks against its built-in list of \(CountFormat.items(ProtectionThreatCatalog.standard.families.count, singular: "threat family", plural: "threat families")). Apple's XProtect rules are read from macOS, kept current by Apple and checked without going online.")
        }
    }

    private var threatListSummary: String {
        guard store.settings.threatFeedEnabled else { return "Off. Scans use the built-in list only." }
        let status = detection.threatList
        guard status.version != nil else { return "Not downloaded yet" }
        var parts = [status.summary]
        if let updated = status.lastUpdated { parts.append("updated \(DurationFormat.relative(updated))") }
        return parts.joined(separator: " · ")
    }

    private var threatListChecked: String {
        if detection.isCheckingThreatList { return "Checking…" }
        guard let checked = detection.threatList.lastChecked else { return "Not checked yet" }
        return "Last checked \(DurationFormat.relative(checked))"
    }

    /// Check Now: downloads the list whatever the date of the last check. The cached copy
    /// stays in use when it fails.
    private func checkThreatList() {
        threatListCheck = nil
        let engine = model.protection
        Task {
            threatListCheck = await engine.checkThreatListNow()
        }
    }

    private static func style(of outcome: ProtectionThreatFeedCheckResult.Outcome) -> (symbol: String, color: Color) {
        switch outcome {
        case .updated, .upToDate: return ("checkmark.circle.fill", StatusColor.success)
        case .failed: return ("exclamationmark.triangle.fill", StatusColor.warning)
        case .notDue, .turnedOff: return ("info.circle.fill", StatusColor.info)
        }
    }

    /// Apple's XProtect rules: how many Spruce uses, or why it can't.
    private var appleRulesRow: some View {
        let rules = detection.appleRules
        return HStack(alignment: .top, spacing: Spacing.s) {
            SettingsRowLabel(title: "Apple XProtect rules", detail: Self.appleRulesDetail(rules), symbol: "apple.logo",
                             tint: ModuleID.protection.palette.accentText)
            Spacer(minLength: Spacing.s)
            if let rules, !rules.notes.isEmpty {
                Button("Details…") { showsRuleNotes = true }
                    .controlSize(.small)
                    .popover(isPresented: $showsRuleNotes) {
                        SettingsRuleNotes(notes: rules.notes)
                    }
            }
            if let rules {
                StatusPill(text: rules.isAvailable ? "In use" : "Unavailable",
                           status: rules.isAvailable ? .clear : .unavailable)
            } else {
                StatusPill(text: "Checking…", status: .info)
            }
        }
    }

    private static func appleRulesDetail(_ rules: ProtectionAppleRulesStatus?) -> String {
        guard let rules else { return "Reading the rules macOS keeps…" }
        guard rules.isAvailable else { return rules.unavailableReason ?? "Not available on this Mac." }
        var parts = ["\(CountFormat.items(rules.activeRuleCount, singular: "rule")) in use"]
        if rules.skippedRuleCount > 0 { parts.append("\(CountFormat.grouped(rules.skippedRuleCount)) skipped") }
        if let version = rules.version { parts.append("XProtect \(version)") }
        return parts.joined(separator: " · ")
    }

    // MARK: VirusTotal

    private var virusTotalSection: some View {
        let hasKey = detection.hasVirusTotalKey
        return Section {
            HStack(alignment: .top, spacing: Spacing.s) {
                SettingsRowLabel(title: "VirusTotal",
                                 detail: "Only a file's SHA-256 fingerprint is sent, never the file. Uses your own free API key: 4 checks a minute, 500 a day.",
                                 symbol: "network.badge.shield.half.filled", tint: ModuleID.protection.palette.accentText)
                Spacer(minLength: Spacing.s)
                StatusPill(text: hasKey ? "Key saved" : "No key", status: hasKey ? .clear : .unavailable,
                           symbol: hasKey ? "key.fill" : nil)
            }
            HStack(spacing: Spacing.s) {
                SecureField("VirusTotal API key", text: $keyDraft,
                            prompt: Text(hasKey ? "Paste a new key to replace yours" : "Paste your API key"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .font(SpruceFont.mono)
                    .onSubmit { saveKey() }
                    .disabled(isWorkingOnKey)
                if isWorkingOnKey {
                    ProgressView().controlSize(.small)
                }
                Button("Save") { saveKey() }
                    .disabled(trimmedDraft.isEmpty || isWorkingOnKey)
                if hasKey {
                    Button("Remove Key", action: removeKey)
                        .disabled(isWorkingOnKey)
                }
            }
            .controlSize(.small)
            .padding(.leading, 30)
            if let keyMessage {
                HStack(spacing: Spacing.s) {
                    SettingsNote(text: keyMessage.text, symbol: keyMessage.symbol, color: keyMessage.color)
                    if offersSaveAnyway {
                        Button("Save Anyway") { saveKey(validate: false) }
                            .controlSize(.small)
                            .disabled(trimmedDraft.isEmpty || isWorkingOnKey)
                            .help("Saves the key without checking it. Spruce checks it with the first lookup.")
                    }
                }
                .padding(.leading, 30)
            }
            if hasKey, let notice = detection.virusTotalNotice {
                SettingsNote(text: notice)
                    .padding(.leading, 30)
            }
            SettingsToggleRow(title: "Check findings automatically",
                              detail: "After a scan, looks up suspicious and rule-based findings in the background, up to 40 a scan. Known threats aren't looked up.",
                              symbol: "checkmark.shield", isOn: $store.settings.virusTotalAutoCheck)
                .disabled(!hasKey)
        } header: {
            SettingsSectionHeader(title: "VirusTotal", trailing: hasKey ? lookupsLeft : nil)
        } footer: {
            HStack(spacing: 4) {
                Text("Your key is kept only in your keychain. No key yet?")
                Button("Get a free one at virustotal.com") {
                    if let url = URL(string: "https://www.virustotal.com/gui/join-us") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)
            }
        }
    }

    private var lookupsLeft: String {
        let left = detection.virusTotalLookupsLeftToday
        return "\(CountFormat.grouped(left)) of \(CountFormat.grouped(VirusTotalRateLimit.publicAPI.perDay)) lookups left today"
    }

    private var trimmedDraft: String {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks the key with VirusTotal (one lookup of a test file's hash, nothing about this
    /// Mac) and saves it in the Keychain when it's usable. The field is cleared once saved.
    private func saveKey(validate: Bool = true) {
        let key = trimmedDraft
        guard !key.isEmpty, !isWorkingOnKey else { return }
        isWorkingOnKey = true
        keyMessage = nil
        offersSaveAnyway = false
        let engine = model.protection
        Task {
            let check = await engine.saveVirusTotalKey(key, validate: validate)
            isWorkingOnKey = false
            if check.isUsable { keyDraft = "" }
            keyMessage = SettingsKeyMessage(check)
            if case .failed = check { offersSaveAnyway = true }
        }
    }

    private func removeKey() {
        guard !isWorkingOnKey else { return }
        isWorkingOnKey = true
        keyMessage = nil
        offersSaveAnyway = false
        let engine = model.protection
        Task {
            await engine.removeVirusTotalKey()
            isWorkingOnKey = false
            keyMessage = SettingsKeyMessage(text: "Your key was removed from the keychain.", tone: .success)
        }
    }

    // MARK: Coverage

    @ViewBuilder
    private var accessSection: some View {
        if !model.hasFullDiskAccess {
            Section {
                HStack(spacing: Spacing.m) {
                    SettingsNote(text: "Without Full Disk Access, some locations, such as Mail downloads and other apps' containers, can't be checked.",
                                 symbol: "lock.fill")
                    Button("Open System Settings") { Permissions.openFullDiskAccessSettings() }
                        .controlSize(.small)
                }
            } header: {
                Text("Coverage")
            }
        }
    }
}

/// The outcome of saving or removing the VirusTotal key, as a note under the field.
private struct SettingsKeyMessage: Equatable {
    enum Tone: Equatable {
        case success, warning, problem
    }

    var text: String
    var tone: Tone

    init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    init(_ check: VirusTotalKeyCheck) {
        let tone: Tone
        switch check {
        case .valid, .quotaReached, .notChecked: tone = .success
        case .failed: tone = .warning
        case .invalid, .malformed: tone = .problem
        }
        self.init(text: check.message, tone: tone)
    }

    var symbol: String {
        switch tone {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch tone {
        case .success: return StatusColor.success
        case .warning: return StatusColor.warning
        case .problem: return StatusColor.danger
        }
    }
}

/// The XProtect rules Spruce doesn't use, and why (Settings › Protection › Details…).
private struct SettingsRuleNotes: View {
    var notes: [String]

    /// More lines than anyone reads in a popover.
    private static let maxLines = 300

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Rules Spruce skips")
                .font(SpruceFont.bodyStrong)
                .foregroundStyle(Ink.primary)
            Text("Spruce reads Apple's rules with its own engine. Rules that use something it doesn't support, or that match ordinary files, are skipped; all the others are used as they are.")
                .font(SpruceFont.caption)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(notes.prefix(Self.maxLines).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(SpruceFont.mono)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if notes.count > Self.maxLines {
                        Text("…and \(CountFormat.grouped(notes.count - Self.maxLines)) more")
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                }
                .textSelection(.enabled)
            }
        }
        .padding(Spacing.l)
        .frame(width: 440, height: 320)
    }
}

/// One selectable scan depth with its coverage, speed and purpose.
private struct SettingsDepthOption: View {
    var depth: ProtectionScanDepth
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        let accent = ModuleID.protection.palette.accent
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.m) {
                ZStack {
                    Circle().strokeBorder(isSelected ? accent : Color.white.opacity(0.42), lineWidth: 1.5)
                    if isSelected {
                        Circle().fill(accent).padding(4)
                    }
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Spacing.s) {
                        Text(depth.title).font(SpruceFont.bodyStrong).foregroundStyle(Ink.primary)
                        if depth == .balanced {
                            PrismChip(text: "Recommended", color: StatusColor.success)
                        }
                        Spacer()
                        Label(depth.speed, systemImage: "clock")
                            .font(SpruceFont.caption)
                            .foregroundStyle(Ink.tertiary)
                    }
                    Text(depth.coverage)
                        .font(SpruceFont.callout)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(depth.purpose)
                        .font(SpruceFont.caption)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.10) : (hovering ? Ink.subtleFill : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
