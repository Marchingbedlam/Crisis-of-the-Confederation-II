PixelShader =
{
	Code
	[[
		// Reproduces CK3's impassable-province colour fill-in for sea zone provinces.
		// The engine's mountain fill-in cannot be extended to water provinces natively.
		//
		// This reimplements the *effect* per-pixel instead: where a sea zone texel has no owner
		// colour of its own, search outward through the indirection map and adopt the colour of
		// the nearest owned province. A pixel shader cannot do a per-province majority vote
		// (that needs a reduction over every texel of the province), so this is a nearest-owner
		// search, which blends toward whichever holder is actually adjacent.
		//
		// Requires ProvinceColorIndirectionTexture / ProvinceColorTexture and the
		// JominiColorMapConstants buffer to already be in scope.

		// --- Sea zone province IDs -----------------------------------------------
		// The `# SEA ZONES` block of live/map_data/default.map.
		// This is a hand-synced duplicate. Any edit to the sea_zones ranges there
		// must be mirrored here or those provinces will stop being filled!
		bool COTC_IsSeaZone( in int ProvinceId )
		{
			return ( ProvinceId >=   58 && ProvinceId <=   59 )		// Helix Nebula
				|| ( ProvinceId >=   94 && ProvinceId <=   96 )		// Witchhead Nebula
				|| ( ProvinceId >=  185 && ProvinceId <=  186 )		// Witchhead Nebula
				|| ( ProvinceId >=  149 && ProvinceId <=  153 )		// Flame Nebula
				|| ( ProvinceId >=  144 && ProvinceId <=  148 )		// Orion Nebula
				|| ( ProvinceId >=  132 && ProvinceId <=  136 )		// Horsehead Nebula
				|| ( ProvinceId >= 2151 && ProvinceId <= 2152 )		// Veil Nebula
				|| ( ProvinceId >=  122 && ProvinceId <=  123 )		// Veil Nebula
				|| ( ProvinceId >=  195 && ProvinceId <=  196 );	// Veil Nebula
		}

		// --- Search kernel -------------------------------------------------------
		// 16 evenly spaced unit directions. Scaled by InvIndirectionMapSize at use, so
		// the radii below are in indirection-map texels and stay correct if the map is
		// ever resized. The indirection map is 1:1 with world XZ, so these are circles
		// in world space too.
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

		// Escalating rings, in indirection-map texels. The first ring that finds any
		// owned neighbour wins, so narrow gaps cost one ring and only wide gaps pay for
		// the outer ones. TUNE THESE to the actual gap width between county circles.
		#define COTC_FILL_RING_COUNT 4
		static const float COTC_FILL_RING_RADII[COTC_FILL_RING_COUNT] =
		{
			8.0f, 20.0f, 44.0f, 92.0f,
		};

		static const float COTC_FILL_OWNED_ALPHA_THRESHOLD = 0.5f;

		// Averages every owned hit in the first ring that produces one. Averaging rather
		// than taking the first hit keeps the boundary between two equidistant realms a
		// blend instead of a hard seam.
		bool COTC_FindNearestOwnedColor( in float2 Coordinate, out float3 OwnedColor )
		{
			OwnedColor = vec3( 0.0f );

			for ( int Ring = 0; Ring < COTC_FILL_RING_COUNT; ++Ring )
			{
				const float2 Radius = COTC_FILL_RING_RADII[ Ring ] * InvIndirectionMapSize;

				float3 Accumulated = vec3( 0.0f );
				float  HitCount = 0.0f;

				for ( int i = 0; i < 16; ++i )
				{
					// saturate keeps the search from wrapping to the far side of the map
					const float2 Offset = saturate( Coordinate + COTC_FILL_DIRECTIONS[ i ] * Radius );
					const float4 Sample = ColorSample( Offset, ProvinceColorIndirectionTexture, ProvinceColorTexture );

					if ( Sample.a > COTC_FILL_OWNED_ALPHA_THRESHOLD )
					{
						Accumulated += Sample.rgb;
						HitCount += 1.0f;
					}
				}

				if ( HitCount > 0.0f )
				{
					OwnedColor = Accumulated / HitCount;
					return true;
				}
			}

			return false;
		}

		void COTC_ApplySeaZoneFill( inout float3 ProvinceOverlayColor, in float2 ColorMapCoords, in float HeightFactor )
		{
			if ( HeightFactor <= 0.0f )
			{
				return;
			}

			// Already owned - the overlay colour is correct, and this is the common case
			// for every land pixel on the map.
			const float4 PrimaryColor = ColorSample( ColorMapCoords, ProvinceColorIndirectionTexture, ProvinceColorTexture );
			if ( PrimaryColor.a > 0.0f )
			{
				return;
			}

			// Sea zones only. Keeps the empty-space wasteland provinces black.
			const int ProvinceId = SampleProvinceId( ColorMapCoords, ProvinceColorIndirectionTexture );
			if ( !COTC_IsSeaZone( ProvinceId ) )
			{
				return;
			}

			float3 OwnedColor;
			if ( COTC_FindNearestOwnedColor( ColorMapCoords, OwnedColor ) )
			{
				ProvinceOverlayColor = OwnedColor;
			}
		}
	]]
}
