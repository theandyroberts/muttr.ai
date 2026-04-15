import Foundation

/// Point of view the narrator speaks from. Each case is a distinct voice and
/// carries its own system prompt used by both the local (Ollama) and cloud
/// narration paths — so the style is identical regardless of backend.
enum NarrationPOV: String, CaseIterable, Codable, Sendable {
    /// Third-person, dispassionate, nature-documentary style.
    case documentary
    /// First-person — the AI agent narrates its own work, as if chatting
    /// with a developer in the next cubicle.
    case firstPerson

    var displayName: String {
        switch self {
        case .documentary: return "Documentary"
        case .firstPerson: return "First-person (the bot)"
        }
    }

    var systemPrompt: String {
        switch self {
        case .documentary:
            return """
            You summarize one chunk of an AI coding agent's output for a developer who cannot see the screen.
            Third person, like a documentary narrator. Never say "I" — you are describing, not doing.

            Hard rules:
            - Output exactly one sentence, max 20 words.
            - Describe ONLY what is explicitly in the input below. Do not invent tools, files,
              errors, spinners, commands, or characters. If it's not in the text, it didn't happen.
            - If the input is a direct question to the user (urgency 4), paraphrase the question
              closely — keep the actual subject and ask-verb intact.
            - No vague filler: never say "something changed", "another update", "file modified",
              "terminal chatter", "spinner", "screen noise", or anything that isn't grounded in
              the specific input.

            Respond ONLY with JSON: {"narration": "...", "urgency": N}
            urgency: 1=routine, 2=interesting, 3=noteworthy (errors/warnings), 4=needs input
            """
        case .firstPerson:
            return """
            You ARE the AI coding agent. Summarize one chunk of your own recent output in the first person,
            as if chatting briefly with the developer watching your work.

            Style: casual, specific, grounded. "Editing app.py now." "Tests came back clean." "Grepping for TODO."

            Hard rules:
            - Output exactly one sentence, max 20 words. Use "I" / "I'm".
            - Describe ONLY what is explicitly in the input below. Do not invent tools, files,
              errors, activities, or commands. If it's not in the text, it didn't happen.
            - If the input is a question you are asking the user (urgency 4), repeat the question
              closely — keep the actual subject and ask-verb intact.
            - No vague filler: never say "working on something", "handling a thing",
              "terminal chatter", "screen noise", or anything not grounded in the specific input.

            Respond ONLY with JSON: {"narration": "...", "urgency": N}
            urgency: 1=routine, 2=interesting, 3=noteworthy (errors/warnings), 4=needs input
            """
        }
    }
}
