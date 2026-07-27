import Foundation

struct RelayPage<Element: Codable & Sendable>: Codable, Sendable {
    let data: [Element]
    let nextCursor: String?
}

extension RelayPage: Equatable where Element: Equatable {}

struct RelayTask: Codable, Equatable, Sendable, Identifiable {
    enum Status: String, Codable, Equatable, Sendable {
        case idle, running, error, offline
    }

    let id: String
    let title: String
    let preview: String
    let cwd: String
    let updatedAt: Int64
    let status: Status
}

struct RelayTaskDetail: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let preview: String
    let cwd: String
    let updatedAt: Int64
    let status: RelayTask.Status
    let activeTurnId: String?
    let activity: [RelayActivity]
}

struct RelayActivity: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Equatable, Sendable {
        case user, assistant, command, file, tool, status
    }

    enum Status: String, Codable, Equatable, Sendable {
        case pending, running, succeeded, failed, unknown
    }

    let id: String
    let turnId: String
    let kind: Kind
    let title: String
    let detail: String?
    let status: Status
    let occurredAt: Int64?
}

struct RelayInbox: Codable, Equatable, Sendable {
    let approvals: [RelayApproval]
    let questions: [RelayQuestion]
}

struct RelayApproval: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Equatable, Sendable {
        case command, file, permission
    }

    enum Risk: String, Codable, Equatable, Sendable {
        case normal, dangerous
    }

    let id: String
    let threadId: String
    let turnId: String
    let itemId: String
    let kind: Kind
    let risk: Risk
    let riskReasons: [String]
    let command: String?
    let cwd: String?
    let reason: String?
    let startedAtMs: Int64
}

struct RelayQuestion: Codable, Equatable, Sendable, Identifiable {
    struct Item: Codable, Equatable, Sendable, Identifiable {
        struct Option: Codable, Equatable, Sendable, Identifiable {
            let label: String
            let description: String

            var id: String { label }
        }

        let id: String
        let header: String
        let question: String
        let options: [Option]
    }

    let id: String
    let threadId: String
    let turnId: String
    let itemId: String
    let questions: [Item]

    func validatedAnswers(_ answers: [String: [String]]) throws -> [String: [String]] {
        guard answers.count == questions.count else {
            throw RelayQuestionAnswerError.incompleteAnswers
        }

        for question in questions {
            guard let selected = answers[question.id], !selected.isEmpty else {
                throw RelayQuestionAnswerError.incompleteAnswers
            }
            let allowed = Set(question.options.map(\.label))
            guard selected.allSatisfy(allowed.contains) else {
                throw RelayQuestionAnswerError.invalidOption
            }
        }
        guard answers.keys.allSatisfy({ answerID in questions.contains { $0.id == answerID } }) else {
            throw RelayQuestionAnswerError.unknownQuestion
        }
        return answers
    }
}

enum RelayQuestionAnswerError: Error, Equatable, Sendable {
    case incompleteAnswers, unknownQuestion, invalidOption
}

struct RelayModel: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
    let efforts: [String]
    let defaultEffort: String
    let isDefault: Bool
}

struct RelayFolder: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Equatable, Sendable {
        case root, directory
    }

    let name: String
    let path: String
    let kind: Kind

    var id: String { path }
}

struct RelayFolderListing: Codable, Equatable, Sendable {
    let path: String?
    let entries: [RelayFolder]
}

struct RelayEvent: Codable, Equatable, Sendable, Identifiable {
    let id: Int
    let type: String
    let data: RelayJSONValue
    let createdAt: Int64
}

enum RelayJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([RelayJSONValue])
    case object([String: RelayJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RelayJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: RelayJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Relay event data")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

struct RelayTranscription: Codable, Equatable, Sendable {
    let transcript: String
}

struct RelayMutationAcknowledgement: Codable, Equatable, Sendable {
    let ok: Bool
}

struct RelayTaskMutationAcknowledgement: Codable, Equatable, Sendable {
    let taskId: String
}

struct RelayTurnMutationAcknowledgement: Codable, Equatable, Sendable {
    let turnId: String
}

struct RelayApprovalDecision: Codable, Equatable, Sendable {
    enum Decision: String, Codable, Equatable, Sendable {
        case approve, deny
    }

    let decision: Decision
    let dangerousConfirmation: Bool?
}

struct RelayQuestionAnswers: Codable, Equatable, Sendable {
    let answers: [String: [String]]
}

struct RelayNewTaskInput: Codable, Equatable, Sendable {
    let cwd: String
    let model: String
    let effort: String
    let prompt: String
}

struct RelayInstructionInput: Codable, Equatable, Sendable {
    let text: String
}

struct RelaySteerInput: Codable, Equatable, Sendable {
    let turnId: String
    let text: String
}

struct RelayStopInput: Codable, Equatable, Sendable {
    let turnId: String
}
