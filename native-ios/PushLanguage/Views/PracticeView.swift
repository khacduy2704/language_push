import SwiftUI

struct PracticeView: View {
    @StateObject private var session: PracticeSession
    @StateObject private var feedback = PracticeFeedback()
    @EnvironmentObject private var library: WordLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var answerFocused: Bool
    @State private var errorMessage: String?
    @State private var isVisible = false

    init(session: PracticeSession) {
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let turn = session.current {
                    Text(LocalizedStringKey(turn.mode == .typing ? "Type the word" : "Flashcard"))
                        .font(.headline)
                        .accessibilityIdentifier("practiceMode")
                    Text("\(session.completedIDs.count)/\(session.words.count) words answered correctly")
                        .font(.footnote).foregroundColor(.secondary)
                    Text(verbatim: "\(turn.word.meaning.isEmpty ? AppLocalization.text("(No meaning)") : turn.word.meaning) (\(turn.word.partOfSpeech))")
                        .font(.title2).multilineTextAlignment(.center)

                    if turn.mode == .typing {
                        Text("\(turn.word.word.count) characters")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("Type the word", text: Binding(
                            get: { session.answer }, set: { session.setAnswer($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($answerFocused)
                        .disabled(session.result != nil || session.recording)
                        .accessibilityIdentifier("practiceAnswer")
                        .submitLabel(.done)
                        .onSubmit { if session.canCheck { check() } }
                        Button("Check") { check() }
                            .disabled(!session.canCheck)
                            .accessibilityIdentifier("practiceCheck")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(session.options.indices, id: \.self) { index in
                                Button {
                                    check(option: index)
                                } label: {
                                    Text(session.options[index])
                                        .frame(maxWidth: .infinity, minHeight: 64)
                                        .foregroundColor(.primary)
                                        .background(optionColor(index))
                                        .cornerRadius(12)
                                }
                                .disabled(session.result != nil || session.recording)
                                .accessibilityIdentifier("practiceOption-\(index)")
                            }
                        }
                    }

                    if let correct = session.result {
                        VStack(spacing: 12) {
                            Text(LocalizedStringKey(correct ? "Correct" : "Incorrect"))
                                .font(.title2).bold()
                                .accessibilityIdentifier("practiceResult")
                            Text("\(turn.word.word) (\(turn.word.partOfSpeech))")
                            Text(turn.word.meaning)
                            if let word = session.recordedWord {
                                Text("Practice score: \(word.practiceScore)/5")
                                    .accessibilityIdentifier("practiceScore")
                                if word.isMastered {
                                    Text("Mastered! This word was moved to Mastered and removed from reminders.")
                                        .accessibilityIdentifier("practiceMastered")
                                }
                            }
                            Button(LocalizedStringKey(session.hasNext ? "Continue" : "Finish")) {
                                advance()
                            }
                            .accessibilityIdentifier("practiceContinue")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(correct ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .cornerRadius(12)
                    }
                }
                if let error = errorMessage ?? feedback.errorMessage {
                    Text(error).foregroundColor(.red)
                }
                if session.recording { ProgressView("Saving practice result...") }
                Text("Listening exercises will be added with pronunciation recording caching.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isVisible = true
            answerFocused = session.current?.mode == .typing
        }
        .onDisappear {
            isVisible = false
            feedback.stop()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { feedback.stop() }
        }
    }

    private func optionColor(_ index: Int) -> Color {
        guard session.result != nil, let turn = session.current else { return Color.secondary.opacity(0.1) }
        if PracticeSession.normalized(session.options[index]) == PracticeSession.normalized(turn.word.word) {
            return Color.green.opacity(0.2)
        }
        return session.selectedOption == index ? Color.red.opacity(0.2) : Color.secondary.opacity(0.1)
    }

    private func check(option: Int? = nil) {
        Task {
            do {
                let correct = try await session.check(option: option) { id, correct in
                    try await library.recordPracticeAnswer(id: id, correct: correct)
                }
                answerFocused = false
                errorMessage = nil
                if isVisible && scenePhase == .active {
                    feedback.play(correct: correct)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func advance() {
        feedback.stop()
        do {
            try session.advance()
            if session.finished {
                dismiss()
            } else {
                answerFocused = session.current?.mode == .typing
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
