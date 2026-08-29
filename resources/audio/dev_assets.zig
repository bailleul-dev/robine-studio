/// Deterministic development signal played once when Robine Studio starts.
pub const input_wav = @embedFile("fixtures/inputs/celestial-guitar-48k-mono.wav");

/// Initial full-quality Dumble capture.
pub const default_nam = @embedFile(
    "models/nam/dumble-ods-102-ford-hyper-accuracy-plus/SLAMMIN_DUMBLE_FORD_CLN_MAIN_S.nam",
);

pub const first_pedal_low_nam = @embedFile(
    "models/nam/sp-compressor/SpCompressor_Low.nam",
);

pub const first_pedal_mid_nam = @embedFile(
    "models/nam/sp-compressor/SpCompressor_Mid.nam",
);

pub const first_pedal_high_nam = @embedFile(
    "models/nam/sp-compressor/SpCompressor_High.nam",
);

/// Mid remains the deterministic benchmark default.
pub const first_pedal_nam = first_pedal_mid_nam;

/// Initial cabinet response. Position C is an opaque pack identifier: the
/// source archive does not document its physical microphone placement.
pub const default_cabinet_ir = @embedFile(
    "irs/orange-2x12-v30/Orange 2x12 V30 SM57 C.wav",
);
