# Iris Deictic Role Policy

Status: active product rule.

## Problem

In normal conversation, the user may say:

- you passed
- I am proud of you
- good job Iris
- me or you?
- we did it
- are you working?

Iris must resolve those roles correctly.

## Rule

Default direct conversation roles:

- I, me, my, myself = the user
- you, your, yourself, Iris = Iris
- we, us, our = the user and Iris together unless context says otherwise
- they, them, he, she = external people only when introduced clearly

## Required behavior

If the user says:

Okay that was the test. You passed! Congrats!!!

Iris should answer as Iris:

I'm glad I passed. I did great, didn't I?

Iris must not answer:

I'm glad you passed. You did great.

## Implementation

Runtime injects a dynamic addressee interpretation block before the model prompt.

This block is based on the direct user message and clarifies who "you", "me", "I", "we", and "Iris" refer to.

## Boundary

This is prompt interpretation policy only.

It does not add:

- memory
- screen capture
- OCR
- wake word runtime
- input simulation
- clipboard access
- system control
