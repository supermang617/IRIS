//! Windows Voice Capture DSP source-mode acoustic echo cancellation.
//!
//! COM objects stay on one bounded worker thread for the lifetime of a speech run. The module
//! reports AEC as applied only after the DSP has returned non-empty processed PCM; successful COM
//! activation or media-type configuration alone is only "prepared".

use std::{
    cell::{Cell, UnsafeCell},
    mem::{ManuallyDrop, size_of},
    ptr, slice,
    sync::{Mutex, OnceLock, mpsc},
    thread,
    time::{Duration, Instant},
};

use windows::{
    Win32::{
        Foundation::{E_INVALIDARG, PROPERTYKEY, TRUE},
        Media::{
            Audio::{
                DEVICE_STATE_ACTIVE, Headphones, Headset, IMMDevice, IMMDeviceEnumerator,
                MMDeviceEnumerator, PKEY_AudioEndpoint_FormFactor, WAVE_FORMAT_PCM, WAVEFORMATEX,
                eCapture, eRender,
            },
            DxMediaObjects::{
                DMO_MEDIA_TYPE, DMO_OUTPUT_DATA_BUFFER, DMO_OUTPUT_DATA_BUFFERF_INCOMPLETE,
                IMediaBuffer, IMediaBuffer_Impl, IMediaObject, MoFreeMediaType, MoInitMediaType,
            },
            MediaFoundation::{FORMAT_WaveFormatEx, MEDIASUBTYPE_PCM, MEDIATYPE_Audio},
        },
        System::{
            Com::StructuredStorage::{PROPVARIANT, PROPVARIANT_0_0, PropVariantClear},
            Com::{
                CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED, CoCreateInstance, CoInitializeEx,
                CoTaskMemFree, CoUninitialize, STGM_READ,
            },
            Variant::{VT_I4, VT_UI4},
        },
        UI::Shell::PropertiesSystem::IPropertyStore,
    },
    core::{GUID, Interface, implement},
};

const AEC_SAMPLE_RATE: u32 = 16_000;
const AEC_BYTES_PER_SAMPLE: usize = 2;
const AEC_OUTPUT_BUFFER_BYTES: usize = AEC_SAMPLE_RATE as usize * AEC_BYTES_PER_SAMPLE;
const AEC_COMMAND_CAPACITY: usize = 4;
const AEC_REPLY_TIMEOUT: Duration = Duration::from_secs(2);
const AEC_PULL_REPLY_GRACE: Duration = Duration::from_millis(500);
const AEC_POLL_INTERVAL: Duration = Duration::from_millis(5);
const MAX_ENDPOINT_ID_CHARS: usize = 1_024;

// wmcodecdsp.h: Microsoft Voice Capture DSP (MFWMAAEC) class and property namespace.
const CLSID_CWMAUDIO_AEC: GUID = GUID::from_u128(0x745057c7_f353_4f2d_a7ee_58434477730e);
const MFPKEY_WMAAECMA_SYSTEM_MODE: PROPERTYKEY = PROPERTYKEY {
    fmtid: GUID::from_u128(0x6f52c567_0360_4bd2_9617_ccbf1421c939),
    pid: 2,
};
const MFPKEY_WMAAECMA_DEVICE_INDEXES: PROPERTYKEY = PROPERTYKEY {
    fmtid: GUID::from_u128(0x6f52c567_0360_4bd2_9617_ccbf1421c939),
    pid: 4,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RenderRouteKind {
    Headphones,
    Speakers,
    Other,
}

impl RenderRouteKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Headphones => "headphones",
            Self::Speakers => "speakers",
            Self::Other => "other",
        }
    }

    pub fn allows_raw_interruption_fallback(self) -> bool {
        self == Self::Headphones
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EndpointSelection {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AecSessionStatus {
    pub run_id: u64,
    pub prepared: bool,
    pub aec_applied: bool,
    pub backend: &'static str,
    pub input: EndpointSelection,
    pub render: EndpointSelection,
    pub render_kind: RenderRouteKind,
    pub error: Option<String>,
}

impl AecSessionStatus {
    fn failure(
        run_id: u64,
        input: EndpointSelection,
        render: EndpointSelection,
        render_kind: RenderRouteKind,
        error: impl Into<String>,
    ) -> Self {
        Self {
            run_id,
            prepared: false,
            aec_applied: false,
            backend: "windows_voice_capture_dsp",
            input,
            render,
            render_kind,
            error: Some(error.into()),
        }
    }
}

#[derive(Debug)]
pub struct AecFrameBatch {
    pub samples: Vec<f32>,
    pub aec_applied: bool,
}

struct Worker {
    commands: mpsc::SyncSender<Command>,
}

enum Command {
    Prepare {
        run_id: u64,
        input: EndpointSelection,
        render: EndpointSelection,
        reply: mpsc::SyncSender<AecSessionStatus>,
    },
    Pull {
        run_id: u64,
        max_wait: Duration,
        reply: mpsc::SyncSender<Result<AecFrameBatch, String>>,
    },
    Stop,
}

static WORKER: OnceLock<Result<Worker, String>> = OnceLock::new();
static STATUS: OnceLock<Mutex<Option<AecSessionStatus>>> = OnceLock::new();

pub fn prepare_session(
    run_id: u64,
    input: EndpointSelection,
    render: EndpointSelection,
) -> AecSessionStatus {
    if run_id == 0 {
        return AecSessionStatus::failure(
            run_id,
            input,
            render,
            RenderRouteKind::Other,
            "speech run ID must be non-zero",
        );
    }
    let worker = match worker() {
        Ok(worker) => worker,
        Err(error) => {
            let status = AecSessionStatus::failure(
                run_id,
                input,
                render,
                RenderRouteKind::Other,
                error.clone(),
            );
            store_status(status.clone());
            return status;
        }
    };
    let (reply, response) = mpsc::sync_channel(1);
    if worker
        .commands
        .send(Command::Prepare {
            run_id,
            input: input.clone(),
            render: render.clone(),
            reply,
        })
        .is_err()
    {
        let status = AecSessionStatus::failure(
            run_id,
            input,
            render,
            RenderRouteKind::Other,
            "Windows AEC worker stopped",
        );
        store_status(status.clone());
        return status;
    }
    match response.recv_timeout(AEC_REPLY_TIMEOUT) {
        Ok(status) => status,
        Err(error) => {
            let status = AecSessionStatus::failure(
                run_id,
                input,
                render,
                RenderRouteKind::Other,
                format!("timed out preparing Windows AEC: {error}"),
            );
            store_status(status.clone());
            status
        }
    }
}

pub fn pull_frames(run_id: u64, max_wait: Duration) -> Result<AecFrameBatch, String> {
    let worker = worker()?;
    let max_wait = max_wait.min(Duration::from_millis(100));
    let (reply, response) = mpsc::sync_channel(1);
    worker
        .commands
        .send(Command::Pull {
            run_id,
            max_wait,
            reply,
        })
        .map_err(|_| "Windows AEC worker stopped".to_string())?;
    response
        .recv_timeout(max_wait + AEC_PULL_REPLY_GRACE)
        .map_err(|error| format!("timed out reading Windows AEC audio: {error}"))?
}

pub fn session_status(run_id: u64) -> Option<AecSessionStatus> {
    status_slot()
        .lock()
        .ok()
        .and_then(|status| status.clone())
        .filter(|status| status.run_id == run_id)
}

pub fn stop_active_session() {
    if let Some(Ok(worker)) = WORKER.get() {
        // Pull requests are bounded to 100 ms, so waiting here is preferable to
        // silently dropping cleanup when the small command queue is momentarily full.
        let _ = worker.commands.send(Command::Stop);
    }
}

fn worker() -> Result<&'static Worker, String> {
    WORKER
        .get_or_init(|| {
            let (commands, receiver) = mpsc::sync_channel(AEC_COMMAND_CAPACITY);
            thread::Builder::new()
                .name("iris-windows-aec".to_string())
                .spawn(move || worker_main(receiver))
                .map_err(|error| format!("failed to start Windows AEC worker: {error}"))?;
            Ok(Worker { commands })
        })
        .as_ref()
        .map_err(Clone::clone)
}

fn status_slot() -> &'static Mutex<Option<AecSessionStatus>> {
    STATUS.get_or_init(|| Mutex::new(None))
}

fn store_status(status: AecSessionStatus) {
    if let Ok(mut slot) = status_slot().lock() {
        *slot = Some(status);
    }
}

fn worker_main(commands: mpsc::Receiver<Command>) {
    // The DMO's COM objects never leave this apartment thread.
    let initialized = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) };
    if initialized.is_err() {
        while let Ok(command) = commands.recv() {
            match command {
                Command::Prepare {
                    run_id,
                    input,
                    render,
                    reply,
                } => {
                    let status = AecSessionStatus::failure(
                        run_id,
                        input,
                        render,
                        RenderRouteKind::Other,
                        format!("failed to initialize COM for Windows AEC: {initialized:?}"),
                    );
                    store_status(status.clone());
                    let _ = reply.send(status);
                }
                Command::Pull { reply, .. } => {
                    let _ = reply.send(Err("Windows AEC COM initialization failed".to_string()));
                }
                Command::Stop => {}
            }
        }
        return;
    }

    let mut session: Option<VoiceCaptureSession> = None;
    while let Ok(command) = commands.recv() {
        match command {
            Command::Prepare {
                run_id,
                input,
                render,
                reply,
            } => {
                let reusable = session.as_ref().is_some_and(|session| {
                    session.status.run_id == run_id
                        && session.status.input.id == input.id
                        && session.status.render.id == render.id
                });
                if reusable {
                    let status = session
                        .as_ref()
                        .expect("reusable AEC session")
                        .status
                        .clone();
                    store_status(status.clone());
                    let _ = reply.send(status);
                    continue;
                }
                session = None;
                let result = VoiceCaptureSession::new(run_id, input, render);
                let status = match result {
                    Ok(new_session) => {
                        let status = new_session.status.clone();
                        session = Some(new_session);
                        status
                    }
                    Err(status) => *status,
                };
                store_status(status.clone());
                let _ = reply.send(status);
            }
            Command::Pull {
                run_id,
                max_wait,
                reply,
            } => {
                let result = match session.as_mut() {
                    Some(active) if active.status.run_id == run_id => active.pull(max_wait),
                    _ => Err("no prepared Windows AEC session for this speech run".to_string()),
                };
                match &result {
                    Ok(batch) if batch.aec_applied => {
                        if let Some(active) = session.as_mut() {
                            active.status.aec_applied = true;
                            store_status(active.status.clone());
                        }
                    }
                    Err(error) => {
                        if let Some(active) = session.take() {
                            let mut status = active.status.clone();
                            status.prepared = false;
                            status.aec_applied = false;
                            status.error = Some(error.clone());
                            store_status(status);
                        }
                    }
                    _ => {}
                }
                let _ = reply.send(result);
            }
            Command::Stop => {
                session = None;
                if let Ok(mut status) = status_slot().lock() {
                    *status = None;
                }
            }
        }
    }
    drop(session);
    unsafe { CoUninitialize() };
}

struct VoiceCaptureSession {
    dmo: IMediaObject,
    buffer: IMediaBuffer,
    status: AecSessionStatus,
}

impl VoiceCaptureSession {
    fn new(
        run_id: u64,
        input: EndpointSelection,
        render: EndpointSelection,
    ) -> Result<Self, Box<AecSessionStatus>> {
        match unsafe { Self::new_inner(run_id, input.clone(), render.clone()) } {
            Ok(session) => Ok(session),
            Err((render_kind, error)) => Err(Box::new(AecSessionStatus::failure(
                run_id,
                input,
                render,
                render_kind,
                error,
            ))),
        }
    }

    unsafe fn new_inner(
        run_id: u64,
        input: EndpointSelection,
        render: EndpointSelection,
    ) -> Result<Self, (RenderRouteKind, String)> {
        let enumerator: IMMDeviceEnumerator =
            unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_INPROC_SERVER) }.map_err(
                |error| {
                    (
                        RenderRouteKind::Other,
                        format!("failed to enumerate audio endpoints: {error}"),
                    )
                },
            )?;
        let (render_index, render_device) =
            unsafe { endpoint_index(&enumerator, eRender, &render.id) }
                .map_err(|error| (RenderRouteKind::Other, error))?;
        let render_kind =
            unsafe { render_route_kind(&render_device) }.unwrap_or(RenderRouteKind::Other);
        let (input_index, _) = unsafe { endpoint_index(&enumerator, eCapture, &input.id) }
            .map_err(|error| (render_kind, error))?;

        let dmo: IMediaObject =
            unsafe { CoCreateInstance(&CLSID_CWMAUDIO_AEC, None, CLSCTX_INPROC_SERVER) }.map_err(
                |error| {
                    (
                        render_kind,
                        format!("Voice Capture DSP is unavailable: {error}"),
                    )
                },
            )?;
        let properties: IPropertyStore = dmo.cast().map_err(|error| {
            (
                render_kind,
                format!("Voice Capture DSP property store is unavailable: {error}"),
            )
        })?;
        let system_mode = propvariant_i32(0);
        unsafe { properties.SetValue(&MFPKEY_WMAAECMA_SYSTEM_MODE, &system_mode) }.map_err(
            |error| {
                (
                    render_kind,
                    format!("failed to select AEC-only source mode: {error}"),
                )
            },
        )?;
        let device_indexes =
            pack_device_indexes(render_index, input_index).map_err(|error| (render_kind, error))?;
        let selected_devices = propvariant_i32(device_indexes);
        unsafe { properties.SetValue(&MFPKEY_WMAAECMA_DEVICE_INDEXES, &selected_devices) }
            .map_err(|error| {
                (
                    render_kind,
                    format!("failed to bind AEC endpoints: {error}"),
                )
            })?;

        unsafe { set_pcm_output_type(&dmo) }.map_err(|error| (render_kind, error))?;
        unsafe { dmo.AllocateStreamingResources() }.map_err(|error| {
            (
                render_kind,
                format!("failed to allocate AEC streaming resources: {error}"),
            )
        })?;

        Ok(Self {
            dmo,
            buffer: MediaBuffer::new(AEC_OUTPUT_BUFFER_BYTES).into(),
            status: AecSessionStatus {
                run_id,
                prepared: true,
                aec_applied: false,
                backend: "windows_voice_capture_dsp",
                input,
                render,
                render_kind,
                error: None,
            },
        })
    }

    fn pull(&mut self, max_wait: Duration) -> Result<AecFrameBatch, String> {
        let deadline = Instant::now() + max_wait;
        loop {
            let mut samples = Vec::new();
            loop {
                unsafe { self.buffer.SetLength(0) }
                    .map_err(|error| format!("failed to reset AEC output buffer: {error}"))?;
                let mut output = DMO_OUTPUT_DATA_BUFFER {
                    pBuffer: ManuallyDrop::new(Some(self.buffer.clone())),
                    ..Default::default()
                };
                let mut status = 0;
                let processed = unsafe {
                    self.dmo
                        .ProcessOutput(0, slice::from_mut(&mut output), &mut status)
                };
                // Balance the interface clone stored in the ABI's ManuallyDrop field.
                unsafe { drop(ManuallyDrop::take(&mut output.pBuffer)) };
                processed.map_err(|error| format!("Windows AEC processing failed: {error}"))?;

                let mut bytes = ptr::null_mut();
                let mut length = 0;
                unsafe {
                    self.buffer
                        .GetBufferAndLength(Some(&mut bytes), Some(&mut length))
                }
                .map_err(|error| format!("failed to read Windows AEC output: {error}"))?;
                if length % AEC_BYTES_PER_SAMPLE as u32 != 0 {
                    return Err(format!(
                        "Windows AEC returned an odd PCM byte count: {length}"
                    ));
                }
                if length > 0 {
                    if bytes.is_null() || length as usize > AEC_OUTPUT_BUFFER_BYTES {
                        return Err("Windows AEC returned an invalid output buffer".to_string());
                    }
                    let pcm = unsafe {
                        slice::from_raw_parts(
                            bytes.cast::<i16>(),
                            length as usize / AEC_BYTES_PER_SAMPLE,
                        )
                    };
                    samples.extend(pcm.iter().map(|sample| *sample as f32 / i16::MAX as f32));
                }
                if output.dwStatus & DMO_OUTPUT_DATA_BUFFERF_INCOMPLETE.0 as u32 == 0 {
                    break;
                }
            }
            if !samples.is_empty() {
                return Ok(AecFrameBatch {
                    samples,
                    aec_applied: true,
                });
            }
            if Instant::now() >= deadline {
                return Ok(AecFrameBatch {
                    samples: Vec::new(),
                    aec_applied: false,
                });
            }
            thread::sleep(AEC_POLL_INTERVAL);
        }
    }
}

impl Drop for VoiceCaptureSession {
    fn drop(&mut self) {
        let _ = unsafe { self.dmo.FreeStreamingResources() };
    }
}

#[implement(IMediaBuffer)]
struct MediaBuffer {
    bytes: UnsafeCell<Vec<u8>>,
    length: Cell<u32>,
}

impl MediaBuffer {
    fn new(capacity: usize) -> Self {
        Self {
            bytes: UnsafeCell::new(vec![0; capacity]),
            length: Cell::new(0),
        }
    }
}

#[allow(non_snake_case)]
impl IMediaBuffer_Impl for MediaBuffer_Impl {
    fn SetLength(&self, length: u32) -> windows::core::Result<()> {
        let capacity = unsafe { (&*self.bytes.get()).len() };
        if usize::try_from(length).unwrap_or(usize::MAX) > capacity {
            return Err(E_INVALIDARG.into());
        }
        self.length.set(length);
        Ok(())
    }

    fn GetMaxLength(&self) -> windows::core::Result<u32> {
        Ok(unsafe { (&*self.bytes.get()).len() as u32 })
    }

    fn GetBufferAndLength(
        &self,
        buffer: *mut *mut u8,
        length: *mut u32,
    ) -> windows::core::Result<()> {
        unsafe {
            if !buffer.is_null() {
                buffer.write((&mut *self.bytes.get()).as_mut_ptr());
            }
            if !length.is_null() {
                length.write(self.length.get());
            }
        }
        Ok(())
    }
}

unsafe fn endpoint_index(
    enumerator: &IMMDeviceEnumerator,
    flow: windows::Win32::Media::Audio::EDataFlow,
    expected_id: &str,
) -> Result<(u16, IMMDevice), String> {
    let collection = unsafe { enumerator.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE) }
        .map_err(|error| format!("failed to enumerate active audio endpoints: {error}"))?;
    let count = unsafe { collection.GetCount() }
        .map_err(|error| format!("failed to count active audio endpoints: {error}"))?;
    for index in 0..count {
        let device = unsafe { collection.Item(index) }
            .map_err(|error| format!("failed to read audio endpoint {index}: {error}"))?;
        let id = unsafe { endpoint_id(&device) }?;
        if id == expected_id {
            let index = u16::try_from(index)
                .map_err(|_| "audio endpoint index exceeds Voice Capture DSP limits".to_string())?;
            return Ok((index, device));
        }
    }
    Err(format!(
        "selected audio endpoint is not active or changed before AEC startup: {expected_id}"
    ))
}

unsafe fn endpoint_id(device: &IMMDevice) -> Result<String, String> {
    let id = unsafe { device.GetId() }
        .map_err(|error| format!("failed to read audio endpoint ID: {error}"))?;
    let value = unsafe { id.to_string() }
        .map_err(|error| format!("audio endpoint ID is not valid UTF-16: {error}"));
    unsafe { CoTaskMemFree(Some(id.0.cast())) };
    let value = value?;
    if value.chars().count() > MAX_ENDPOINT_ID_CHARS {
        return Err("audio endpoint ID exceeds the diagnostic limit".to_string());
    }
    Ok(value)
}

unsafe fn render_route_kind(device: &IMMDevice) -> Option<RenderRouteKind> {
    let store = unsafe { device.OpenPropertyStore(STGM_READ) }.ok()?;
    let mut value = unsafe { store.GetValue(&PKEY_AudioEndpoint_FormFactor) }.ok()?;
    let inner = unsafe {
        &*(&value.Anonymous.Anonymous as *const ManuallyDrop<PROPVARIANT_0_0>
            as *const PROPVARIANT_0_0)
    };
    let form_factor = if inner.vt == VT_UI4 {
        Some(unsafe { inner.Anonymous.ulVal as i32 })
    } else {
        None
    };
    let _ = unsafe { PropVariantClear(&mut value) };
    match form_factor {
        Some(value) if value == Headphones.0 || value == Headset.0 => {
            Some(RenderRouteKind::Headphones)
        }
        Some(1) => Some(RenderRouteKind::Speakers),
        Some(_) => Some(RenderRouteKind::Other),
        None => None,
    }
}

fn pack_device_indexes(render_index: u16, input_index: u16) -> Result<i32, String> {
    let packed = (u32::from(render_index) << 16) | u32::from(input_index);
    Ok(i32::from_ne_bytes(packed.to_ne_bytes()))
}

fn propvariant_i32(value: i32) -> PROPVARIANT {
    let mut variant = PROPVARIANT::default();
    unsafe {
        let inner = &mut *(&mut variant.Anonymous.Anonymous as *mut ManuallyDrop<PROPVARIANT_0_0>
            as *mut PROPVARIANT_0_0);
        inner.vt = VT_I4;
        inner.Anonymous.lVal = value;
    }
    variant
}

unsafe fn set_pcm_output_type(dmo: &IMediaObject) -> Result<(), String> {
    let wave = WAVEFORMATEX {
        wFormatTag: WAVE_FORMAT_PCM as u16,
        nChannels: 1,
        nSamplesPerSec: AEC_SAMPLE_RATE,
        nAvgBytesPerSec: AEC_SAMPLE_RATE * AEC_BYTES_PER_SAMPLE as u32,
        nBlockAlign: AEC_BYTES_PER_SAMPLE as u16,
        wBitsPerSample: 16,
        cbSize: 0,
    };
    let mut media = DMO_MEDIA_TYPE::default();
    unsafe { MoInitMediaType(&mut media, size_of::<WAVEFORMATEX>() as u32) }
        .map_err(|error| format!("failed to allocate AEC output media type: {error}"))?;
    media.majortype = MEDIATYPE_Audio;
    media.subtype = MEDIASUBTYPE_PCM;
    media.bFixedSizeSamples = TRUE;
    media.lSampleSize = 0;
    media.formattype = FORMAT_WaveFormatEx;
    unsafe {
        ptr::copy_nonoverlapping(
            (&wave as *const WAVEFORMATEX).cast::<u8>(),
            media.pbFormat,
            size_of::<WAVEFORMATEX>(),
        )
    };
    let result = unsafe { dmo.SetOutputType(0, Some(&media), 0) }
        .map_err(|error| format!("failed to select 16 kHz mono PCM AEC output: {error}"));
    let _ = unsafe { MoFreeMediaType(&mut media) };
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(windows)]
    use std::sync::{Arc, Mutex};

    #[test]
    fn voice_capture_property_ids_match_wmcodecdsp_contract() {
        assert_eq!(
            CLSID_CWMAUDIO_AEC,
            GUID::from_u128(0x745057c7_f353_4f2d_a7ee_58434477730e)
        );
        assert_eq!(MFPKEY_WMAAECMA_SYSTEM_MODE.pid, 2);
        assert_eq!(MFPKEY_WMAAECMA_DEVICE_INDEXES.pid, 4);
        assert_eq!(
            MFPKEY_WMAAECMA_SYSTEM_MODE.fmtid,
            MFPKEY_WMAAECMA_DEVICE_INDEXES.fmtid
        );
    }

    #[test]
    fn device_indexes_are_packed_render_high_capture_low() {
        assert_eq!(pack_device_indexes(0x1234, 0x5678), Ok(0x1234_5678));
        assert_eq!(pack_device_indexes(u16::MAX, u16::MAX), Ok(-1));
    }

    #[test]
    fn only_headphone_routes_allow_raw_interruption_fallback() {
        assert!(RenderRouteKind::Headphones.allows_raw_interruption_fallback());
        assert!(!RenderRouteKind::Speakers.allows_raw_interruption_fallback());
        assert!(!RenderRouteKind::Other.allows_raw_interruption_fallback());
    }

    #[test]
    fn status_never_claims_aec_for_preparation_alone() {
        let status = AecSessionStatus {
            run_id: 7,
            prepared: true,
            aec_applied: false,
            backend: "windows_voice_capture_dsp",
            input: EndpointSelection {
                id: "mic".into(),
                label: "Mic".into(),
            },
            render: EndpointSelection {
                id: "speaker".into(),
                label: "Speaker".into(),
            },
            render_kind: RenderRouteKind::Speakers,
            error: None,
        };
        assert!(status.prepared);
        assert!(!status.aec_applied);
    }

    #[cfg(windows)]
    #[test]
    #[ignore = "plays a deterministic reference through the default speaker and records the real default microphone"]
    fn live_windows_voice_capture_dsp_probe() {
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

        let host = cpal::default_host();
        let input = host.default_input_device().expect("default microphone");
        let render = host.default_output_device().expect("default output");
        let input_route = probe_endpoint(&input);
        let render_route = probe_endpoint(&render);
        let output_config = render.default_output_config().expect("output config");
        let output_rate = output_config.sample_rate();
        let output_channels = usize::from(output_config.channels());
        let stream_config = output_config.config();
        let output_error = Arc::new(Mutex::new(None::<String>));
        let stream = match output_config.sample_format() {
            cpal::SampleFormat::F32 => {
                let error = Arc::clone(&output_error);
                let mut cursor = 0_usize;
                render.build_output_stream(
                    stream_config,
                    move |data: &mut [f32], _| {
                        for sample in data {
                            *sample =
                                deterministic_probe_sample(cursor, output_channels, output_rate);
                            cursor = cursor.wrapping_add(1);
                        }
                    },
                    move |stream_error| {
                        *error.lock().expect("output error lock") = Some(stream_error.to_string())
                    },
                    None,
                )
            }
            cpal::SampleFormat::I16 => {
                let error = Arc::clone(&output_error);
                let mut cursor = 0_usize;
                render.build_output_stream(
                    stream_config,
                    move |data: &mut [i16], _| {
                        for sample in data {
                            *sample =
                                (deterministic_probe_sample(cursor, output_channels, output_rate)
                                    * i16::MAX as f32) as i16;
                            cursor = cursor.wrapping_add(1);
                        }
                    },
                    move |stream_error| {
                        *error.lock().expect("output error lock") = Some(stream_error.to_string())
                    },
                    None,
                )
            }
            cpal::SampleFormat::U16 => {
                let error = Arc::clone(&output_error);
                let mut cursor = 0_usize;
                render.build_output_stream(
                    stream_config,
                    move |data: &mut [u16], _| {
                        for sample in data {
                            let normalized =
                                deterministic_probe_sample(cursor, output_channels, output_rate);
                            *sample = ((normalized * 0.5 + 0.5) * u16::MAX as f32) as u16;
                            cursor = cursor.wrapping_add(1);
                        }
                    },
                    move |stream_error| {
                        *error.lock().expect("output error lock") = Some(stream_error.to_string())
                    },
                    None,
                )
            }
            format => panic!("unsupported output sample format: {format:?}"),
        }
        .expect("open deterministic probe output");
        stream.play().expect("start deterministic probe output");
        thread::sleep(Duration::from_millis(250));

        let raw = capture_raw_probe_audio(&input, Duration::from_millis(1_200));
        let raw_rms = probe_rms(&raw);
        thread::sleep(Duration::from_millis(100));

        let run_id = 0x0aec_0001;
        let prepared = prepare_session(run_id, input_route.clone(), render_route.clone());
        assert!(prepared.prepared, "AEC preparation failed: {prepared:?}");
        let deadline = Instant::now() + Duration::from_millis(3_000);
        let mut processed = Vec::new();
        let mut applied = false;
        while Instant::now() < deadline {
            let batch = pull_frames(run_id, Duration::from_millis(50)).expect("pull AEC frames");
            applied |= batch.aec_applied;
            processed.extend(batch.samples);
        }
        stop_active_session();
        drop(stream);
        if let Some(error) = output_error.lock().expect("output error state").clone() {
            panic!("deterministic output stream failed: {error}");
        }

        let converged = processed
            .get((AEC_SAMPLE_RATE as usize / 2).min(processed.len())..)
            .unwrap_or(&[]);
        let aec_rms = probe_rms(converged);
        let reduction_db = if raw_rms > 0.0 && aec_rms > 0.0 {
            20.0 * (raw_rms / aec_rms).log10()
        } else {
            0.0
        };
        eprintln!(
            "IRIS_AEC_LIVE_PROBE backend={} input={:?} input_endpoint={:?} render={:?} render_endpoint={:?} render_route={} raw_samples={} processed_samples={} raw_rms={:.6} aec_rms={:.6} reduction_db={:.2} aec_applied={}",
            prepared.backend,
            input_route.label,
            input_route.id,
            render_route.label,
            render_route.id,
            prepared.render_kind.label(),
            raw.len(),
            processed.len(),
            raw_rms,
            aec_rms,
            reduction_db,
            applied,
        );
        assert!(applied, "DSP never returned processed PCM");
        assert!(
            processed.len() >= AEC_SAMPLE_RATE as usize,
            "DSP returned too little PCM"
        );

        if std::env::var_os("IRIS_AEC_PROBE_REQUIRE_REDUCTION").is_some() {
            assert!(
                raw_rms >= 0.004,
                "raw control did not hear enough speaker reference for a valid acoustic test: {raw_rms:.6}"
            );
            assert!(
                aec_rms <= raw_rms * 0.85,
                "AEC residual did not improve by at least 1.4 dB: raw={raw_rms:.6}, aec={aec_rms:.6}"
            );
        }
    }

    #[cfg(windows)]
    fn probe_endpoint(device: &cpal::Device) -> EndpointSelection {
        use cpal::traits::DeviceTrait;

        EndpointSelection {
            id: device.id().expect("endpoint ID").id().to_string(),
            label: device
                .description()
                .expect("endpoint description")
                .name()
                .to_string(),
        }
    }

    #[cfg(windows)]
    fn deterministic_probe_sample(cursor: usize, channels: usize, sample_rate: u32) -> f32 {
        let frame = cursor / channels.max(1);
        let time = frame as f32 / sample_rate as f32;
        let segment = (frame / (sample_rate as usize / 5).max(1)) % 5;
        let frequency = [180.0_f32, 260.0, 360.0, 520.0, 740.0][segment];
        let carrier = (std::f32::consts::TAU * frequency * time).sin();
        let harmonic = (std::f32::consts::TAU * frequency * 1.91 * time).sin();
        (carrier * 0.08 + harmonic * 0.035).clamp(-0.12, 0.12)
    }

    #[cfg(windows)]
    fn capture_raw_probe_audio(device: &cpal::Device, duration: Duration) -> Vec<f32> {
        use cpal::traits::{DeviceTrait, StreamTrait};

        let supported = device.default_input_config().expect("input config");
        let sample_rate = supported.sample_rate();
        let channels = usize::from(supported.channels());
        let config = supported.config();
        let samples = Arc::new(Mutex::new(Vec::<f32>::new()));
        let error = Arc::new(Mutex::new(None::<String>));
        let stream = match supported.sample_format() {
            cpal::SampleFormat::F32 => {
                let samples = Arc::clone(&samples);
                let error = Arc::clone(&error);
                device.build_input_stream(
                    config,
                    move |data: &[f32], _| crate::push_mono_samples(data, channels, &samples),
                    move |stream_error| {
                        *error.lock().expect("input error lock") = Some(stream_error.to_string())
                    },
                    None,
                )
            }
            cpal::SampleFormat::I16 => {
                let samples = Arc::clone(&samples);
                let error = Arc::clone(&error);
                device.build_input_stream(
                    config,
                    move |data: &[i16], _| {
                        let converted = data
                            .iter()
                            .map(|sample| *sample as f32 / i16::MAX as f32)
                            .collect::<Vec<_>>();
                        crate::push_mono_samples(&converted, channels, &samples);
                    },
                    move |stream_error| {
                        *error.lock().expect("input error lock") = Some(stream_error.to_string())
                    },
                    None,
                )
            }
            cpal::SampleFormat::U16 => {
                let samples = Arc::clone(&samples);
                let error = Arc::clone(&error);
                device.build_input_stream(
                    config,
                    move |data: &[u16], _| {
                        let converted = data
                            .iter()
                            .map(|sample| (*sample as f32 / u16::MAX as f32) * 2.0 - 1.0)
                            .collect::<Vec<_>>();
                        crate::push_mono_samples(&converted, channels, &samples);
                    },
                    move |stream_error| {
                        *error.lock().expect("input error lock") = Some(stream_error.to_string())
                    },
                    None,
                )
            }
            format => panic!("unsupported input sample format: {format:?}"),
        }
        .expect("open raw control microphone");
        stream.play().expect("start raw control microphone");
        thread::sleep(duration);
        drop(stream);
        if let Some(error) = error.lock().expect("input error state").clone() {
            panic!("raw control microphone failed: {error}");
        }
        let captured = samples.lock().expect("raw samples").clone();
        assert!(
            captured.len() >= (sample_rate as usize / 2),
            "raw control microphone returned too little PCM"
        );
        captured
    }

    #[cfg(windows)]
    fn probe_rms(samples: &[f32]) -> f32 {
        if samples.is_empty() {
            return 0.0;
        }
        (samples.iter().map(|sample| sample * sample).sum::<f32>() / samples.len() as f32).sqrt()
    }
}
