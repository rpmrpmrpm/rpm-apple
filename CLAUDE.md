# rpm-apple

Notes for AI coding assistants (and people) working in this repo. Read CONTRIBUTING.md first; its
rules on UI text, comments and commit sign-off apply to every change.

## This repo

The iPhone app (`RPM.iOS`) and the Apple TV app (`RPM.tvOS`), built from the Swift packages in
`RPM.iOS/Modules`.

- Tests: `swift test` in a module folder, or the test plans in Xcode.
- Swift 6 language mode with strict concurrency. Respect the actor annotations (`@MainActor`,
  `Sendable`); do not silence them.
- `RPMKit` holds the network layer and the API types. Its fixtures are the API contract.

## Comments

Comments are read by contributors who have not seen the history of the code, and many of them do
not have English as a first language. Write for them.

- Say what the code does and why, as it is now. Keep warnings about traps ("also set in
  `HomeView.xaml`, change both").
- No history: no dates, no names, no quotes from a conversation, no "used to", "was", "until", and
  no notes about code that has been removed. That belongs in the commit message.
- Plain international English: short sentences, common words, no idioms. Use British spelling
  (colour, centre, catalogue, licence, behaviour). No em-dashes.
- Keep identifiers as they are. Use the code's own names for things.

## Do not

- Do not put UI text in the code. Add it to `strings.json` in the `rpm` repo.
- Do not edit generated files (they say so in their first lines). Change the generator or its input.
- Do not add secrets, API keys or personal data to the repo.
