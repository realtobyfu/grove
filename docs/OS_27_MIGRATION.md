# Grove OS 27 migration

The current workspace uses Xcode 26.0.1 and the OS 26 SDKs. The following work
must remain deferred until an OS 27 SDK is installed so the APIs can be compiled,
tested, and profiled rather than added speculatively.

## Foundation Models

1. Replace Grove's provider-specific surface with the OS 27 `LanguageModel`
   abstraction.
2. Add task profiles:
   - capture classification, tags, and short summaries: on-device model;
   - long board synthesis and difficult multi-item reasoning: Private Cloud
     Compute when the user enables Enhanced intelligence;
   - Dialectics: a dynamic profile that changes tools and context without
     rebuilding conversation history.
3. Replace manual JSON parsing in tagging, reflection prompts, connections, and
   starters with `@Generable` response types.
4. Replace the text-based `tool_call` loop in Dialectics with Foundation Models
   `Tool` implementations. Keep write tools separately permissioned from search
   tools and require explicit confirmation for destructive or shared-data
   changes.
5. Replace character-based token estimates and message-count truncation with
   `tokenCount(for:)`, model `contextSize`, and transcript transforms.
6. Map the OS 27 Foundation Models error hierarchy into `LLMError`, including
   quota-nearing and quota-reached states.

## Evaluation and observability

1. Add Xcode 27 Evaluations datasets for:
   - board routing accuracy;
   - tag precision and duplicate-tag rate;
   - summary fidelity;
   - Dialectics tool selection and tool-call trajectories.
2. Seed evaluation cases from local user corrections: accepted/dismissed board
   suggestions, board changes, edited summaries, and reverted AI overviews.
3. Establish separate quality gates for the on-device and enhanced models.
4. Profile first-token latency, total latency, context size, and tool rounds with
   the Foundation Models Instruments template.

## SwiftUI

1. Test the automatic OS 27 visual refresh before adding custom glass. Apply
   custom glass only to interactive floating controls.
2. Adopt toolbar visibility priority and auto-minimizing behavior in the item
   reader.
3. Replace custom board/item reordering with OS 27 reorderable containers after
   verifying keyboard, pointer, VoiceOver, and multi-item drag behavior.
4. Consider swipe actions on non-List inbox cards so macOS and iPad triage share
   the same action model.

## Exit criteria

- Xcode 27 beta or newer is selected by `xcode-select`.
- macOS and iOS builds pass with strict concurrency enabled.
- Model behavior is evaluated on both OS 26 and OS 27 devices.
- Every new OS 27 API has an OS 26 fallback because Grove still deploys to iOS
  18 and supports older macOS installations.
