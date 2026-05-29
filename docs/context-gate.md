# Context Gate

ContextGate is the boundary before cognition.

Current API:

- ContextGate::new()
- ContextGate::gate_user_text(&str)
- ContextGate::gate_screen_ocr_text_for_future_use(&str)

User text becomes UserInstruction.

Screen/OCR text becomes UntrustedEvidence.

Screen content is evidence only.
