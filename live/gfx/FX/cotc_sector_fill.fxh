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

		// READABILITY KNOB
		//   2.0 = gentle
		//   3.0 = balanced
		//   5.0 = hard
		static const float COTC_FILL_DISTANCE_POWER = 3.0f;

		// SEAM KNOBS. Darkens the blend zone between two realms
		static const float3 COTC_FILL_SEAM_COLOR = float3( 0.03f, 0.03f, 0.045f );
		static const float COTC_FILL_SEAM_STRENGTH = 0.45f;
		static const float COTC_FILL_SEAM_CONTRAST = 2.5f;

		// Ray stop once the land it has passed through leaves this little light through
		static const float COTC_FILL_TRANSMITTANCE_EPSILON = 0.002f;
		static const float COTC_FILL_WEIGHT_SATURATED = 0.995f;
		static const float COTC_FILL_WEIGHT_EPSILON = 0.0001f;

		// --- Hollow / filled -------------------------------------------
		// Hooks into what makes county interiors go hollow
		float COTC_GetMapFilledness()
		{
			return saturate( GB_GradientAlphaInside );
		}

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

		// Footprint copied from BilinearColorSample so the interpolation matches vanilla texel for texel
		void COTC_BilinearSampleProvinceColors( in float2 Coord, out float4 Primary, out float4 Secondary, out float4 Highlight )
		{
			float2 Pixel = Coord * IndirectionMapSize + 0.5f;
			const float2 FracCoord = frac( Pixel );
			Pixel = floor( Pixel ) / IndirectionMapSize - InvIndirectionMapSize / 2.0f;

			float4 P11, P21, P12, P22;
			float4 S11, S21, S12, S22;
			float4 H11, H21, H12, H22;
			COTC_SampleProvinceColors( Pixel, P11, S11, H11 );
			COTC_SampleProvinceColors( Pixel + float2( InvIndirectionMapSize.x, 0.0f ), P21, S21, H21 );
			COTC_SampleProvinceColors( Pixel + float2( 0.0f, InvIndirectionMapSize.y ), P12, S12, H12 );
			COTC_SampleProvinceColors( Pixel + InvIndirectionMapSize, P22, S22, H22 );

			Primary = lerp( lerp( P11, P21, FracCoord.x ), lerp( P12, P22, FracCoord.x ), FracCoord.y );
			Secondary = lerp( lerp( S11, S21, FracCoord.x ), lerp( S12, S22, FracCoord.x ), FracCoord.y );
			Highlight = lerp( lerp( H11, H21, FracCoord.x ), lerp( H12, H22, FracCoord.x ), FracCoord.y );
		}

		// Gathers an inverse-distance-weighted average of the owned province colours around
		// Coordinate. As the sample point approaches a province, the result converges to that province's
		// colour. Pixels near a province read as fully that province's, while true midpoints blend.
		//
		// Structure: 16 rays marched outward.
		//
		// Four things to keep the result smooth:
		//  1. Bilinear taps, not point taps. The indirection map stores a palette
		//     *index* in .rg, so its sampler is necessarily Point-filtered and a raw
		//     ColorSample snaps to one indirection texel. COTC_BilinearSampleProvinceColors
		//     interpolates four of them by hand - as CalcPrimaryProvinceOverlay does, and
		//     the reason vanilla province colours do not look blocky.
		//  2. Weighting by Sample.a instead of thresholding it. Alpha is continuous across a 
		//     boundary once sampled bilinearly, so weighting by it is continuous too. It also 
		//     drops theunowned taps' rgb automatically rather than needing to exclude them.
		//  3. Transmittance rather than breaking on first hit. Each ray accumulates through 
		//	   land continuously, so a far province cannot bleed through a near one.
		//  4. Continuous loop exits. Both breaks below test smoothly-varying quantities.
		//
		// OwnedSecondary comes back weighted by exactly the same weights as OwnedColor, so
		// the occupation stripes belong to the same province whose colour
		// it inherited. Its alpha survives the averaging, so an unoccupied dominant
		// neighbour yields alpha ~0 and no stripes are drawn.
		bool COTC_GatherOwnedColor( in float2 Coordinate, out float3 OwnedColor, out float4 OwnedSecondary, out float4 OwnedHighlight )
		{
			OwnedColor = vec3( 0.0f );
			OwnedSecondary = vec4( 0.0f );
			OwnedHighlight = vec4( 0.0f );

			float3 Accumulated = vec3( 0.0f );
			float3 AccumulatedSquared = vec3( 0.0f );
			float4 AccumulatedSecondary = vec4( 0.0f );
			float4 AccumulatedHighlight = vec4( 0.0f );
			float  TotalWeight = 0.0f;

			// Per-texel jitter offset, stable in MAP space rather than screen space so the
			// residual noise stays painted on the map instead of swimming as the camera moves.
			const float Jitter = CalcRandom( floor( Coordinate * IndirectionMapSize ) ) * COTC_FILL_JITTER;

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

					const float ShellNear = COTC_FILL_SHELL_BOUNDS[ Step ];
					const float ShellFar = COTC_FILL_SHELL_BOUNDS[ Step + 1 ];

					// Jittered sample position within this shell, and the shell's thickness.
					const float Distance = lerp( ShellNear, ShellFar, Jitter );
					const float ShellWidth = ShellFar - ShellNear;

					// saturate keeps the search from wrapping to the far side of the map
					const float2 Offset = saturate( Coordinate + Direction * ( Distance * InvIndirectionMapSize ) );

					float4 Sample;
					float4 SecondarySample;
					float4 HighlightSample;
					COTC_BilinearSampleProvinceColors( Offset, Sample, SecondarySample, HighlightSample );

					// Inverse-distance weight, normalised so the nearest possible sample weighs 1.
					const float NormalizedDistance = Distance / COTC_FILL_SHELL_BOUNDS[ 0 ];
					const float DistanceWeight = pow( NormalizedDistance, -COTC_FILL_DISTANCE_POWER );

					// Scaling by the shell thickness turns this sum into a quadrature of the
					// kernel along the ray rather than a bare sum of kernel values. Neighbouring 
					// shells contribute comparable amounts.
					const float Weight = Sample.a * Transmittance * DistanceWeight * ShellWidth;

					Accumulated += Sample.rgb * Weight;
					AccumulatedSquared += Sample.rgb * Sample.rgb * Weight;
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

			// Weighted variance of the gathered colours, per channel. How much do
			// the contributing provinces disagree. Determines darkening.
			const float3 MeanSquared = AccumulatedSquared / TotalWeight;
			const float3 Variance = max( MeanSquared - Mean * Mean, vec3( 0.0f ) );

			// Root of the summed channel variances - the RMS colour spread across the gather.
			const float Disagreement = saturate( sqrt( Variance.r + Variance.g + Variance.b ) * COTC_FILL_SEAM_CONTRAST );

			OwnedColor = lerp( Mean, COTC_FILL_SEAM_COLOR, COTC_FILL_SEAM_STRENGTH * Disagreement );
			OwnedSecondary = AccumulatedSecondary / TotalWeight;
			OwnedHighlight = AccumulatedHighlight / TotalWeight;
			return true;
		}

		// FillStrength is how much of the fill this pixel should receive
		void COTC_ApplySectorFill( inout float3 ProvinceOverlayColor, out float SectorFillAmount, in float2 ColorMapCoords, in float FillStrength )
		{
			SectorFillAmount = 0.0f;

			// Raw palette alpha for this texel: "is anything owned here at all". Fetched
			// before the mask reject on purpose - the tint suppression below has to happen
			// across the whole map, not only inside sector areas.
			const float4 PrimaryColor = BilinearColorSample( ColorMapCoords, IndirectionMapSize, InvIndirectionMapSize, ProvinceColorIndirectionTexture, ProvinceColorTexture );
			const float OwnedAlpha = saturate( PrimaryColor.a );

			// Honour the overlay alpha, which COTC_PS_plane otherwise throws away.
			//
			// CalcPrimaryProvinceOverlay returns rgb = the palette entry scaled by the
			// gradient constants, *independent of alpha*. Vanilla never shows that rgb for an
			// unowned province because it blends by PreLightingBlend / PostLightingBlend,
			// both of which carry the alpha as a factor. COTC_PS_plane ignores those and
			// paints the rgb directly (its alpha comes from the plane mask instead), so an
			// unowned province's default palette colour - a blue tint - renders at full
			// strength.
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
				SectorFillAmount = Strength * COTC_GetMapFilledness();
			}
		}
	]]
}
