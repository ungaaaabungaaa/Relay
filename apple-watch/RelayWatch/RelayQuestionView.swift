import SwiftUI

struct RelayQuestionView: View {
    @ObservedObject var model: RelayWatchModel
    let questionID: String?
    @State private var answers: [String: [String]] = [:]
    @State private var questionIndex = 0

    var body: some View {
        RelayAdaptiveContainer {
            questionContent(scrolling: false)
        } scrolling: {
            questionContent(scrolling: true)
        }
        .onChange(of: questionID) { _, _ in
            questionIndex = 0
            answers = [:]
        }
    }

    @ViewBuilder
    private func questionContent(scrolling: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RelayStatusStrip(connection: model.connection, cacheIsStale: model.cacheIsStale, error: model.error)
            if let question, !question.questions.isEmpty {
                let index = currentIndex(for: question)
                let item = question.questions[index]
                let progress = RelayQuestionProgress(questionCount: question.questions.count)

                Text(progress.title(at: index))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.header)
                    .font(.headline)
                Text(item.question)

                ForEach(item.options) { option in
                    Button {
                        guard canMutate else { return }
                        answers[item.id] = [option.label]
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(option.label)
                                Text(option.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if answers[item.id] == [option.label] {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: RelayWatchStyle.tileCornerRadius))
                    .disabled(!canMutate)
                }

                Button(progress.actionTitle(at: index)) {
                    continueOrSubmit(question, at: index)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!canContinue(question, item: item))
                .accessibilityHint("Sends only the selected Mac-provided answers to Codex")
            } else if question != nil {
                Text("This question has no available answers.")
            } else {
                Text("This question is no longer pending.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(scrolling ? .horizontal : [])
    }

    private var canMutate: Bool { model.actionsEnabled && !model.mutationPending }

    private var question: RelayQuestion? {
        guard let questionID else { return model.selectedQuestion }
        return model.inbox.questions.first { $0.id == questionID }
    }

    private func currentIndex(for question: RelayQuestion) -> Int {
        min(max(questionIndex, 0), question.questions.count - 1)
    }

    private func canContinue(_ question: RelayQuestion, item: RelayQuestion.Item) -> Bool {
        guard canMutate, answers[item.id] != nil else { return false }
        let progress = RelayQuestionProgress(questionCount: question.questions.count)
        guard progress.actionTitle(at: currentIndex(for: question)) == "Send answer" else { return true }
        return progress.canSubmit(
            answeredQuestionIDs: Array(answers.keys),
            requiredIDs: question.questions.map(\.id)
        )
    }

    private func continueOrSubmit(_ question: RelayQuestion, at index: Int) {
        guard canMutate else { return }
        let progress = RelayQuestionProgress(questionCount: question.questions.count)
        if progress.actionTitle(at: index) == "Send answer" {
            guard progress.canSubmit(
                answeredQuestionIDs: Array(answers.keys),
                requiredIDs: question.questions.map(\.id)
            ) else { return }
            submit(question)
        } else {
            questionIndex = min(index + 1, question.questions.count - 1)
        }
    }

    private func submit(_ question: RelayQuestion) {
        guard canMutate else { return }
        Task {
            do {
                let validatedAnswers = try question.validatedAnswers(answers)
                try await model.answer(question.id, answers: validatedAnswers)
                model.reportActionSuccess()
                model.popToRoot()
            } catch { model.reportActionFailure(error) }
        }
    }
}
