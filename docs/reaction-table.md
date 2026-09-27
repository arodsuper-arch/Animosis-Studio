# Reaction table

The rules that turn layer values into state. Data, not code.

## Why data

- A designer adds a reaction without a rebuild.
- Animosis Core reads it headlessly, with no renderer.
- It ships in the content manifest and versions with everything else.
- A reaction written as a `match` statement in engine code never leaves.

Same rule as materials: authored as data, consumed by whatever needs it.

## Shape

```json
{
  "id": "freeze.standing_water",
  "when": { "temperature": { "lt": 0.0 }, "moisture": { "gt": 0.4 } },
  "sets": { "state": "frozen" },
  "priority": 20,
  "capability": "weather.wetness"
}
```

- `when` — conditions on layer values. All must hold.
- `sets` — the resulting state, which materials declare an appearance for.
- `priority` — higher wins when several match. Ties are an authoring error,
  not a runtime coin flip.
- `capability` — the capability that must be enabled, or the rule never fires.

## Rules

- Reactions read layers and write state. They never write layers directly;
  effects do that.
- Evaluation is ordered by `priority`, then by `id`, so the outcome is
  reproducible.
- A reaction naming an unknown layer or capability fails at load, not silently
  at runtime.
