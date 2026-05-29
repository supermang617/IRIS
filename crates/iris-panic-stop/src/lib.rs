use std::sync::atomic::{AtomicBool, Ordering};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PanicStopStatus {
    Clear,
    Requested,
}

#[derive(Debug, Default)]
pub struct PanicStopFlag {
    requested: AtomicBool,
}

impl PanicStopFlag {
    pub fn new_clear() -> Self {
        Self {
            requested: AtomicBool::new(false),
        }
    }

    pub fn request_stop(&self) {
        self.requested.store(true, Ordering::SeqCst);
    }

    pub fn clear(&self) {
        self.requested.store(false, Ordering::SeqCst);
    }

    pub fn is_requested(&self) -> bool {
        self.requested.load(Ordering::SeqCst)
    }

    pub fn status(&self) -> PanicStopStatus {
        if self.is_requested() {
            PanicStopStatus::Requested
        } else {
            PanicStopStatus::Clear
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_clear() {
        let flag = PanicStopFlag::new_clear();

        assert_eq!(flag.status(), PanicStopStatus::Clear);
        assert!(!flag.is_requested());
    }

    #[test]
    fn request_stop_sets_requested_status() {
        let flag = PanicStopFlag::new_clear();

        flag.request_stop();

        assert_eq!(flag.status(), PanicStopStatus::Requested);
        assert!(flag.is_requested());
    }

    #[test]
    fn clear_resets_requested_status() {
        let flag = PanicStopFlag::new_clear();

        flag.request_stop();
        flag.clear();

        assert_eq!(flag.status(), PanicStopStatus::Clear);
        assert!(!flag.is_requested());
    }
}
