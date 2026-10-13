import GolfCore
import GolfDesign
import SwiftUI

/// Edit carry distances used for club suggestions. Rows save in longest-carry order.
struct ClubBagView: View {
    @AppStorage(SettingsKey.clubBag) private var clubBagJSON = ""
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ClubBagRules.Row] = []
    @State private var confirmReset = false
    @FocusState private var focusedRow: UUID?

    private var clubs: [ClubDistance]? { ClubBagRules.clubs(from: rows) }

    var body: some View {
        Form {
            Section {
                ForEach($rows) { $row in
                    HStack(spacing: GolfSpacing.s) {
                        TextField("Club", text: $row.name)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focusedRow, equals: row.id)
                            .font(.body.weight(.semibold))
                        TextField("Carry", text: $row.yards)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 80)
                        Text("yd").foregroundStyle(.golfSecondaryText)
                    }
                    .accessibilityElement(children: .contain)
                    .listRowBackground(row.isValid ? nil : GolfPalette.destructive.color.opacity(0.12))
                }
                .onDelete { rows.remove(atOffsets: $0) }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

                Button("Add club", systemImage: "plus") {
                    let row = ClubBagRules.Row(name: "", yards: "")
                    rows.append(row)
                    focusedRow = row.id
                }
            } footer: {
                Text(rows.allSatisfy(\.isValid)
                     ? "Carry distances from 1 to 400 yards. Suggestions use plays-like yardage."
                     : "Each club needs a name and a carry from 1 to 400 yards.")
            }

            Section {
                Button("Reset to default clubs", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Club bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let clubs else { return }
                    clubBagJSON = ClubDistance.encodeBag(clubs)
                    dismiss()
                }
                .disabled(clubs == nil)
            }
        }
        .confirmationDialog("Reset club bag?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                rows = ClubDistance.defaultBag.map(ClubBagRules.Row.init)
            }
        } message: {
            Text("Replace your clubs with the default carry distances. Nothing changes until you save.")
        }
        .onAppear {
            if rows.isEmpty { rows = ClubDistance.decodeBag(clubBagJSON).map(ClubBagRules.Row.init) }
        }
    }
}

#Preview {
    NavigationStack { ClubBagView() }
}
