import SwiftUI
import MapKit

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var matchManager: MatchManager

    @State private var questEnabled = true
    @State private var alertLimit = 5
    @State private var locationMode = PrivacySettings.LocationSharingMode.anonymized
    @State private var showCommunityEvents = true
    @State private var autoZones: [GeoFenceZone] = []
    @State private var showAddZone = false
    @State private var showDeleteAccountAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DQ.Spacing.xxl) {
                    questSection
                    privacySection
                    autoPauseSection
                    safetySection
                    accountSection
                }
                .padding(.horizontal, DQ.Spacing.xl)
                .padding(.vertical, DQ.Spacing.lg)
            }
            .dqBackground(heroGlow: true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DQ.Colors.textPrimary)
                }
            }
            .sheet(isPresented: $showAddZone) {
                AddPauseZoneView { zone in
                    autoZones.append(zone)
                    locationService.configureAutoPauseZones(autoZones)
                }
            }
            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                Button("Delete", role: .destructive) {
                    Task { await authViewModel.deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action is permanent and cannot be undone.")
            }
        }
    }

    // MARK: - Section Container

    private func settingsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DQ.Spacing.lg) {
            Text(title.uppercased())
                .font(DQ.Typography.sectionLabel())
                .foregroundStyle(DQ.Colors.textQuaternary)
                .tracking(1)
                .padding(.leading, DQ.Spacing.xxxs)

            VStack(spacing: 1) {
                content()
            }
            .background(DQ.Colors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.large))
            .overlay(
                RoundedRectangle(cornerRadius: DQ.Radii.large)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - Row Helpers

    private func settingsRow<Content: View>(
        icon: String,
        iconColor: Color = DQ.Colors.accent,
        title: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: DQ.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DQ.Radii.small)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .font(DQ.Typography.settingTitle())
                .foregroundStyle(DQ.Colors.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, DQ.Spacing.lg)
        .padding(.vertical, DQ.Spacing.md)
        .background(DQ.Colors.surfaceCard)
    }

    private func settingsNavRow(icon: String, iconColor: Color = DQ.Colors.accent, title: String, destination: some View) -> some View {
        NavigationLink {
            destination
        } label: {
            settingsRow(icon: icon, iconColor: iconColor, title: title) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DQ.Colors.textQuaternary)
            }
        }
    }

    // MARK: - Quest Mode Section

    private var questSection: some View {
        settingsSection(title: "Quest Mode") {
            settingsRow(icon: "location.north.circle.fill", iconColor: DQ.Colors.accent, title: "Quest Mode") {
                Toggle("", isOn: $questEnabled)
                    .labelsHidden()
                    .tint(DQ.Colors.accent)
                    .onChange(of: questEnabled) { _, val in
                        if val, let user = authViewModel.currentUser {
                            matchManager.enableQuestMode(for: user)
                        } else {
                            matchManager.disableQuestMode()
                        }
                    }
                    .accessibilityLabel("Quest Mode")
            }

            Divider().opacity(0.1)

            settingsRow(icon: "bell.badge.fill", iconColor: DQ.Colors.warning, title: "Daily Alert Limit") {
                HStack(spacing: DQ.Spacing.md) {
                    Button {
                        if alertLimit > 1 { alertLimit -= 1 }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DQ.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(DQ.Colors.surfaceElevated)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Decrease alert limit")

                    Text("\(alertLimit)")
                        .font(DQ.Typography.bodyBold())
                        .foregroundStyle(DQ.Colors.textPrimary)
                        .frame(minWidth: 24)

                    Button {
                        if alertLimit < 20 { alertLimit += 1 }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DQ.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(DQ.Colors.surfaceElevated)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Increase alert limit")
                }
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        settingsSection(title: "Privacy") {
            settingsRow(icon: "location.slash.fill", iconColor: DQ.Colors.info, title: "Location Mode") {
                Picker("", selection: $locationMode) {
                    Text("Anonymized").tag(PrivacySettings.LocationSharingMode.anonymized)
                    Text("Hidden").tag(PrivacySettings.LocationSharingMode.hidden)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            Divider().opacity(0.1)

            settingsRow(icon: "person.3.fill", iconColor: DQ.Colors.accentPink, title: "Community Events") {
                Toggle("", isOn: $showCommunityEvents)
                    .labelsHidden()
                    .tint(DQ.Colors.accent)
                    .accessibilityLabel("Show in community events")
            }

            Divider().opacity(0.1)

            settingsNavRow(
                icon: "doc.text.fill",
                iconColor: DQ.Colors.textTertiary,
                title: "Data Rights (GDPR/CCPA)",
                destination: DataRightsView()
            )
        }
    }

    // MARK: - Auto-Pause Section

    private var autoPauseSection: some View {
        settingsSection(title: "Auto-Pause Zones") {
            ForEach(autoZones) { zone in
                VStack(spacing: 0) {
                    settingsRow(icon: "mappin.circle.fill", iconColor: DQ.Colors.accentOrange, title: zone.label) {
                        HStack(spacing: DQ.Spacing.xs) {
                            Text("\(Int(zone.radiusMeters))m")
                                .font(DQ.Typography.caption())
                                .foregroundStyle(DQ.Colors.textQuaternary)
                            Toggle("", isOn: Binding(
                                get: { zone.isActive },
                                set: { _ in /* update zone */ }
                            ))
                            .labelsHidden()
                            .tint(DQ.Colors.accent)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(zone.label) pause zone, radius \(Int(zone.radiusMeters)) meters")
                    Divider().opacity(0.1)
                }
            }

            Button {
                showAddZone = true
            } label: {
                HStack(spacing: DQ.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DQ.Radii.small)
                            .fill(DQ.Colors.accent.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DQ.Colors.accent)
                    }
                    Text("Add Zone")
                        .font(DQ.Typography.settingTitle())
                        .foregroundStyle(DQ.Colors.accent)
                    Spacer()
                }
                .padding(.horizontal, DQ.Spacing.lg)
                .padding(.vertical, DQ.Spacing.md)
                .background(DQ.Colors.surfaceCard)
            }
        }
    }

    // MARK: - Safety Section

    private var safetySection: some View {
        settingsSection(title: "Safety") {
            settingsNavRow(
                icon: "exclamationmark.bubble.fill",
                iconColor: DQ.Colors.error,
                title: "Report a User",
                destination: ReportUserView(reportedUID: matchManager.nearbyMatchProfile?.uid ?? "")
            )
            Divider().opacity(0.1)
            settingsNavRow(
                icon: "hand.raised.slash.fill",
                iconColor: DQ.Colors.warning,
                title: "Block List",
                destination: Text("Coming soon")
                    .font(DQ.Typography.body())
                    .foregroundStyle(DQ.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dqBackground()
            )
            Divider().opacity(0.1)

            // Verification / Trust Level
            let trust = authViewModel.currentUser?.trustLevel ?? .bronze
            settingsRow(
                icon: "shield.fill",
                iconColor: DQ.Colors.trustColor(for: trust),
                title: "Trust Level"
            ) {
                TrustBadgeView(trustLevel: trust, size: .medium)
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        settingsSection(title: "Account") {
            Button {
                authViewModel.signOut()
            } label: {
                settingsRow(icon: "arrow.right.square.fill", iconColor: DQ.Colors.textTertiary, title: "Sign Out") {
                    EmptyView()
                }
            }
            Divider().opacity(0.1)
            Button {
                showDeleteAccountAlert = true
            } label: {
                settingsRow(icon: "trash.fill", iconColor: DQ.Colors.error, title: "Delete Account") {
                    EmptyView()
                }
            }
            .accessibilityHint("This action is permanent and cannot be undone")
        }
    }
}

// MARK: - Add Pause Zone

struct AddPauseZoneView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (GeoFenceZone) -> Void
    @State private var label = ""
    @State private var radius = 200.0

    var body: some View {
        NavigationStack {
            VStack(spacing: DQ.Spacing.xxl) {
                DQTextField(label: "Zone name",
                            placeholder: "Zone name (e.g. Home)", text: $label,
                            isSecure: false)

                VStack(alignment: .leading, spacing: DQ.Spacing.xs) {
                    Text("Radius")
                        .font(DQ.Typography.sectionLabel())
                        .foregroundStyle(DQ.Colors.textQuaternary)
                        .tracking(0.5)
                        .textCase(.uppercase)
                    HStack(spacing: DQ.Spacing.md) {
                        Button {
                            if radius > 50 { radius -= 50 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DQ.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(DQ.Colors.surfaceElevated)
                                .clipShape(Circle())
                        }
                        Text("\(Int(radius))m")
                            .font(DQ.Typography.bodyBold())
                            .foregroundStyle(DQ.Colors.textPrimary)
                            .frame(minWidth: 48)
                        Button {
                            if radius < 500 { radius += 50 }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DQ.Colors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(DQ.Colors.surfaceElevated)
                                .clipShape(Circle())
                        }
                    }
                }

                Text("Your exact location is never stored — zones use anonymized geohashes.")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.textQuaternary)

                Spacer()
            }
            .padding(DQ.Spacing.xl)
            .dqBackground()
            .navigationTitle("Add Pause Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DQ.Colors.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let zone = GeoFenceZone(label: label,
                                                geohash: LocationService.shared.currentGeohash ?? "",
                                                radiusMeters: radius, isActive: true)
                        onAdd(zone)
                        dismiss()
                    }
                    .disabled(label.isEmpty)
                    .foregroundStyle(label.isEmpty ? DQ.Colors.textQuaternary : DQ.Colors.accent)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Report User View

struct ReportUserView: View {
    var reportedUID: String

    @StateObject private var verifier = SafetyVerifier()
    @State private var selectedReason: SafetyVerifier.ReportReason = .fakeProfile
    @State private var details = ""
    @State private var submitted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQ.Spacing.xxl) {
                Text("Report a User")
                    .font(DQ.Typography.sectionHeader())
                    .foregroundStyle(DQ.Colors.textPrimary)

                VStack(alignment: .leading, spacing: DQ.Spacing.xs) {
                    Text("REASON")
                        .font(DQ.Typography.sectionLabel())
                        .foregroundStyle(DQ.Colors.textQuaternary)
                        .tracking(0.5)
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(SafetyVerifier.ReportReason.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DQ.Colors.accent)
                    .padding(DQ.Spacing.md)
                    .background(DQ.Colors.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                }

                VStack(alignment: .leading, spacing: DQ.Spacing.xs) {
                    Text("DETAILS")
                        .font(DQ.Typography.sectionLabel())
                        .foregroundStyle(DQ.Colors.textQuaternary)
                        .tracking(0.5)
                    TextEditor(text: $details)
                        .frame(height: 100)
                        .padding(DQ.Spacing.xs)
                        .background(DQ.Colors.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                        .foregroundStyle(DQ.Colors.textPrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DQ.Radii.medium)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .accessibilityLabel("Report details")
                }

                if submitted {
                    Label("Report submitted. Thank you.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DQ.Colors.success)
                        .font(DQ.Typography.bodyBold())
                } else {
                    Button("Submit Report") {
                        Task {
                            await verifier.reportUser(reportedUID: reportedUID,
                                                      reason: selectedReason, details: details)
                            submitted = true
                        }
                    }
                    .buttonStyle(.dqPrimary)
                }
                Spacer()
            }
            .padding(DQ.Spacing.xl)
        }
        .dqBackground()
    }
}

// MARK: - Data Rights View

struct DataRightsView: View {
    @State private var showComingSoon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQ.Spacing.xxl) {
                Text("Your Data Rights")
                    .font(DQ.Typography.sectionHeader())
                    .foregroundStyle(DQ.Colors.textPrimary)
                Text("Under CCPA and GDPR, you have the right to access, correct, and delete your personal data.")
                    .font(DQ.Typography.body())
                    .foregroundStyle(DQ.Colors.textSecondary)
                Button("Request My Data Export") { showComingSoon = true }
                    .buttonStyle(.dqSecondary)
                Button("Delete All My Data") { showComingSoon = true }
                    .buttonStyle(.dqSecondary)
            }
            .padding(DQ.Spacing.xl)
        }
        .dqBackground()
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This feature is not yet available.")
        }
    }
}
