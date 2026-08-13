from pathlib import Path

path = Path('apps/ios/CAPlayground/Features/Projects/ProjectsView.swift')
s = path.read_text()

old = '''    @State private var pendingDelete: Entry?
    @State private var deleteOptionsOpen = false
    @State private var deleteFromDevice = true
'''
new = '''    @State private var pendingDelete: Entry?
    @State private var deleteOptionsOpen = false
    @State private var bulkDeleteOpen = false
    @State private var pendingBulkDeleteIDs: Set<String> = []
    @State private var deleteFromDevice = true
'''
if s.count(old) != 1:
    raise SystemExit(f'bulk state anchor count={s.count(old)}')
s = s.replace(old, new, 1)

old = '''            .sheet(isPresented: $importLinkOpen) { importLinkDialog }
            .sheet(isPresented: $deleteOptionsOpen) { deleteOptionsDialog }
            .sheet(isPresented: tosBinding) { tosDialog }
'''
new = '''            .sheet(isPresented: $importLinkOpen) { importLinkDialog }
            .sheet(isPresented: $deleteOptionsOpen) { deleteOptionsDialog }
            .sheet(isPresented: $bulkDeleteOpen) { bulkDeleteOptionsDialog }
            .sheet(isPresented: tosBinding) { tosDialog }
'''
if s.count(old) != 1:
    raise SystemExit(f'bulk sheet anchor count={s.count(old)}')
s = s.replace(old, new, 1)

marker = '''    private var tosDialog: some View {
'''
bulk_dialog = '''    private var bulkDeleteOptionsDialog: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Delete from Device", isOn: $deleteFromDevice)
                    Toggle("Delete from Cloud", isOn: $deleteFromCloud)
                } footer: {
                    Text("Choose where the selected projects should be deleted. This action cannot be undone.")
                }
                if !deleteFromDevice && !deleteFromCloud {
                    Section {
                        Text("Please select at least one location.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Delete \(pendingBulkDeleteIDs.count) Selected Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        bulkDeleteOpen = false
                        pendingBulkDeleteIDs.removeAll()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        Task { await performBulkDelete() }
                    }
                    .disabled(!deleteFromDevice && !deleteFromCloud)
                }
            }
        }
        .presentationDetents([.height(320)])
    }

'''
if s.count(marker) != 1:
    raise SystemExit(f'TOS marker count={s.count(marker)}')
s = s.replace(marker, bulk_dialog + marker, 1)

old = '''    private func bulkDelete() {
        let selected = selectedEntries
        for entry in selected where entry.local != nil && entry.cloud == nil {
            if let local = entry.local { store.delete(local) }
        }
        let complex = selected.first { $0.cloud != nil }
        selectedIDs.removeAll()
        if let complex { confirmDelete(complex) }
    }
'''
new = '''    private func bulkDelete() {
        guard !selectedIDs.isEmpty else { return }
        pendingBulkDeleteIDs = selectedIDs
        deleteFromDevice = true
        deleteFromCloud = false
        bulkDeleteOpen = true
    }

    private func performBulkDelete() async {
        guard !pendingBulkDeleteIDs.isEmpty, deleteFromDevice || deleteFromCloud else { return }
        let entries = mergedEntries.filter { pendingBulkDeleteIDs.contains($0.id) }
        if deleteFromDevice {
            for entry in entries {
                if let local = entry.local { store.delete(local) }
            }
        }
        if deleteFromCloud {
            for entry in entries {
                if let cloud = entry.cloud { await drive.delete(cloud) }
            }
            if drive.connected { await drive.refresh() }
        }
        selectedIDs.removeAll()
        pendingBulkDeleteIDs.removeAll()
        selectMode = false
        bulkDeleteOpen = false
    }
'''
if s.count(old) != 1:
    raise SystemExit(f'bulk function count={s.count(old)}')
s = s.replace(old, new, 1)

path.write_text(s)
Path('.github/projects_bulk_patch.py').unlink()
Path('.github/workflows/projects-bulk-parity.yml').unlink()
