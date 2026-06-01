use sysinfo::System;

pub const DEFAULT_RESERVED_MEMORY_RATIO: f64 = 0.35;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlatformTarget {
    Windows,
    Unsupported,
}

impl PlatformTarget {
    pub fn current() -> Self {
        if cfg!(target_os = "windows") {
            Self::Windows
        } else {
            Self::Unsupported
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Windows => "windows",
            Self::Unsupported => "unsupported",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct HardwareSnapshot {
    pub platform: PlatformTarget,
    pub total_ram_bytes: u64,
    pub available_ram_bytes: u64,
    pub cpu_cores: usize,
    pub gpu_vram_bytes: Option<u64>,
    pub reserved_memory_ratio: f64,
}

impl HardwareSnapshot {
    pub fn usable_memory_bytes(&self) -> u64 {
        let reserved = (self.total_ram_bytes as f64 * self.reserved_memory_ratio).round() as u64;
        self.available_ram_bytes.saturating_sub(reserved)
    }

    pub fn total_ram_gb(&self) -> f64 {
        bytes_to_gb(self.total_ram_bytes)
    }

    pub fn available_ram_gb(&self) -> f64 {
        bytes_to_gb(self.available_ram_bytes)
    }

    pub fn usable_memory_gb(&self) -> f64 {
        bytes_to_gb(self.usable_memory_bytes())
    }

    pub fn basis(&self) -> String {
        format!(
            "platform={}, total_ram={:.1}GB, available_ram={:.1}GB, usable_after_reserve={:.1}GB, cpu_cores={}, reserved_memory_ratio={:.0}%",
            self.platform.as_str(),
            self.total_ram_gb(),
            self.available_ram_gb(),
            self.usable_memory_gb(),
            self.cpu_cores,
            self.reserved_memory_ratio * 100.0
        )
    }
}

pub fn scan_system() -> HardwareSnapshot {
    let mut system = System::new_all();
    system.refresh_memory();
    system.refresh_cpu_all();

    HardwareSnapshot {
        platform: PlatformTarget::current(),
        total_ram_bytes: system.total_memory(),
        available_ram_bytes: system.available_memory(),
        cpu_cores: system.cpus().len(),
        gpu_vram_bytes: None,
        reserved_memory_ratio: DEFAULT_RESERVED_MEMORY_RATIO,
    }
}

fn bytes_to_gb(bytes: u64) -> f64 {
    bytes as f64 / 1024.0 / 1024.0 / 1024.0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gb(value: u64) -> u64 {
        value * 1024 * 1024 * 1024
    }

    #[test]
    fn usable_memory_reserves_system_headroom() {
        let snapshot = HardwareSnapshot {
            platform: PlatformTarget::Windows,
            total_ram_bytes: gb(64),
            available_ram_bytes: gb(56),
            cpu_cores: 16,
            gpu_vram_bytes: None,
            reserved_memory_ratio: DEFAULT_RESERVED_MEMORY_RATIO,
        };

        let expected = (gb(56) as f64 - (gb(64) as f64 * 0.35).round()) as u64;
        assert_eq!(snapshot.usable_memory_bytes(), expected);
        assert!(snapshot.usable_memory_gb() > 33.5);
        assert!(snapshot.usable_memory_gb() < 33.7);
    }

    #[test]
    fn basis_reports_windows_hardware() {
        let snapshot = HardwareSnapshot {
            platform: PlatformTarget::Windows,
            total_ram_bytes: gb(64),
            available_ram_bytes: gb(56),
            cpu_cores: 16,
            gpu_vram_bytes: None,
            reserved_memory_ratio: DEFAULT_RESERVED_MEMORY_RATIO,
        };

        assert!(snapshot.basis().contains("platform=windows"));
        assert!(snapshot.basis().contains("cpu_cores=16"));
    }
}
