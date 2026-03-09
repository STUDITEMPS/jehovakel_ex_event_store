---
name: mob-next
description: Rotation handoff in a mob session. Summarizes progress, states the next step, and updates the session spec for the incoming driver.
---

# Mob Rotation Handoff

The team is about to run `mob next` to hand off to the next driver. Do the following:

1. **Summarize current state**: What was done since the last rotation? What is the status of the current task?
2. **State the next step**: What is the next small, concrete action the incoming driver should take?
3. **Update the spec**: Write both the summary and next step into the **Rotation Log** section of session-spec.md:
   - Update "Current Task" with the active task number and name
   - Update "Progress" with what was accomplished
   - Update "Next Step" with the concrete next action
4. **Flag open issues**: If there are blockers, open questions, or decisions the team needs to make, list them clearly

The new driver and AI can pick up from this context after `mob start`.
