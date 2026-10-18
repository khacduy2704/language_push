import SwiftUI

struct WordFormView: View {
    @EnvironmentObject private var library: WordLibrary
    @Environment(\.dismiss) private var dismiss
    let original: SavedWord?
    @State private var word: String
    @State private var partOfSpeech: String
    @State private var meaning: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(original: SavedWord? = nil) {
        self.original = original
        _word = State(initialValue: original?.word ?? "")
        _partOfSpeech = State(initialValue: original?.partOfSpeech ?? "None")
        _meaning = State(initialValue: original?.meaning ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Word")) {
                    TextField("Word", text: $word)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("wordFormWord")
                }
                Section(header: Text("Parts of speech")) {
                    Picker("Parts of speech", selection: $partOfSpeech) {
                        ForEach(["n", "v", "adj", "adv", "None"], id: \.self) { value in
                            Text(LocalizedStringKey(value == "None" ? "None" : value)).tag(value)
                        }
                        if !["n", "v", "adj", "adv", "None"].contains(partOfSpeech) {
                            Text(partOfSpeech).tag(partOfSpeech)
                        }
                    }
                }
                Section(header: Text("Meaning")) {
                    TextEditor(text: $meaning)
                        .frame(minHeight: 100)
                        .accessibilityIdentifier("wordFormMeaning")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
            .disabled(saving)
            .navigationTitle(LocalizedStringKey(original == nil ? "Add Word" : "Edit Word"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey(original == nil ? "Save" : "Update")) {
                        saving = true
                        errorMessage = nil
                        Task {
                            do {
                                try await library.save(
                                    WordDraft(word: word, partOfSpeech: partOfSpeech, meaning: meaning),
                                    id: original?.id
                                )
                                dismiss()
                            } catch {
                                errorMessage = AppLocalization.format("Could not save word. %@", error.localizedDescription)
                            }
                            saving = false
                        }
                    }
                    .disabled(saving)
                    .accessibilityIdentifier("wordFormSave")
                }
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(saving)
    }
}
