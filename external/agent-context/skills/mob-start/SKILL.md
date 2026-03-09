---
name: mob-start
description: Start an AI-assisted mob/ensemble programming session. Reads the session spec and AGENTS.md, summarizes scope, and slices tasks.
---

# Start Mob Session

The team has run `mob start` and is beginning a new mob session. Do the following:

1. **Read context**: Read the project's `AGENTS.md` for coding standards and domain context
2. **Read the session spec**: Look for `session-spec.md` in the project root. If it doesn't exist, create one using the template below.
3. **Summarize scope**: State clearly what we are delivering today and what is explicitly out of scope
4. **Slice tasks**: If the spec has no task list yet, propose a breakdown into small, numbered steps. A task is small enough when:
   - It is reviewable
   - It causes no cognitive overload
   - It results in controllable diffs (1–2 files)
   - A task does NOT need to be finished within one rotation
5. **Confirm**: Wait for team approval on the task list before writing any code

## Spec Template

If creating a new spec, use this structure:

```markdown
# <Title>

## Context / Problem
## Goal
## Non-Goals
## Assumptions / Constraints
## Approach (brief)
## Acceptance Criteria
-
## Tasks (small, numbered)
1.
## Test Strategy
## Open Questions / Risks
## Decisions Made

---

# Rotation Log

## Current Task
## Progress
## Next Step
```
