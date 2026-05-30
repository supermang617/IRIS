# Chat Local Route Override

Status: active.

The chat-local command is routed early to run_chat_local().

Reason: an older raw local loopback handler still existed in the command router and could panic with InvalidResponse.

The active chat-local path must use checked_local_response_for_hud so it shares the same bounded response handling as HUD.

This keeps typed conversation aligned with the tested HUD response path.
