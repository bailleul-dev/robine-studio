/// Deterministic development signal played once when Robine Studio starts.
pub const input_wav = @embedFile("fixtures/inputs/celestial-guitar-48k-mono.wav");

/// Fixed monitor headroom for the capture-only development chain. Continuous
/// output level controls will replace this when live routing is introduced.
pub const monitor_output_gain: f32 = 0.025;

/// Initial full-quality Dumble capture.
pub const default_nam = @embedFile(
    "models/nam/dumble-ods-102-ford-hyper-accuracy-plus/SLAMMIN_DUMBLE_FORD_CLN_MAIN_S.nam",
);

pub const bogner_shiva_default_nam = @embedFile(
    "models/nam/bogner-shiva-el34/bogner ch1.nam",
);

pub const mesa_lone_star_default_nam = @embedFile(
    "models/nam/mesa-boogie-lone-star/FULL-6L6[100w]_MESA!BoogieLoneStar-CH1.nam",
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

/// Neutral Normal-mode Tumnus capture used by the initial fixed mapping.
pub const tumnus_deluxe_default_nam = @embedFile(
    "models/nam/wampler-tumnus-deluxe/Tumnus Deluxe Nrm B-5 M-5 T-5 L-6 G-5.nam",
);

/// Median Op-Amp Big Muff capture used by the initial fixed catalog mapping.
pub const op_amp_big_muff_default_nam = @embedFile(
    "models/nam/electro-harmonix-op-amp-big-muff/EHX IC Big Muff V-6 T-5 S-5.nam",
);

/// Medium Hall stereo response selected by the initial effects-loop mapping.
pub const skysurfer_hall_medium_ir = @embedFile(
    "irs/tc-electronic-skysurfer-reverb/Hall 3 - Medium.wav",
);

/// Initial cabinet response. Position C is an opaque pack identifier: the
/// source archive does not document its physical microphone placement.
pub const default_cabinet_ir = @embedFile(
    "irs/orange-2x12-v30/Orange 2x12 V30 SM57 C.wav",
);

/// Runtime-ready R-121 capture associated with the left Bogner Shiva combo.
pub const bogner_shiva_cabinet_ir = @embedFile(
    "irs/bogner-shiva-2x12/Bogner Shiva 212_V30-R121 01-48k-runtime.wav",
);

/// Native 48 kHz C90 capture associated with the right Mesa Lone Star combo.
pub const mesa_lone_star_cabinet_ir = @embedFile(
    "irs/mesa-lone-star-c90/Marshall 4x12 1960A SM57 Karnivore - Mesa Lone Star 1x12 C90 Dyn441.wav",
);

pub const AmplifierCabinetPair = struct {
    name: []const u8,
    nam: []const u8,
    cabinet_ir: []const u8,
};

/// Stable left-to-right catalog shared with the three-combo studio layout.
pub const amplifier_catalog = [_]AmplifierCabinetPair{
    .{ .name = "Bogner Shiva EL34", .nam = bogner_shiva_default_nam, .cabinet_ir = bogner_shiva_cabinet_ir },
    .{ .name = "Dumble ODS #102", .nam = default_nam, .cabinet_ir = default_cabinet_ir },
    .{ .name = "Mesa/Boogie Lone Star", .nam = mesa_lone_star_default_nam, .cabinet_ir = mesa_lone_star_cabinet_ir },
};
