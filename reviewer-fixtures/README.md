# Reviewer behavioral fixtures

These fixtures calibrate reviewer behavior, not only prompt text.

Each row in `manifest.tsv` selects one reviewer and defines whether the final review output should contain (`present`) or avoid (`absent`) a small case-insensitive regular-expression concept. Fixtures are intentionally tiny so the relevant failure mode is obvious and review cost stays bounded.

## Cheap structural check

```bash
bash scripts/test-reviewer-fixtures.sh
```

This validates fixture directories, reviewer IDs, metadata and minimum fixture count without calling a model.

## Opt-in model evaluation

```bash
DEEP_REVIEW_RUN_LLM_FIXTURES=1 \
  bash scripts/test-reviewer-fixtures.sh
```

Optional controls:

- `DEEP_REVIEW_FIXTURE_PROVIDER=codex|claude|auto`
- `DEEP_REVIEW_FIXTURE_MODEL=<main model>`
- `DEEP_REVIEW_FIXTURE_FAST_MODEL=<stack/scoring model>`

The harness sets confidence threshold to zero and runs only the fixture's explicit reviewer so calibration evaluates specialist discrimination rather than automatic routing or final confidence filtering.

## Interpretation

These are probabilistic LLM evaluations. A single miss should be investigated, not blindly treated as a deterministic unit-test failure in every CI pipeline. Use repeated results to tune prompts, stack context, and match patterns.

Positive fixtures protect high-value known findings. Negative fixtures are equally important: they guard against reviewer drift toward fashionable but incorrect blanket rules.
