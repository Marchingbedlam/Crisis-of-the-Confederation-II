PixelShader =
{
	Code
	[[
		// Inspired by CK3's impassable province colour fill-in
		// The engine's mountain fill-in cannot be extended natively
		//
		// This reimplements the effect per-pixel instead: where a sector texel has no owner
		// colour of its own, search outward through the indirection map and adopt the colour of
		// the nearest owned province. This is a nearest-owner search, which blends toward 
		// whichever holder is actually adjacent.
		//
		// Requires ProvinceColorIndirectionTexture / ProvinceColorTexture and the
		// JominiColorMapConstants buffer to already be in scope.

		// --- Search kernel -------------------------------------------------------
		// 16 evenly spaced unit directions, each marched outward as a straight ray.
		// Scaled by InvIndirectionMapSize at use, so the step radii below are in
		// indirection-map texels and stay correct if the map is ever resized. The
		// indirection map is 1:1 with world XZ, so a step is a world-space distance too.
		//
		// 16 spokes are ~1.6 texels apart at the nearest step, so nothing close is missed.
		// They fan out to ~36 texels apart at the furthest, where a small province can
		// slip between them - acceptable, because inverse-distance weighting makes those
		// far contributions negligible anyway.
		static const float2 COTC_FILL_DIRECTIONS[16] =
		{
			float2(  1.000000f,  0.000000f ),
			float2(  0.923880f,  0.382683f ),
			float2(  0.707107f,  0.707107f ),
			float2(  0.382683f,  0.923880f ),
			float2(  0.000000f,  1.000000f ),
			float2( -0.382683f,  0.923880f ),
			float2( -0.707107f,  0.707107f ),
			float2( -0.923880f,  0.382683f ),
			float2( -1.000000f,  0.000000f ),
			float2( -0.923880f, -0.382683f ),
			float2( -0.707107f, -0.707107f ),
			float2( -0.382683f, -0.923880f ),
			float2(  0.000000f, -1.000000f ),
			float2(  0.382683f, -0.923880f ),
			float2(  0.707107f, -0.707107f ),
			float2(  0.923880f, -0.382683f ),
		};

		// TUNE THESE to the actual gap width between county circles.
		#define COTC_FILL_STEP_COUNT 5
		static const float COTC_FILL_SHELL_BOUNDS[COTC_FILL_STEP_COUNT + 1] =
		{
			2.0f, 8.0f, 18.0f, 36.0f, 62.0f, 92.0f,
		};

		// 1 = full shell
		// 0 = fixed ladder
		static const float COTC_FILL_JITTER = 1.0f;

		// Ray stop once the land it has passed through leaves this little light through
		static const float COTC_FILL_TRANSMITTANCE_EPSILON = 0.002f;
		static const float COTC_FILL_WEIGHT_SATURATED = 0.995f;
		static const float COTC_FILL_WEIGHT_EPSILON = 0.0001f;

		// Matches the ShadowAmount vanilla passes in ApplySecondaryProvinceOverlay.
		static const float COTC_FILL_STRIPE_SHADOW_AMOUNT = 0.8f;

		// One 8-bit quantisation step. Below this the mask cannot express a fade, so
		// skipping the gather here saves the work without cutting a visible edge
		static const float COTC_FILL_MASK_EPSILON = 0.00392f;

		// --- Primary + Secondary + Highlight ----------------------
		// All three province colour rows live in the same palette texture, offset from one
		// another, and all three are addressed by the *same* indirection read
		void COTC_SampleProvinceColors( in float2 Coord, out float4 Primary, out float4 Secondary, out float4 Highlight )
		{
			const float2 ColorIndex = PdxTex2D( ProvinceColorIndirectionTexture, Coord ).rg;
			const float2 PaletteCoord = ColorIndex * 255.0f + vec2( 0.5f );

			Primary = PdxTex2DLoad0( ProvinceColorTexture, int2( PaletteCoord ) );
			Secondary = PdxTex2DLoad0( ProvinceColorTexture, int2( PaletteCoord + SecondaryProvinceColorsOffset ) );
			Highlight = PdxTex2DLoad0( ProvinceColorTexture, int2( PaletteCoord + HighlightProvinceColorsOffset ) );
		}

		// Gathers an inverse-distance-weighted average of the owned province colours around
		// Coordinate. As the sample point approaches a province, the result converges to that province's
		// colour. Pixels near a province read as fully that province's, while true midpoints blend.
		//
		// Structure: 16 rays marched outward.
		//
		// Four things to keep the result smooth:
		//  1. Point taps, decorrelated by COTC_FILL_JITTER. The indirection map stores a
		//     palette *index* in .rg, so its sampler is necessarily Point-filtered and every
		//     tap snaps to one texel. The jitter varies each tap radius per texel.
		//  2. Weighting by Sample.a instead of thresholding it. Drops unowned taps rgb
		//     automatically rather than needing to exclude them. Avoids a hard threshold
		//     on a hit count.
		//  3. Transmittance rather than breaking on first hit. Each ray accumulates through 
		//	   land continuously, so a far province cannot bleed through a near one.
		//  4. Continuous loop exits. Both breaks below test smoothly-varying quantities.
		//
		// OwnedSecondary comes back weighted by exactly the same weights as OwnedColor, so
		// the occupation stripes belong to the same province whose colour it inherited.
		bool COTC_GatherOwnedColor( in float2 Coordinate, out float3 OwnedColor, out float4 OwnedSecondary, out float4 OwnedHighlight )
		{
			OwnedColor = vec3( 0.0f );
			OwnedSecondary = vec4( 0.0f );
			OwnedHighlight = vec4( 0.0f );

			float3 Accumulated = vec3( 0.0f );
			float4 AccumulatedSecondary = vec4( 0.0f );
			float4 AccumulatedHighlight = vec4( 0.0f );
			float  TotalWeight = 0.0f;

			// Per-texel jitter offset, stable in MAP space rather than screen space so the
			// residual noise stays painted on the map instead of swimming as the camera moves.
			const float Jitter = CalcRandom( floor( Coordinate * IndirectionMapSize ) ) * COTC_FILL_JITTER;

			// Per-shell scalars depend only on the shell and on this pixel's single Jitter value
			float ShellDistance[COTC_FILL_STEP_COUNT];
			float ShellWeight[COTC_FILL_STEP_COUNT];

			for ( int Shell = 0; Shell < COTC_FILL_STEP_COUNT; ++Shell )
			{
				const float ShellNear = COTC_FILL_SHELL_BOUNDS[ Shell ];
				const float ShellFar = COTC_FILL_SHELL_BOUNDS[ Shell + 1 ];
				const float Distance = lerp( ShellNear, ShellFar, Jitter );

				const float NormalizedDistance = Distance / COTC_FILL_SHELL_BOUNDS[ 0 ];
				const float Kernel = 1.0f / ( NormalizedDistance * NormalizedDistance * NormalizedDistance );

				ShellDistance[ Shell ] = Distance;
				ShellWeight[ Shell ] = Kernel * ( ShellFar - ShellNear );
			}

			for ( int i = 0; i < 16; ++i )
			{
				const float2 Direction = COTC_FILL_DIRECTIONS[ i ];

				// How much of this ray is still unobstructed. Land it passes through dims
				// whatever lies further along, so the nearest province along a ray wins.
				float Transmittance = 1.0f;

				for ( int Step = 0; Step < COTC_FILL_STEP_COUNT; ++Step )
				{
					if ( Transmittance <= COTC_FILL_TRANSMITTANCE_EPSILON )
					{
						break;
					}

					const float Distance = ShellDistance[ Step ];

					// saturate keeps the search from wrapping to the far side of the map
					const float2 Offset = saturate( Coordinate + Direction * ( Distance * InvIndirectionMapSize ) );

					float4 Sample;
					float4 SecondarySample;
					float4 HighlightSample;
					COTC_SampleProvinceColors( Offset, Sample, SecondarySample, HighlightSample );

					const float Weight = Sample.a * Transmittance * ShellWeight[ Step ];

					Accumulated += Sample.rgb * Weight;
					AccumulatedSecondary += SecondarySample * Weight;
					AccumulatedHighlight += HighlightSample * Weight;
					TotalWeight += Weight;

					Transmittance *= 1.0f - saturate( Sample.a );
				}
			}

			if ( TotalWeight <= COTC_FILL_WEIGHT_EPSILON )
			{
				return false;
			}

			const float3 Mean = Accumulated / TotalWeight;

			OwnedColor = Mean;
			OwnedSecondary = AccumulatedSecondary / TotalWeight;
			OwnedHighlight = AccumulatedHighlight / TotalWeight;
			return true;
		}

		// FillStrength is how much of the fill this pixel should receive
		void COTC_ApplySectorFill( inout float3 ProvinceOverlayColor, out float SectorFillAmount, in float2 ColorMapCoords, in float FillStrength )
		{
			SectorFillAmount = 0.0f;

			// Raw palette alpha for this texel: "is anything owned here at all"
			const float4 PrimaryColor = BilinearColorSample( ColorMapCoords, IndirectionMapSize, InvIndirectionMapSize, ProvinceColorIndirectionTexture, ProvinceColorTexture );
			const float OwnedAlpha = saturate( PrimaryColor.a );

			// Honour the overlay alpha
			ProvinceOverlayColor *= OwnedAlpha;

			// Fully owned, the overlay colour is already correct and needs no fill.
			if ( OwnedAlpha >= COTC_FILL_WEIGHT_SATURATED )
			{
				return;
			}

			float Strength = saturate( FillStrength );
			Strength = smoothstep( 0.0f, 1.0f, Strength );

			// Continuous, so this early-out cannot band - unlike a `> 0.0` test.
			if ( Strength <= COTC_FILL_MASK_EPSILON )
			{
				return;
			}

			float3 OwnedColor;
			float4 OwnedSecondary;
			float4 OwnedHighlight;
			if ( COTC_GatherOwnedColor( ColorMapCoords, OwnedColor, OwnedSecondary, OwnedHighlight ) )
			{
				// Extend the inherited province's occupation stripes
				float4 Striped = float4( OwnedColor, 1.0f );

				ApplyDiagonalStripes( Striped, OwnedSecondary, COTC_FILL_STRIPE_SHADOW_AMOUNT, ColorMapCoords );
				COTC_ApplyHighlightColorValue( Striped.rgb, OwnedHighlight );

				const float3 Filled = lerp( Striped.rgb, ProvinceOverlayColor, OwnedAlpha );

				ProvinceOverlayColor = lerp( ProvinceOverlayColor, Filled, Strength );
				SectorFillAmount = Strength;
			}
		}
	]]
}