Includes = {
	"cw/pdxterrain.fxh"
	"cw/pdxmesh.fxh"
	"cw/utility.fxh"
	"cw/shadow.fxh"
	"cw/camera.fxh"
	"cw/heightmap.fxh"
	"jomini/jomini_fog.fxh"
	"jomini/map_lighting.fxh"
	"jomini/jomini_fog_of_war.fxh"
	"jomini/jomini_water.fxh"
	"jomini/jomini_mapobject.fxh"
	"jomini/translucency.fxh"
	"constants.fxh"
	"standardfuncsgfx.fxh"
	"shadow_tint.fxh"
	"lowspec.fxh"
	"dynamic_masks.fxh"
	"liquid.fxh"
	"clouds.fxh"
	"province_effects.fxh"
	#MOD(COTC)
	"jomini/jomini_province_overlays.fxh"
	"bordercolor.fxh"
	"cotc_overrides.fxh"
	"cotc_utilities.fxh"
	"generated/cotc_starlight_coord.fxh"
	#END MOD
}

PixelShader =
{
	TextureSampler DiffuseMap
	{
		Index = 0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler PropertiesMap
	{
		Index = 1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler NormalMap
	{
		Index = 2
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}

	TextureSampler AtmosphereMap
    {
		Index = 3
        MagFilter = "Linear"
        MinFilter = "Linear"
        MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
    }

	TextureSampler EnvironmentMap
	{
		Ref = JominiEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler ShadowTexture
	{
		Ref = PdxShadowmap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		CompareFunction = less_equal
		SamplerType = "Compare"
	}

	TextureSampler COTC_Plane_Mask
	{
		Index = 40
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		File = "gfx/map/terrain/cotc_plane_mask.png"
		#srgb = yes
	}

	TextureSampler COTC_Starlight_Mask
	{
		Index = 41
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		File = "gfx/map/terrain/cotc_starlight_mask.png"
		#srgb = yes
	}

	# Baked RGB-mask -> XYZ coordinate lookup table (see generated/cotc_starlight_coord.fxh).
	TextureSampler COTC_Starlight_Coord_LUT
	{
		Index = 42
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		File = "gfx/FX/generated/cotc_starlight_coord_lut.dds"
	}

	# MOD(map-skybox)
	TextureSampler SkyboxSample
	{
		Index = 4
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
		File = "gfx/map/environment/SkyBox.dds"
		srgb = yes
	}
	# END MOD

	TextureSampler FogOfWarAlpha
	{
		Ref = JominiFogOfWar
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler FlagTexture
	{
		Ref = PdxMeshCustomTexture0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
}

VertexStruct VS_OUTPUT
{
    float4 Position			: PDX_POSITION;
	float3 Normal			: TEXCOORD0;
	float3 Tangent			: TEXCOORD1;
	float3 Bitangent		: TEXCOORD2;
	float2 UV0				: TEXCOORD3;
	float2 UV1				: TEXCOORD4;
	float3 WorldSpacePos	: TEXCOORD5;
	uint InstanceIndex 	: TEXCOORD6;
};

VertexShader =
{
	Code
	[[
		VS_OUTPUT ConvertOutput( VS_OUTPUT_PDXMESH In )
		{
			VS_OUTPUT Out;

			Out.Position = In.Position;
			Out.Normal = In.Normal;
			Out.Tangent = In.Tangent;
			Out.Bitangent = In.Bitangent;
			Out.UV0 = In.UV0;
			Out.UV1 = In.UV1;
			Out.WorldSpacePos = In.WorldSpacePos;

			#if defined( SELECTION_MARKER )
				float2 UV = Out.UV0;
				float Rotation = GlobalTime * 1.0f;
				float mid = 0.5f;

				// rotation
				Out.UV0 = float2(
					cos( Rotation ) * ( UV.x - mid ) + sin( Rotation ) * ( UV.y - mid ) + mid,
					cos( Rotation ) * ( UV.y - mid ) - sin( Rotation ) * ( UV.x - mid ) + mid
				);
			#endif

			return Out;
		}
	]]

	MainCode COTC_VS_standard
	{
		Input = "VS_INPUT_PDXMESHSTANDARD"
		Output = "VS_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT Out = ConvertOutput( PdxMeshVertexShaderStandard( Input ) );
				Out.InstanceIndex = Input.InstanceIndices.y;
				return Out;
			}
		]]
	}

	MainCode COTC_VS_mapobject
	{
		Input = "VS_INPUT_PDXMESH_MAPOBJECT"
		Output = "VS_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT Out = ConvertOutput( PdxMeshVertexShader( PdxMeshConvertInput( Input ), 0/*Skinning data not supported*/, UnpackAndGetMapObjectWorldMatrix( Input.InstanceIndex24_Opacity8 ) ) );
				Out.InstanceIndex = Input.InstanceIndex24_Opacity8;
				return Out;
			}
		]]
	}
}

PixelShader =
{
	Code
	[[
		static const float COTC_STAR_EMISSIVE_BOOST       = 4.0f;
		static const float COTC_BLACK_HOLE_EMISSIVE_BOOST = 5.0f;

		// Pack an 8-bit RGB triple (0-255) into a single 24-bit key.
		uint PackColorKey( uint3 StarlightRgb )
		{
			return ( StarlightRgb.r << 16 ) | ( StarlightRgb.g << 8 ) | StarlightRgb.b;
		}

		// Wang-style finalizer
		// MUST stay bit-identical to hash_color_key() in bake_starlight.py
		uint HashColorKey( uint Key )
		{
			Key = ( Key ^ 61u ) ^ ( Key >> 16 );
			Key *= 9u;
			Key = Key ^ ( Key >> 4 );
			Key *= 0x27d4eb2du;
			Key = Key ^ ( Key >> 15 );
			return Key;
		}

		// Center-of-texel UV for a linear slot index. RowOffset picks the band:
		// 0 = key, STARLIGHT_LUT_ROWS = data0, 2*STARLIGHT_LUT_ROWS = data1.
		float2 StarlightLUTSlotUV( uint Slot, uint RowOffset )
		{
			uint x = Slot % STARLIGHT_LUT_W;
			uint y = Slot / STARLIGHT_LUT_W + RowOffset;
			return ( float2( x, y ) + 0.5f ) / float2( STARLIGHT_LUT_W, STARLIGHT_LUT_ROWS * STARLIGHT_LUT_BANDS );
		}

		// Reassemble a 16-bit unsigned value from a (low, high) byte pair.
		uint Unpack16( float Lo, float Hi )
		{
			return (uint)round( Lo * 255.0f ) + ( (uint)round( Hi * 255.0f ) << 8 );
		}

		float3 LookupStarlightCoord( uint3 StarlightRgb )
		{
			float3 StarCoord = float3( 0.0f, 0.0f, 0.0f );

			uint Key  = PackColorKey( StarlightRgb );
			uint Slot = HashColorKey( Key ) & STARLIGHT_LUT_TABLE_MASK;

			for ( uint i = 0u; i <= STARLIGHT_LUT_TABLE_MASK; ++i )
			{
				float4 KeyTexel = PdxTex2DLod0( COTC_Starlight_Coord_LUT, StarlightLUTSlotUV( Slot, 0u ) );

				if ( KeyTexel.a < 0.5f )
				{
					return StarCoord; // empty slot -> starlight not in table
				}

				uint3 StoredRGB = (uint3)round( KeyTexel.rgb * 255.0f );
				if ( all( StoredRGB == StarlightRgb ) )
				{
					float4 Data0 = PdxTex2DLod0( COTC_Starlight_Coord_LUT, StarlightLUTSlotUV( Slot, STARLIGHT_LUT_ROWS ) );
					float4 Data1 = PdxTex2DLod0( COTC_Starlight_Coord_LUT, StarlightLUTSlotUV( Slot, STARLIGHT_LUT_ROWS * 2u ) );
					StarCoord = float3(
						Unpack16( Data0.r, Data0.g ),   // X
						Unpack16( Data0.b, Data0.a ),   // Y
						Unpack16( Data1.r, Data1.g ) ); // Z
					return StarCoord;
				}

				Slot = ( Slot + 1u ) & STARLIGHT_LUT_TABLE_MASK; // wrap around
			}

			return StarCoord;
		}
	]]

	MainCode COTC_PS_plane
	{
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			#ifndef DIFFUSE_UV_SET
				#define DIFFUSE_UV_SET Input.UV0
			#endif

			PDX_MAIN
			{
				float2 ColorMapCoords =  Input.WorldSpacePos.xz *  WorldSpaceToTerrain0To1;
				float HeightFactor = COTC_GetHeightBasedAlpha();
				float ProvinceStrength = 1.0f - HeightFactor;

				float3 ProvinceOverlayColor;
				float PreLightingBlend;
				float PostLightingBlend;
				GetProvinceOverlayAndBlend( ColorMapCoords, ProvinceOverlayColor, PreLightingBlend, PostLightingBlend );
				float2 DetailCoordinates = Input.WorldSpacePos.xz * WorldSpaceToDetail;
				DetailCoordinates.y = 1.0f - DetailCoordinates.y;
				float4 PlaneMask = PdxTex2DLod0( COTC_Plane_Mask, DetailCoordinates );

				int StarLayerMult = 2;
				float Alpha = lerp(PlaneMask.a / 3, 0.0f, ProvinceStrength);
				float3 Color = lerp(ProvinceOverlayColor, 0.0f, ProvinceStrength);
				float CloudMaskValue = PlaneMask.r;
				float SystemMaskValue = PlaneMask.g;
				float SectorMaskValue = PlaneMask.b;

				if ( CloudMaskValue > 0.0f )
				{
					Color = float3(0.1f, 0.1f, 0.15f);
				}

				if(HeightFactor == 1.0)
				{
					if ( SystemMaskValue > 0.0f )
					{
						StarLayerMult = 8;
					}

					if ( SectorMaskValue > 0.0f )
					{
						StarLayerMult = 3;
					}
				}
				else
				{
					StarLayerMult = 2;
				}

				COTC_ApplyHighlightColor(Color, ColorMapCoords);
				COTC_ApplyBackgroundEffects( Color, Alpha, Input.WorldSpacePos, StarLayerMult );

				return float4(Color, Alpha);
			}
		]]
	}
	MainCode COTC_PS_background
	{
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			#ifndef DIFFUSE_UV_SET
				#define DIFFUSE_UV_SET Input.UV0
			#endif

			PDX_MAIN
			{
				float2 DetailCoordinates = Input.WorldSpacePos.xz * WorldSpaceToDetail;
				DetailCoordinates.y = 1.0f - DetailCoordinates.y;
				float4 PlaneMask = PdxTex2DLod0( COTC_Plane_Mask, DetailCoordinates );
				float2 ColorMapCoords =  Input.WorldSpacePos.xz *  WorldSpaceToTerrain0To1;
				float HeightFactor = COTC_GetHeightBasedAlpha();
				float ProvinceStrength = 1.0f - HeightFactor;
				int StarLayerMult = 2;

				float4 Diffuse = PdxTex2D( DiffuseMap, DIFFUSE_UV_SET );
				float3 Color = Diffuse.rgb;
				float Alpha = Diffuse.a - 0.1;
				float CloudMaskValue = PlaneMask.r;
				float SystemMaskValue = PlaneMask.g;
				float SectorMaskValue = PlaneMask.b;

				if(PlaneMask.a > 0.0)
				{
					Alpha = lerp(Alpha, 0.0f, PlaneMask.a);
				}

				return float4(Color, Alpha);
			}
		]]
	}

	MainCode COTC_PS_black_hole
	{
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			#ifndef DIFFUSE_UV_SET
				#define DIFFUSE_UV_SET Input.UV0
			#endif

			PDX_MAIN
			{
				float2 ColorMapCoords =  Input.WorldSpacePos.xz *  WorldSpaceToTerrain0To1;
				float ProvinceStrength = COTC_GetHeightBasedAlpha();
				float Alpha = 1.0;
				float3 Color = float3(0,0,0);
				float3 ProvinceOverlayColor;
				float PreLightingBlend;
				float PostLightingBlend;
				GetProvinceOverlayAndBlend( ColorMapCoords, ProvinceOverlayColor, PreLightingBlend, PostLightingBlend );

				#if defined( COTC_OUTER_FRESNEL ) || defined( COTC_INNER_FRESNEL )
					float4 FresnelColor = PdxTex2D( AtmosphereMap, DIFFUSE_UV_SET );
					float3 ToCameraDir = normalize( Input.WorldSpacePos.xyz - CameraPosition );

					// Exterior
					#if defined( COTC_OUTER_FRESNEL )
						float FresnelFactor = saturate( Fresnel( abs( dot( ToCameraDir, Input.Normal ) ), 0.1f, 0.1f) );
						Alpha = Alpha - FresnelFactor;
						Color = lerp( FresnelColor.rgb, ProvinceOverlayColor, ProvinceStrength );
					#endif

					// Interior
					#if defined( COTC_INNER_FRESNEL )
						float FresnelFactor = saturate( Fresnel( abs( dot( ToCameraDir, Input.Normal ) ), 0.1f, 8.0f - ProvinceStrength ) - 0.1 );
						FresnelColor.rgb = lerp( FresnelColor.rgb, ProvinceOverlayColor, ProvinceStrength );
						Color = lerp( Color, FresnelColor, FresnelFactor );
					#endif
				#endif

				// After the fresnel block, because the outer pass replaces Color outright.
				// Before the highlight, so selection stays a tint instead of a blown-out flare.
				#if defined( COTC_EMISSIVE_BLACK_HOLE )
					Color *= COTC_BLACK_HOLE_EMISSIVE_BOOST;
				#endif

				COTC_ApplyHighlightColor(Color, ColorMapCoords);

				return float4( Color, Alpha );
			}
		]]
	}

	MainCode COTC_PS_standard
	{
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			void DebugReturn( inout float3 Out, SMaterialProperties MaterialProps, SLightingProperties LightingProps, PdxTextureSamplerCube EnvironmentMap, float3 ScatteringColor, float ScatteringMask, float3 DiffuseTranslucency )
			{
				#if defined( PDX_DEBUG_SCATTERING_MASK )
					Out = ScatteringMask;
				#elif defined( PDX_DEBUG_SCATTERING_COLOR )
					Out = ScatteringColor;
				#elif defined( PDX_DEBUG_TRANSLUCENCY )
					Out = DiffuseTranslucency;
				#else
					// DebugReturn( Out, MaterialProps, LightingProps, EnvironmentMap );
				#endif
			}

			#if defined( ATLAS )
				#ifndef DIFFUSE_UV_SET
					#define DIFFUSE_UV_SET Input.UV1
				#endif

				#ifndef NORMAL_UV_SET
					#define NORMAL_UV_SET Input.UV1
				#endif

				#ifndef PROPERTIES_UV_SET
					#define PROPERTIES_UV_SET Input.UV1
				#endif

				#ifndef UNIQUE_UV_SET
					#define UNIQUE_UV_SET Input.UV0
				#endif
			#else
				#ifndef DIFFUSE_UV_SET
					#define DIFFUSE_UV_SET Input.UV0
				#endif

				#ifndef NORMAL_UV_SET
					#define NORMAL_UV_SET Input.UV0
				#endif

				#ifndef PROPERTIES_UV_SET
					#define PROPERTIES_UV_SET Input.UV0
				#endif
			#endif
			#if defined( COA )
				#ifndef UNIQUE_UV_SET
					#define UNIQUE_UV_SET Input.UV1
				#endif
			#endif

			PDX_MAIN
			{
				float4 Diffuse = PdxTex2D( DiffuseMap, DIFFUSE_UV_SET );
				
				float4 Properties = PdxTex2D( PropertiesMap, PROPERTIES_UV_SET );
				#if defined( LOW_SPEC_SHADERS )
					float3 Normal = Input.Normal;
				#else
					float3 NormalSample = UnpackRRxGNormal( PdxTex2D( NormalMap, NORMAL_UV_SET ) );
				
					float3x3 TBN = Create3x3( normalize( Input.Tangent ), normalize( Input.Bitangent ), normalize( Input.Normal ) );
					float3 Normal = normalize( mul( NormalSample, TBN ) );
				#endif

				float2 ColorMapCoords =  Input.WorldSpacePos.xz *  WorldSpaceToTerrain0To1;

				SMaterialProperties MaterialProps = GetMaterialProperties( Diffuse.rgb, Normal, Properties.a, Properties.g, Properties.b );
				float ProvinceStrength = COTC_GetHeightBasedAlpha();
				float Alpha = Diffuse.a;
				float3 Color;
				SLightingProperties LightingProps;

				#if defined( COTC_NO_SHADOW )
					LightingProps = GetSunLightingProperties( Input.WorldSpacePos, ShadowTexture );
					Color = COTC_CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap, ProvinceStrength );
				#else
					float2 DetailCoordinates = Input.WorldSpacePos.xz * WorldSpaceToDetail;
					DetailCoordinates.y = 1.0f - DetailCoordinates.y;
					float4 StarlightMask = PdxTex2DLod0( COTC_Starlight_Mask, DetailCoordinates );
					uint3 StarlightRgb = (uint3)round( saturate( StarlightMask.rgb ) * 255.0f );
					float3 StarlightPos = LookupStarlightCoord( StarlightRgb );

					LightingProps = COTC_GetSunLightingProperties( Input.WorldSpacePos, StarlightPos, ShadowTexture );
					Color = COTC_CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap, 1.0 );
				#endif

				float3 ProvinceOverlayColor;
				float PreLightingBlend;
				float PostLightingBlend;
				GetProvinceOverlayAndBlend( ColorMapCoords, ProvinceOverlayColor, PreLightingBlend, PostLightingBlend );
				float3 ToCameraDir = normalize( Input.WorldSpacePos.xyz - CameraPosition );

				#if defined( COTC_HEX )
					Alpha = Alpha * ProvinceStrength;
				#endif

				#if defined( COTC_OUTER_FRESNEL ) || defined( COTC_INNER_FRESNEL )
					float4 AtmoColor = PdxTex2D( AtmosphereMap, DIFFUSE_UV_SET );

					float InSun = lerp(saturate( dot( LightingProps._ToLightDir, Input.Normal ) ), 1.0f, ProvinceStrength);

					// Exterior
					#if defined( COTC_OUTER_FRESNEL )
						float FresnelFactor = saturate( Fresnel( abs( dot( ToCameraDir, Input.Normal ) ), 0.5f, 0.8f) );
						Alpha = Alpha - FresnelFactor;
						Color = lerp( AtmoColor, ProvinceOverlayColor, ProvinceStrength );
					#endif

					// Interior
					#if defined( COTC_INNER_FRESNEL )
						float FresnelFactor = saturate( Fresnel( abs( dot( ToCameraDir, Input.Normal ) ), 0.1f, 2.0f - ProvinceStrength ) * InSun );
						AtmoColor.rgb = lerp( AtmoColor.rgb, ProvinceOverlayColor, ProvinceStrength );
						Color = lerp( Color, AtmoColor.rgb, FresnelFactor );
					#endif
				#endif

				// After the fresnel block, because the atmosphere pass replaces Color outright.
				// Before the highlight, so selection stays a tint instead of a blown-out flare.
				#if defined( COTC_EMISSIVE_STAR )
					Color *= COTC_STAR_EMISSIVE_BOOST;
				#endif

				COTC_ApplyHighlightColor(Color, ColorMapCoords);

				return float4( Color, Alpha );
			}
		]]
	}
}

DepthStencilState DepthStencilState
{
	StencilEnable = yes
}

BlendState alpha_to_coverage
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
	AlphaToCoverage = yes
}

Effect cotc_planet
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_INNER_FRESNEL" }
	DepthStencilState = DepthStencilState
}	

Effect cotc_planet_city
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_INNER_FRESNEL" "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}	

Effect cotc_planet_atmosphere
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_OUTER_FRESNEL" "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}

Effect cotc_star
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" "COTC_EMISSIVE_STAR" }
	DepthStencilState = DepthStencilState
}

Effect cotc_star_atmosphere
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_OUTER_FRESNEL" "COTC_NO_SHADOW" "COTC_EMISSIVE_STAR" }
	DepthStencilState = DepthStencilState
}

Effect cotc_black_hole
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_black_hole"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_INNER_FRESNEL" "COTC_NO_SHADOW" "COTC_EMISSIVE_BLACK_HOLE" }
	DepthStencilState = DepthStencilState
}

Effect cotc_black_hole_outer
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_black_hole"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_OUTER_FRESNEL" "COTC_NO_SHADOW" "COTC_EMISSIVE_BLACK_HOLE" }
	DepthStencilState = DepthStencilState
}

Effect cotc_standard
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}

Effect cotc_standard_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}

Effect cotc_standard_selection_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}

Effect cotc_background
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_background"
	BlendState = "alpha_to_coverage"
}

Effect cotc_background_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_background"
	BlendState = "alpha_to_coverage"
}

Effect cotc_background_selection_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_background"
	BlendState = "alpha_to_coverage"
}

Effect cotc_hex
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" "COTC_HEX" }
	DepthStencilState = DepthStencilState
}

Effect cotc_hex_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" "COTC_HEX" }
	DepthStencilState = DepthStencilState
}

Effect cotc_hex_selection_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" "COTC_HEX" }
	DepthStencilState = DepthStencilState
}

Effect cotc_plane
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_plane"
	BlendState = "alpha_to_coverage"
	DepthStencilState = DepthStencilState
}

Effect cotc_plane_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_plane"
	BlendState = "alpha_to_coverage"
	DepthStencilState = DepthStencilState
}

Effect cotc_plane_selection_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_plane"
	BlendState = "alpha_to_coverage"
	DepthStencilState = DepthStencilState
}