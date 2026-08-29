/// Deterministic development signal played once when Robine Studio starts.
pub const input_wav = @embedFile("fixtures/inputs/celestial-guitar-48k-mono.wav");

/// Initial full-quality Dumble capture. There is deliberately no cabinet IR yet.
pub const default_nam = @embedFile(
    "models/nam/dumble-ods-102-ford-hyper-accuracy-plus/SLAMMIN_DUMBLE_FORD_CLN_MAIN_S.nam",
);
