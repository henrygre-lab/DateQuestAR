// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Alert cap sourced from BalanceEnforcer (reads server-set values from Firestore)
// [x] The hourly alert cap row is shown only to Dating-gated users, because that
//     is the only case the asymmetric caps apply to
// [x] Intents are changed through the setActiveIntents Cloud Function, never by a
//     direct write — that function is what enforces the Dating gate and starts
//     the 24h Dating-off cooldown, and firestore.rules rejects a client write
// [x] Dating cannot be selected without the student ID <-> liveness face match and
//     a verified adult age, both server-written fields this view only reads
// [x] Vibe tags stored only on user's own Firestore document — no cross-user exposure
// [x] Verification triggers SafetyVerifier which proxies through Cloud Functions
// [x] Global pause respects geo-fence auto-pause zones (server-enforced boundaries)
// [x] School display name is community identity (DESIGN_SYSTEM.md §8); no
//     neighbourhood, venue, building or geohash is rendered
// [x] No PII logged — only enum states, alert limits, and vibe tag labels

import SwiftUI
import MapKit
import FirebaseFunctions

/// DesignSystem v2 skin. Rows, groups and controls come from `DQFormParts`;
/// every setting, gate and destination behaves exactly as before.
struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var matchManager: MatchManager
    @EnvironmentObject var balanceEnforcer: BalanceEnforcer
    @Environment(\.dq) private var p

    @State private var questEnabled = true
    @State private var alertLimit = 5
    @State private var locationMode = PrivacySettings.LocationSharingMode.anonymized
    @State private var showCommunityEvents = true
    @State private var autoZones: [GeoFenceZone] = []
    @State private var showAddZone = false
    @State private var showDeleteAccountConfirm = false
    @State private var selectedVibes: Set<String> = []
    @State private var globalPauseEnabled = false
    @State private var selectedIntents: Set<Intent> = Set(Intent.defaults)

    private let allVibes = [
        "Chill hangout", "Deep conversation", "Adventure buddy",
        "Coffee date", "Group outing", "Creative collab",
        "Workout partner", "Foodie crawl", "Night out",
        "Study buddy", "Dog walk", "Just vibing"
    ]

    private var alertCap: Int {
        max(1, balanceEnforcer.calculateAlertCap(for: authViewModel.currentUser?.gender ?? .preferNotToSay))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                p.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DQSpace.gutter) {
                        DQTopBar(title: "Settings")
                        questSection
                        intentSection
                        balanceAndSafetySection
                        privacySection
                        autoPauseSection
                        safetySection
                        accountSection
                    }
                    .padding(.horizontal, DQSpace.gutter)
                    .padding(.top, DQSpace.safeTop)
                    .padding(.bottom, DQSpace.gutter)
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .ignoresSafeArea(edges: .top)
            .sheet(isPresented: $showAddZone) {
                AddPauseZoneView { zone in
                    autoZones.append(zone)
                    locationService.configureAutoPauseZones(autoZones)
                }
            }
            .sheet(isPresented: $showDeleteAccountConfirm) {
                DQConfirmSheet(
                    title: "Delete Account",
                    message: "This action is permanent and cannot be undone.",
                    confirmTitle: "Delete"
                ) {
                    Task { await authViewModel.deleteAccount() }
                }
            }
            .onAppear {
                if let user = authViewModel.currentUser {
                    alertLimit = balanceEnforcer.calculateAlertCap(for: user.gender)
                    selectedVibes = Set(user.intentVibes)
                    globalPauseEnabled = !matchManager.isQuestModeActive
                    // Seeded from the profile, which is the server's copy. The
                    // toggles must never start from a local guess.
                    selectedIntents = Set(user.activeIntents)
                }
            }
        }
    }

    // MARK: - Quest Mode

    private var questSection: some View {
        VStack(spacing: 0) {
            DQSectionHeader(title: "Quest Mode")
            DQGroup {
                DQRow(label: "Campus", sublabel: campusSublabel) {
                    if let school = authViewModel.currentUser?.schoolDisplayName,
                       !school.isEmpty {
                        DQChip(text: school)
                    }
                }

                DQToggleRow(label: "Quest Mode", isOn: $questEnabled)
                    .onChange(of: questEnabled) { _, val in
                        if val, let user = authViewModel.currentUser {
                            matchManager.enableQuestMode(for: user)
                        } else {
                            matchManager.disableQuestMode()
                        }
                    }

                // Dating-only. Showing an hourly cap to someone on Study would
                // describe a limit that never fires for them.
                if isDatingGated {
                    DQStepperRow(
                        label: "Hourly alert limit",
                        value: $alertLimit,
                        range: 1...alertCap
                    )
                }
            }
        }
    }

    /// Says plainly whether scanning is live, and why not when it isn't.
    private var campusSublabel: String {
        switch locationService.communityScope {
        case .none:            return "Paused — you're off campus"
        case .campus:          return "Scanning your school only"
        case .springBreak(_, let label): return label
        }
    }

    // MARK: - Intents

    private var intentSection: some View {
        VStack(spacing: 0) {
            DQSectionHeader(title: "What you're here for")
            DQGroup {
                ForEach(Intent.allCases) { intent in
                    let locked = intent.requiresFaceMatch && !canUseDating
                    DQToggleRow(
                        label: intent.displayName,
                        sublabel: locked
                            ? "Needs your student ID to match your selfie"
                            : intent.subtitle,
                        isOn: Binding(
                            get: { selectedIntents.contains(intent) },
                            set: { isOn in
                                if isOn { selectedIntents.insert(intent) }
                                else { selectedIntents.remove(intent) }
                                Task { await saveIntents() }
                            }
                        )
                    )
                    .disabled(locked)
                }
            }

            DQFootnote(text: datingFootnote)
        }
    }

    /// Explains the cooldown before it bites, rather than after.
    private var datingFootnote: String {
        guard let user = authViewModel.currentUser else { return "" }
        if user.isInDatingCooldown() {
            return "You turned Dating off recently. Its alert limits stay on for "
                 + "24 hours — that's there so the limits can't be switched off "
                 + "and on to get around them."
        }
        if selectedIntents.contains(.dating) {
            return "Turning Dating off keeps its alert limits for 24 hours."
        }
        return "Dating is optional. Everything else works without it."
    }

    private var canUseDating: Bool {
        authViewModel.currentUser?.canUseDatingIntent ?? false
    }

    private var isDatingGated: Bool {
        authViewModel.currentUser?.isDatingGated() ?? false
    }

    /// Writes intents through the Cloud Function.
    ///
    /// Not a Firestore write: `activeIntents` is server-owned precisely so this
    /// path cannot be bypassed, and it is the function that sets the cooldown.
    private func saveIntents() async {
        do {
            _ = try await Functions.functions()
                .httpsCallable("setActiveIntents")
                .call(["intents": selectedIntents.map(\.rawValue)])
            await authViewModel.reloadProfile()
        } catch {
            // Reflect the server's answer rather than leaving the toggle showing
            // a state the backend refused.
            selectedIntents = Set(authViewModel.currentUser?.activeIntents ?? Intent.defaults)
            Log.app.error("Intent update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Balance & Safety

    private var balanceAndSafetySection: some View {
        let verification = authViewModel.currentUser?.verificationStatus ?? .unverified
        return VStack(spacing: 0) {
            DQSectionHeader(title: "Balance & Safety")
            DQGroup {
                DQToggleRow(
                    label: "Global pause",
                    sublabel: "Pauses all quest scanning and alerts",
                    isOn: $globalPauseEnabled
                )
                .onChange(of: globalPauseEnabled) { _, paused in
                    if paused {
                        matchManager.disableQuestMode()
                    } else if let user = authViewModel.currentUser {
                        matchManager.enableQuestMode(for: user)
                    }
                }

                DQRow(label: "Balance status") {
                    DQChip(text: balanceEnforcer.needsFemaleBoost ? "Balancing" : "Balanced")
                }

                // The trust centre was built and unreachable. It is the right
                // destination for this row now that the tiers describe the campus
                // gate rather than a generic identity ladder.
                NavigationLink {
                    TrustCenterView(
                        tier: authViewModel.currentUser?.trustLevel ?? .bronze,
                        schoolDisplayName: authViewModel.currentUser?.schoolDisplayName,
                        studentIDStatus: authViewModel.currentUser?.studentIDStatus ?? .none
                    )
                } label: {
                    DQRow(label: "Trust & verification", sublabel: verificationSublabel) {
                        if verification == .verified {
                            DQChip(text: "Verified")
                        } else {
                            chevron
                        }
                    }
                }
                .buttonStyle(.plain)

                vibesBlock
            }
        }
    }

    private var vibesBlock: some View {
        VStack(alignment: .leading, spacing: DQSpace.tight) {
            HStack {
                Text("My vibes")
                    .font(DQFont.uiSized(14, .semibold))
                    .foregroundStyle(p.text)
                Spacer(minLength: 0)
                Text("\(selectedVibes.count)")
                    .font(DQFont.monoSized(13, .medium))
                    .foregroundStyle(p.text2)
            }

            FlowLayout(spacing: 7) {
                ForEach(allVibes, id: \.self) { vibe in
                    Button {
                        if selectedVibes.contains(vibe) {
                            selectedVibes.remove(vibe)
                        } else {
                            selectedVibes.insert(vibe)
                        }
                    } label: {
                        DQChip(text: vibe, selected: selectedVibes.contains(vibe))
                            .frame(minHeight: DQSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(vibe)
                    .accessibilityAddTraits(
                        selectedVibes.contains(vibe) ? [.isButton, .isSelected] : .isButton
                    )
                }
            }
        }
        .padding(.vertical, DQFormMetrics.rowVPad)
        .padding(.horizontal, DQFormMetrics.inset)
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(spacing: 0) {
            DQSectionHeader(title: "Privacy")
            DQGroup {
                DQToggleRow(label: "Community events", isOn: $showCommunityEvents)

                NavigationLink {
                    DataRightsView()
                } label: {
                    DQRow(label: "Data rights", sublabel: "GDPR / CCPA") { chevron }
                }
                .buttonStyle(.plain)
            }

            // Segmented pickers stand alone, never inside a group.
            VStack(alignment: .leading, spacing: 7) {
                Text("Location mode")
                    .font(DQFont.labelSized(9.5, .semibold))
                    .tracking(DQFont.track(9.5, em: 0.16))
                    .textCase(.uppercase)
                    .foregroundStyle(p.text2)
                    .padding(.leading, DQFormMetrics.inset)

                DQSegmentedPicker(
                    options: [PrivacySettings.LocationSharingMode.anonymized, .hidden],
                    title: { $0 == .anonymized ? "Anonymized" : "Hidden" },
                    selection: $locationMode
                )
            }
            .padding(.top, DQSpace.gutter)
        }
    }

    // MARK: - Auto-Pause Zones

    private var autoPauseSection: some View {
        VStack(spacing: 0) {
            DQSectionHeader(title: "Auto-Pause Zones")
            DQGroup {
                ForEach(autoZones) { zone in
                    DQRow(label: zone.label) {
                        HStack(spacing: DQSpace.tight) {
                            Text("\(Int(zone.radiusMeters)) m")
                                .font(DQFont.monoSized(13, .medium))
                                .foregroundStyle(p.text2)
                            Toggle("", isOn: Binding(
                                get: { zone.isActive },
                                set: { _ in /* update zone */ }
                            ))
                            .labelsHidden()
                            .tint(p.ember)
                            .fixedSize()
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(zone.label) pause zone, radius \(Int(zone.radiusMeters)) meters")
                }

                Button { showAddZone = true } label: {
                    DQRow(label: "Add zone") { chevron }
                }
                .buttonStyle(.plain)
            }
            DQFootnote(text: "Quest Mode switches off automatically inside these areas.")
        }
    }

    // MARK: - Safety

    private var safetySection: some View {
        let trust = authViewModel.currentUser?.trustLevel ?? .bronze
        return VStack(spacing: 0) {
            DQSectionHeader(title: "Safety")
            DQGroup {
                NavigationLink {
                    ReportUserView(reportedUID: matchManager.nearbyMatchProfile?.uid ?? "")
                } label: {
                    DQRow(label: "Report a user") { chevron }
                }
                .buttonStyle(.plain)

                NavigationLink {
                    comingSoonPlaceholder
                } label: {
                    DQRow(label: "Block list") { chevron }
                }
                .buttonStyle(.plain)

                DQRow(label: "Trust level") {
                    TrustChip(tier: trust)
                }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(spacing: 0) {
            DQSectionHeader(title: "Account")
            DQGroup {
                Button { authViewModel.signOut() } label: {
                    DQRow(label: "Sign out") { chevron }
                }
                .buttonStyle(.plain)

                // §8 / rule 4: destructive actions read as `danger` ink on the
                // row label. The filled danger pill lives only in the confirm
                // step, never here.
                DQDangerRow(
                    label: "Delete account",
                    sublabel: "Permanent and cannot be undone"
                ) {
                    showDeleteAccountConfirm = true
                }
            }
        }
    }

    // MARK: - Helpers

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(p.text3)
    }

    /// States what is actually outstanding, rather than a generic "not verified".
    private var verificationSublabel: String {
        let status = authViewModel.currentUser?.studentIDStatus ?? .none
        if status.isFaceMatched { return "Student ID matched" }
        if status.isIDVerified { return "Match your ID to your selfie for Dating" }
        return "Add your student ID"
    }

    private var comingSoonPlaceholder: some View {
        DQEmptyState(symbol: "hand.raised", title: "Coming soon")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(p.bg.ignoresSafeArea())
    }
}
