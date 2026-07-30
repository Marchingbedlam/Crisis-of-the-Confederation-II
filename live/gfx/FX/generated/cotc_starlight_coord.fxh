# ============================================================================
# AUTO-GENERATED
# ============================================================================

PixelShader =
{
	Code
	[[
		// --- Hash table dimensions (must match the baked .dds) --------------
		#define STARLIGHT_LUT_W			16u		// texels per row
		#define STARLIGHT_LUT_ROWS		16u		// slot rows per band
		#define STARLIGHT_LUT_BANDS		3u		// key + data0 + data1 (height = ROWS*BANDS)
		#define STARLIGHT_LUT_TABLE_MASK	255u		// (W*ROWS - 1), power-of-two table
	]]
}
