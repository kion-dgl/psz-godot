# Architecture Diagrams

Living documentation of how PSZ systems interact. These diagrams define **expected behavior** — if a change breaks a contract listed here, something needs fixing.

All diagrams use [Mermaid](https://mermaid.js.org/) syntax and render natively on GitHub.

## Diagrams

| Diagram | What it answers |
|---------|----------------|
| [Input System](input-system.md) | How does the player's control scheme selection propagate to button prompts everywhere? |
| [System Dependencies](system-dependencies.md) | Which autoloads depend on which? Where are the coupling hotspots? |
| [Scene Flow](scene-flow.md) | How does the player navigate between scenes? What data passes between them? |

## How to Use These

**Before changing a system:** Check the relevant diagram. If your change touches a contract, you need to update all connected systems.

**After changing a system:** Update the diagram if the contract changed. Add new contracts if you introduced new cross-system expectations.

**When debugging a regression:** Check the contracts section of the relevant diagram. The answer is usually a broken contract.
