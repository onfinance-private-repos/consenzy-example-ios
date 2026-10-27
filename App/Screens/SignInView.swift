// Sign-in: pick the backend mode and a synthetic demo customer. In a real app this is your normal login; afterwards
// your backend, not the app, decides which customer the Consenzy session is minted for.

import OnFinanceConsenzy
import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var state: AppState
    @State private var customers: [DemoCustomer] = []
    @State private var selectedRef = "CUST-DEMO-0001"
    @State private var actAsGuardian = false
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var selectedCustomer: DemoCustomer? { customers.first { $0.externalRef == selectedRef } }

    var body: some View {
        Form {
            Section {
                Picker("Backend", selection: $state.mode) {
                    ForEach(BackendMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if state.mode == .sessionServer {
                    TextField("Session server URL", text: $state.sessionServerURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Mode")
            } footer: {
                Text(state.mode == .inAppDemo
                     ? "Everything runs in the app with synthetic data. The real SDK code runs against a fake HTTP transport."
                     : "Run consenzy-example-session-server (npm start). From the simulator it is http://localhost:8787.")
            }

            Section("Demo customer") {
                if customers.isEmpty {
                    Button("Load demo customers") { Task { await loadCustomers() } }
                } else {
                    Picker("Customer", selection: $selectedRef) {
                        ForEach(customers) { Text($0.label).tag($0.externalRef) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if selectedCustomer?.actsThroughGuardian == true {
                        Toggle("Sign in as the guardian (acting_as=guardian)", isOn: $actAsGuardian)
                    }
                }
            }

            Section {
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        Text("Sign in as \(selectedRef)")
                        if isBusy { Spacer(); ProgressView() }
                    }
                }
                .disabled(isBusy || customers.isEmpty)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Consenzy example")
        .task { await loadCustomers() }
        .onChange(of: state.mode) { _ in
            customers = []
            errorMessage = nil
            Task { await loadCustomers() }
        }
    }

    private func loadCustomers() async {
        errorMessage = nil
        do {
            customers = try await state.makeClient().demoCustomers()
            if !customers.contains(where: { $0.externalRef == selectedRef }), let first = customers.first {
                selectedRef = first.externalRef
            }
        } catch {
            errorMessage = "Could not load customers: \(error.localizedDescription)"
        }
    }

    private func signIn() async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        let guardian = actAsGuardian && selectedCustomer?.actsThroughGuardian == true
        do {
            try await state.signIn(externalRef: selectedRef, actingAs: guardian ? .guardian : .dataPrincipal)
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }
}
