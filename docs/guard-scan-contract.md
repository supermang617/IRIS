# Guard Scan Contract

Status: active.

Runtime safety scans must detect actual capability APIs, not broad namespace strings.

## Correct

- Command::new
- std::process::Command
- process::Command
- TcpStream
- std::net

## Incorrect

- std::process by itself

Reason: std::process can be used for process exit codes or metadata. Iris forbids process spawning and shell execution, not harmless namespace references.

## Rule

When a guard fails, fix the first precise failing section. Do not add broad string scans that catch the guard script itself or harmless namespace references.
