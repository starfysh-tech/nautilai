# Convention: diagrams

> Status: active · Applies to: any plugin that ships a Mermaid diagram, in a README or as skill output

A diagram is not a nicer way to say the same thing. It is a different claim: *these
are the parts, and these are all the connections between them*. Prose does not
assert completeness; a picture does. That asymmetry is what these rules protect.

## 1. The shape test — diagram branching content only

Draw a diagram when the content is a **graph**: nodes with non-linear relationships
— loops, forks, convergence, states with different exits.

Do **not** draw one when the content is:

| Content | Right form |
|---|---|
| A linear chain (`a → b → c → d`) | text — the arrow already is the diagram |
| A matrix (roles × resources) | a table |
| A ranked list of findings | a list |
| Fewer than ~4 nodes | a sentence |

Adding a hop to a linear path does not make it a graph. `route → view →
permission → queryset → serializer` is five nodes and still a straight line; what
earns a diagram is *aggregation* — four routes converging on one unguarded view.

The counter-limit is the hairball. A graph's value is what it **omits**; a
200-node map of everything is wallpaper. Scope every diagram to one question, and
bound it by something that does not grow with the codebase (a finding count, one
lifecycle) rather than by file count.

## 2. Placement — README, not SKILL.md

`SKILL.md` is read by the model. A README is read by a person.

A model gains nothing from a diagram — it parses the graph back into text to use
it, having paid tokens for the box drawing. Put diagrams where a human reads them:
the plugin README, or a report file the user opens.

> **Rule:** no Mermaid in `SKILL.md`, `workflows/*.md`, or any file whose primary
> consumer is the agent — including handoff and hand-off-style documents written
> for a *next session* to read.

A README diagram is an **orientation layer added before** the existing prose, not
a replacement for it. Transitions interleaved with commands still have to be
written out; the diagram is the map you read first.

## 3. A generated diagram marks what it could not resolve

Any diagram built from a scan of the user's code must render an unresolved edge
or node **visibly**, never omit it.

Static analysis always has blind spots — runtime-registered routes, attributes set
on a base class, dynamic dispatch. A graph that silently drops those edges reads
as the complete picture and is trusted as one. That failure is worse than the flat
list it replaced, because the list never claimed to be exhaustive.

> **Rule:** carry a resolution state per node/edge (e.g. `resolved` /
> `inferred` / `unresolved`) through to the render, distinguish unresolved
> elements visually, and include a legend. Findings that depend on an unresolved
> hop are reported at lower confidence.

This is convention [#4](./README.md#4-ground-against-live-sources-mark-unverified)
— *ground against live sources; mark `[unverified]`* — applied to graph edges.

## 4. Update the diagram in the PR that changes what it depicts

A hand-authored diagram drifts, and a stale lifecycle diagram misinforms exactly
the reader who trusted it most.

> **Rule:** if a change alters a lifecycle a diagram depicts, update the diagram
> in the **same PR**. Same discipline as
> [`docs/plugin-changelog.md`](../plugin-changelog.md).

There is deliberately **no CI check**. These transitions live in `SKILL.md` prose
and bash control flow, not in parseable structure — a gate could verify the
vocabulary (subcommand names, cap values) while missing whether the transitions
are right, and a check that cannot verify the part that matters is worse than an
honest rule, because it implies coverage it does not have.

## Syntax floor

Diagrams must render both on GitHub and in a strict parser (a terminal preview,
a docs build). Stay inside the common subset:

- `flowchart` / `graph` with a direction, `stateDiagram-v2`, or `sequenceDiagram`.
- Short, plain node labels. No styling directives, no `%%` comments inside the graph.
- Node ids used consistently — never write a shape suffix (`B{Check}`) on an id
  that also appears bare (`B`), which some parsers read as two separate nodes.

## Exemplified by

- `autodev` README — lane lifecycle (review gate loop-back, four failure classes,
  two independent counters).
- `relay` README — handoff doc lifecycle (consume-once marker, TTL asymmetry).
- `commitcraft` README — release-please auto-merge loop.

Rule 3 has no exemplar yet — no shipped skill generates a diagram from a scan of
the user's code. It is written down now because the first one that does will need
it on day one, not after the first misleading graph.
