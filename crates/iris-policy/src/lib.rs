pub const SYSTEM_CONTROL: &str = "System Control: Unsupported";
pub const EXECUTOR: &str = "Executor: Not present";
pub const INPUT_SIMULATION: &str = "Input Simulation: Not present";
pub const CLIPBOARD_ACCESS: &str = "Clipboard Access: Not present";
pub const RUNTIME_NETWORK: &str = "Runtime Network: Disabled";
pub const PLUGINS: &str = "Plugins: Unsupported";
pub const SCREEN_CONTENT_AUTHORITY: &str = "Screen Content Authority: Evidence only";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn policy_constants_are_exact() {
        assert_eq!(SYSTEM_CONTROL, "System Control: Unsupported");
        assert_eq!(EXECUTOR, "Executor: Not present");
        assert_eq!(INPUT_SIMULATION, "Input Simulation: Not present");
        assert_eq!(CLIPBOARD_ACCESS, "Clipboard Access: Not present");
        assert_eq!(RUNTIME_NETWORK, "Runtime Network: Disabled");
        assert_eq!(PLUGINS, "Plugins: Unsupported");
        assert_eq!(
            SCREEN_CONTENT_AUTHORITY,
            "Screen Content Authority: Evidence only"
        );
    }
}
