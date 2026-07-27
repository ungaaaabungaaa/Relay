import SwiftUI

struct RelayQuestionView: View {
    @ObservedObject var model: RelayWatchModel
    @State private var answers: [String: [String]] = [:]

    var body: some View {
        List {
            RelayConnectionBanner(model: model)
            if let question = model.selectedQuestion {
                ForEach(question.questions) { item in
                    Section(item.header) {
                        Text(item.question)
                        ForEach(item.options) { option in
                            Button {
                                answers[item.id] = [option.label]
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(option.label)
                                        Text(option.description)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if answers[item.id] == [option.label] {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .disabled(!canMutate)
                        }
                    }
                }
                Button("Send answer") { submit(question) }
                    .disabled(!canMutate || answers.count != question.questions.count)
                    .accessibilityHint("Sends only the selected Mac-provided answers to Codex")
            } else {
                Text("This question is no longer pending.")
            }
            RelayBackButton(model: model)
        }
    }

    private var canMutate: Bool { model.actionsEnabled && !model.mutationPending }

    private func submit(_ question: RelayQuestion) {
        Task {
            do {
                try await model.answer(question.id, answers: answers)
                model.reportActionSuccess()
                model.show(.inbox)
            } catch { model.reportActionFailure(error) }
        }
    }
}
