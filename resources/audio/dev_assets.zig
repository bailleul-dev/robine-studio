/// Deterministic development signal played once when Robine Studio starts.
pub const input_wav = @embedFile("fixtures/inputs/celestial-guitar-48k-mono.wav");

/// Fixed monitor headroom for the capture-only development chain. Continuous
/// output level controls will replace this when live routing is introduced.
pub const monitor_output_gain: f32 = 0.5;

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

pub const king_of_tone_orange_nam = @embedFile(
    "models/nam/king-of-tone-clone/Ly Pedals - King of Tone Clone - OrangeChannel CLN Boost.nam",
);

pub const king_of_tone_red_nam = @embedFile(
    "models/nam/king-of-tone-clone/Ly Pedals - King of Tone Clone - Red Channel OD.nam",
);

pub const king_of_tone_both_nam = @embedFile(
    "models/nam/king-of-tone-clone/Ly Pedals - King of Tone Clone - Both Channels DST.nam",
);

/// Initial cabinet response. Position C is an opaque pack identifier: the
/// source archive does not document its physical microphone placement.
pub const default_cabinet_ir = @embedFile(
    "irs/orange-2x12-v30/Orange 2x12 V30 SM57 C.wav",
);
