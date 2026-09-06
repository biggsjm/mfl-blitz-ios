import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var credentials = LoginCredentials()
    @State private var showingSignIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    valueCards
                    actions
                    independenceNote
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)
                .readablePageWidth()
            }
            .background {
                LinearGradient(
                    colors: [Color.blitzNavy, Color.blitzNavy.opacity(0.93), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showingSignIn) {
                SignInSheet(credentials: $credentials)
                    .presentationDetents([.large])
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blitzGreen.opacity(0.16))
                    .frame(width: 122, height: 122)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 58, weight: .black))
                    .foregroundStyle(Color.blitzGreen)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            }
            .accessibilityHidden(true)

            VStack(spacing: 9) {
                Text("MFL BLITZ")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .tracking(1.2)
                Text("Deep enough for MFL.\nCalm enough for Sunday.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var valueCards: some View {
        VStack(spacing: 10) {
            BenefitRow(icon: "sportscourt.fill", title: "Scores at a glance", detail: "Your matchup first, with every league score one swipe away.")
            BenefitRow(icon: "checkmark.circle.fill", title: "Deadline-safe actions", detail: "Clear lineup and waiver reviews before anything reaches MFL.")
            BenefitRow(icon: "hand.raised.fill", title: "Private by default", detail: "No ads, no tracking SDK, and your password is never stored.")
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                showingSignIn = true
            } label: {
                Text("Connect MyFantasyLeague")
                    .font(.headline)
                    .foregroundStyle(Color.blitzNavy)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.blitzGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Button {
                Task { await model.continueInDemo() }
            } label: {
                HStack {
                    if model.isBusy { ProgressView() }
                    Text("Preview Champion Hall")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(model.isBusy)
            .accessibilityHint("Opens a safe interactive preview using sample game-day data")
        }
    }

    private var independenceNote: some View {
        Text("Independent companion for MyFantasyLeague.com. Not affiliated with or endorsed by MyFantasyLeague, the NFL, or any NFL team.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.blitzGreen)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct SignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var credentials: LoginCredentials
    @FocusState private var focus: Field?

    enum Field { case username, password, league }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("MFL username", text: $credentials.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                    SecureField("MFL password", text: $credentials.password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                } header: {
                    Text("MyFantasyLeague account")
                } footer: {
                    Text("Credentials are sent directly to MFL over HTTPS. The password and resulting session are kept in memory only and are discarded when you disconnect or close the app.")
                }

                Section("League") {
                    TextField("League ID", text: $credentials.leagueID)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .league)
                    Stepper(value: $credentials.season, in: 2020...Calendar.current.component(.year, from: Date())) {
                        Text(verbatim: "Season \(credentials.season)")
                    }
                }

                Section {
                    PrimaryActionButton(title: "Sign in securely", systemImage: "lock.fill", isBusy: model.isBusy, isDisabled: !isValid) {
                        Task {
                            await model.signIn(credentials: credentials)
                            if model.phase == .signedIn { dismiss() }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Connect MFL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focus = .username }
        }
    }

    private var isValid: Bool {
        !credentials.username.trimmingCharacters(in: .whitespaces).isEmpty
            && !credentials.password.isEmpty
            && credentials.leagueID.count >= 4
    }
}
