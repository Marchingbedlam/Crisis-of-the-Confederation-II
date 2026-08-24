Includes = {
	"cw/lighting_util.fxh"
	"cw/lighting.fxh"
	"cw/shadow.fxh"
	"jomini/jomini.fxh"
	"constants.fxh"
	"cw/random.fxh"
	"cotc_camera_utils.fxh"
}

PixelShader = 
{
	Code
	[[
		float4 COTC_GetHighlightColor( in float2 WorldSpacePosXZ )
		{
			float4 HighlightColor = BilinearColorSampleAtOffset( WorldSpacePosXZ, IndirectionMapSize, InvIndirectionMapSize, ProvinceColorIndirectionTexture, ProvinceColorTexture, HighlightProvinceColorsOffset );

			float3 Saturated = vec3( ( HighlightColor.r + HighlightColor.g + HighlightColor.b ) * 2 );
			HighlightColor.rgb = lerp( HighlightColor.rgb, Saturated, 0.1 );

			return HighlightColor;
		}

		static const float COTC_HIGHLIGHT_FADE_KNEE = 0.15f;

		// Applies an already-sampled highlight colour. Split out from COTC_ApplyHighlightColor so
		// the sea fill can reuse the exact same intensity and fade maths on a highlight colour it
		// gathered from a neighbouring province rather than from this texel.
		void COTC_ApplyHighlightColorValue( inout float3 Diffuse, in float4 HighlightColor )
		{
			// Faded on the shared zoom step, so the highlight goes with the colours instead of surviving them
			float ZoomFade = COTC_GetMapZoomFade();
			ZoomFade = saturate( ( ZoomFade - COTC_HIGHLIGHT_FADE_KNEE ) / ( 1.0f - COTC_HIGHLIGHT_FADE_KNEE ) );

			// Fade applied OUTSIDE the saturate deliberately for proportional fade
			const float Highlight = saturate( HighlightColor.a * MapHighlightIntensity * 2.0f ) * ZoomFade;

			Diffuse = lerp( Diffuse, HighlightColor.rgb, Highlight );
		}

		void COTC_ApplyHighlightColor( inout float3 Diffuse, in float2 WorldSpacePosXZ )
		{
			COTC_ApplyHighlightColorValue( Diffuse, COTC_GetHighlightColor( WorldSpacePosXZ ) );
		}

		void COTC_CalculateLightingFromLight( SMaterialProperties MaterialProps, float3 ToCameraDir, float3 ToLightDir, float3 LightIntensity, float ShadowStrength, out float3 DiffuseOut, out float3 SpecularOut )
		{
			float3 H = normalize( ToCameraDir + ToLightDir );
			float NdotV = saturate( dot( MaterialProps._Normal, ToCameraDir ) ) + 1e-5;
			float RawNdotL = dot( MaterialProps._Normal, ToLightDir );
			float TerminatorSoftness = 0.5f;
			float NdotL = smoothstep( -TerminatorSoftness, 3.0f, RawNdotL);
			float NdotH = saturate( dot( MaterialProps._Normal, H ) );
			float LdotH = saturate( dot( ToLightDir, H ) );
			
			float DiffuseBRDF = CalcDiffuseBRDF( NdotV, NdotL, LdotH, MaterialProps._PerceptualRoughness );

			#ifdef COTC_NO_SHADOW
				NdotL = 1.0f;
			#endif

			DiffuseOut = DiffuseBRDF * MaterialProps._DiffuseColor * LightIntensity * NdotL;
				
			#ifdef PDX_HACK_ToSpecularLightDir
				float3 H_Spec = normalize( ToCameraDir + PDX_HACK_ToSpecularLightDir );
				float NdotL_Spec = saturate( dot( MaterialProps._Normal, PDX_HACK_ToSpecularLightDir ) ) + 1e-5;
				float NdotH_Spec = saturate( dot( MaterialProps._Normal, H_Spec ) );
				float LdotH_Spec = saturate( dot( PDX_HACK_ToSpecularLightDir, H_Spec ) );
				float3 SpecularBRDF = CalcSpecularBRDF( MaterialProps._SpecularColor, LdotH_Spec, NdotH_Spec, NdotL_Spec, NdotV, MaterialProps._Roughness );
				SpecularOut = SpecularBRDF * LightIntensity * NdotL;
			#else
				float3 SpecularBRDF = CalcSpecularBRDF( MaterialProps._SpecularColor, LdotH, NdotH, NdotL, NdotV, MaterialProps._Roughness );
				SpecularOut = SpecularBRDF * LightIntensity * NdotL;
			#endif
		}
		
		void COTC_CalculateLightingFromLight( SMaterialProperties MaterialProps, SLightingProperties LightingProps, float ShadowStrength, out float3 DiffuseOut, out float3 SpecularOut )
		{
			COTC_CalculateLightingFromLight( MaterialProps, LightingProps._ToCameraDir, LightingProps._ToLightDir, LightingProps._LightIntensity * LightingProps._ShadowTerm, ShadowStrength, DiffuseOut, SpecularOut );
		}

		// Generate the texture co-ordinates for a PCF kernel
		void COTC_CalculateCoordinates( float2 ShadowCoord, inout float2 TexCoords[5] )
		{
			// Generate the texture co-ordinates for the specified depth-map size
			TexCoords[0] = ShadowCoord + float2( -KernelScale, 0.0f );
			TexCoords[1] = ShadowCoord + float2( 0.0f, KernelScale );
			TexCoords[2] = ShadowCoord + float2( KernelScale, 0.0f );
			TexCoords[3] = ShadowCoord + float2( 0.0f, -KernelScale );
			TexCoords[4] = ShadowCoord;
		}
		
		float COTC_CalculateShadow( float4 ShadowProj, PdxTextureSampler2D ShadowMap )
		{
			ShadowProj.xyz = ShadowProj.xyz / ShadowProj.w;
			
			float2 TexCoords[5];
			COTC_CalculateCoordinates( ShadowProj.xy, TexCoords );
			
			// Sample each of them checking whether the pixel under test is shadowed or not
			float fShadowTerm = 0.0f;
			for( int i = 0; i < 5; i++ )
			{				
				float A = PdxTex2DLod0( ShadowMap, TexCoords[i] ).r;
				float B = ShadowProj.z - Bias;
				
				// Texel is shadowed
				fShadowTerm += ( A < 0.99f && A < B ) ? 0.0 : 1.0;
			}
			
			// Get the average
			fShadowTerm = fShadowTerm / 5.0f;
			return lerp( 1.0, fShadowTerm, ShadowFadeFactor );
		}
		
		float2 COTC_RotateDisc( float2 Disc, float2 Rotate )
		{
			return float2( Disc.x * Rotate.x - Disc.y * Rotate.y, Disc.x * Rotate.y + Disc.y * Rotate.x );
		}
		
		float COTC_CalculateShadow( float4 ShadowProj, PdxTextureSampler2DCmp ShadowMap )
		{
			ShadowProj.xyz = ShadowProj.xyz / ShadowProj.w;

			float RandomAngle = CalcRandom( round( ShadowScreenSpaceScale * ShadowProj.xy ) ) * 3.14159 * 2.0;
			float2 Rotate = float2( cos( RandomAngle ), sin( RandomAngle ) );

			// Sample each of them checking whether the pixel under test is shadowed or not
			float ShadowTerm = 0.0;
			for( int i = 0; i < NumSamples; i++ )
			{
				float4 Samples = DiscSamples[i] * KernelScale;
				ShadowTerm += PdxTex2DCmpLod0( ShadowMap, ShadowProj.xy + COTC_RotateDisc( Samples.xy, Rotate ), ShadowProj.z - Bias );
				ShadowTerm += PdxTex2DCmpLod0( ShadowMap, ShadowProj.xy + COTC_RotateDisc( Samples.zw, Rotate ), ShadowProj.z - Bias );
			}

			// Get the average
			ShadowTerm *= 0.5; // We have 2 samples per "sample"
			ShadowTerm = ShadowTerm / float(NumSamples);
			
			float3 FadeFactor = saturate( float3( 1.0 - abs( 0.5 - ShadowProj.xy ) * 2.0, 1.0 - ShadowProj.z ) * 32.0 ); // 32 is just a random strength on the fade
			ShadowTerm = lerp( 1.0, ShadowTerm, min( min( FadeFactor.x, FadeFactor.y ), FadeFactor.z ) );

			return lerp( 1.0, ShadowTerm, ShadowFadeFactor );
		}

		float3 COTC_CalculateSunLighting( SMaterialProperties MaterialProps, SLightingProperties LightingProps, PdxTextureSamplerCube EnvironmentMap, float ShadowStrength )
		{
			SLightingProperties LightingPropsNoShadow = LightingProps;
			LightingPropsNoShadow._ShadowTerm = 1.0;

			float3 DiffuseLight;
			float3 SpecularLight;
			COTC_CalculateLightingFromLight( MaterialProps, LightingProps, ShadowStrength, DiffuseLight, SpecularLight );
			
			float3 DiffuseIBL;
			float3 SpecularIBL;
			CalculateLightingFromIBL( MaterialProps, LightingProps, EnvironmentMap, DiffuseIBL, SpecularIBL );
			
			return DiffuseLight + SpecularLight + DiffuseIBL + SpecularIBL;
		}

		SLightingProperties COTC_GetSunLightingProperties( float3 WorldSpacePos, float3 LightPos, float ShadowTerm )
		{
			SLightingProperties LightingProps;
			LightingProps._ToCameraDir = normalize( CameraPosition - WorldSpacePos );
			LightingProps._ToLightDir = normalize( LightPos - WorldSpacePos );
			LightingProps._LightIntensity = SunDiffuse * SunIntensity;
			LightingProps._ShadowTerm = ShadowTerm;
			LightingProps._CubemapIntensity = CubemapIntensity;
			LightingProps._CubemapYRotation = CubemapYRotation;
			
			return LightingProps;
		}
		
		SLightingProperties COTC_GetSunLightingProperties( float3 WorldSpacePos, float3 LightPos, PdxTextureSampler2DCmp ShadowMap )
		{
			float4 ShadowProj = mul( ShadowMapTextureMatrix, float4( WorldSpacePos, 1.0 ) );
			float ShadowTerm = COTC_CalculateShadow( ShadowProj, ShadowMap );
			return COTC_GetSunLightingProperties( WorldSpacePos, LightPos, ShadowTerm );
		}
	]]
}
