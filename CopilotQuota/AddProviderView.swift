import SwiftUI

/// Inline view for adding a new provider or editing an existing API-key provider.
struct AddProviderView: View {
    @ObservedObject var coordinator: QuotaCoordinator
    var editingAccount: ProviderAccount?
    var initialKind: ProviderKind?
    var onDismiss: () -> Void

    @State private var selectedKind: ProviderKind?
    @State private var apiKey = ""
    @State private var displayName = ""
    @State private var glmRegion: GLMRegion = .cn
    @State private var capText = ""
    @State private var warningText = ""
    @State private var criticalText = ""

    init(
        coordinator: QuotaCoordinator,
        editingAccount: ProviderAccount? = nil,
        initialKind: ProviderKind? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.editingAccount = editingAccount
        self.initialKind = initialKind
        self.onDismiss = onDismiss
        _selectedKind = State(initialValue: editingAccount?.kind ?? initialKind)
        _displayName = State(initialValue: editingAccount?.displayName ?? "")
        _glmRegion = State(initialValue: editingAccount?.glmRegion ?? .cn)
        _capText = State(initialValue: editingAccount?.balanceReferenceCap.map { String(format: "%.0f", $0) } ?? "")
        _warningText = State(initialValue: editingAccount?.warningThreshold.map { String(format: "%.0f", $0) } ?? "")
        _criticalText = State(initialValue: editingAccount?.criticalThreshold.map { String(format: "%.0f", $0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editingAccount != nil ? L("Edit Provider") : L("Add Provider"))
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .linkCursor()
            }

            if let kind = selectedKind {
                if kind == .copilot {
                    DeviceFlowView(
                        coordinator: coordinator,
                        onComplete: onDismiss,
                        onCancel: {
                            if editingAccount != nil || initialKind != nil {
                                onDismiss()
                            } else {
                                selectedKind = nil
                            }
                        }
                    )
                } else {
                    apiKeyForm(for: kind)
                }
            } else {
                providerPicker
            }
        }
    }

    private var providerPicker: some View {
        VStack(spacing: 8) {
            ForEach(ProviderKind.allCases) { kind in
                let alreadyAdded = coordinator.accounts.contains(where: { $0.kind == kind })
                Button {
                    selectedKind = kind
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.primary.opacity(0.06))
                            ProviderGlyphView(kind: kind, size: 18)
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.displayName)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(subtitle(for: kind))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if alreadyAdded {
                            Text(L("Added"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(alreadyAdded)
                .opacity(alreadyAdded ? 0.55 : 1.0)
                .linkCursor()
            }

            // Placeholder note for Google AI Pro (v2.1).
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(L("Google AI Pro support is planned for v2.1."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)
        }
    }

    private func apiKeyForm(for kind: ProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderGlyphView(kind: kind, size: 18)
                Text(kind.displayName)
                    .font(.subheadline.weight(.semibold))
            }

            if kind == .glm {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Region"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(L("Region"), selection: $glmRegion) {
                        ForEach(GLMRegion.allCases) { region in
                            Text(region.displayName).tag(region)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(editingAccount != nil ? L("API Key (leave blank to keep existing)") : L("API Key"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField(apiKeyPlaceholder(for: kind), text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if kind.isBalanceBased {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Ring display options (optional)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Reference cap (%@)", kind.defaultCurrencySymbol))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            TextField("100", text: $capText)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Low (%@)", kind.defaultCurrencySymbol))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            TextField("10", text: $warningText)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Critical (%@)", kind.defaultCurrencySymbol))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            TextField("5", text: $criticalText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    Text(L("Leave cap blank for a full ring that turns orange/red below your thresholds."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                if editingAccount == nil && initialKind == nil {
                    Button(L("Back")) { selectedKind = nil }
                        .buttonStyle(.link)
                        .font(.caption)
                        .linkCursor()
                }
                Spacer()
                Button(L("Cancel")) { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editingAccount != nil ? L("Save") : L("Add")) {
                    submitAPIKey(for: kind)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editingAccount == nil && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
    }

    private func submitAPIKey(for kind: ProviderKind) {
        let cap = Double(capText.trimmingCharacters(in: .whitespacesAndNewlines))
        let warning = Double(warningText.trimmingCharacters(in: .whitespacesAndNewlines))
        let critical = Double(criticalText.trimmingCharacters(in: .whitespacesAndNewlines))
        let regionValue = kind == .glm ? glmRegion.rawValue : nil

        if var existing = editingAccount {
            existing.region = regionValue
            existing.balanceReferenceCap = cap
            existing.warningThreshold = warning
            existing.criticalThreshold = critical
            coordinator.updateAccount(existing, newAPIKey: apiKey.isEmpty ? nil : apiKey)
        } else {
            coordinator.addAPIKeyAccount(
                kind: kind,
                apiKey: apiKey,
                displayName: displayName.isEmpty ? nil : displayName,
                region: regionValue,
                balanceReferenceCap: cap,
                warningThreshold: warning,
                criticalThreshold: critical
            )
        }
        onDismiss()
    }

    private func subtitle(for kind: ProviderKind) -> String {
        switch kind {
        case .copilot: return L("OAuth Device Flow · Monthly premium requests")
        case .deepseek: return L("API Key · Prepaid balance (CNY / USD)")
        case .openrouter: return L("API Key · Prepaid credits (USD)")
        case .glm: return L("API Key · 5h & weekly rolling windows")
        }
    }

    private func apiKeyPlaceholder(for kind: ProviderKind) -> String {
        switch kind {
        case .deepseek: return "sk-..."
        case .openrouter: return "sk-or-v1-..."
        case .glm: return "id.secret"
        case .copilot: return ""
        }
    }
}
