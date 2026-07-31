Includes = {
	"cw/camera.fxh"
	"cw/pdxterrain.fxh"
}

PixelShader = {
	# RGB = fog colour, A = fog density
	# Sampled with normalised UVs, so the mask can be authored at any resolution
	TextureSampler COTC_Nebula_Mask
	{
		Index = 43
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		File = "gfx/map/terrain/cotc_nebula_mask.png"
		srgb = yes
	}

	# Seamless tiling cloud used to break up the mask alpha so the fog reads as cloud rather than a smooth blob
	TextureSampler COTC_Nebula_Cloud
	{
		Index = 44
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/map/environment/cotc_nebula_cloud.png"
	}

	Code
	[[
		static const int   COTC_NEBULA_LAYERS    = 8;
		static const float COTC_NEBULA_DENSITY   = 0.65f;

		static const float COTC_NEBULA_CEILING_Y = 20.0f;
		static const float COTC_NEBULA_FLOOR_Y   = -30.0f;

		static const float COTC_NEBULA_CLOUD_TILE_SIZE    = 600.0f;
		static const float COTC_NEBULA_CLOUD_CONTRAST     = 1.0f;
		static const float COTC_NEBULA_CLOUD_LAYER_OFFSET = 0.3f;

		void COTC_ApplyNebula(inout float3 Color, inout float Alpha, float3 WorldSpacePos)
		{
			float3 ToCameraNorm                   = normalize(CameraPosition - WorldSpacePos);
			float  CeilingParallaxDistance        = (COTC_NEBULA_CEILING_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float  FloorParallaxDistance          = (COTC_NEBULA_FLOOR_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float2 CeilingParallaxWorldSpacePosXZ = (WorldSpacePos + CeilingParallaxDistance*ToCameraNorm).xz;
			float2 FloorParallaxWorldSpacePosXZ   = (WorldSpacePos + FloorParallaxDistance*ToCameraNorm).xz;

			float3 AccumColor = float3(0.0f, 0.0f, 0.0f);
			float  AccumAlpha = 0.0f;

			for (int i = 0; i < COTC_NEBULA_LAYERS; i++)
			{
				// Half-step offset so the samples sit at layer centres rather than on the slab edges.
				float  LayerRelativeHeight            = (float(i) + 0.5f)/float(COTC_NEBULA_LAYERS);
				float2 CurrentParallaxWorldSpacePosXZ = lerp(FloorParallaxWorldSpacePosXZ, CeilingParallaxWorldSpacePosXZ, LayerRelativeHeight);

				// Same convention as the plane and starlight masks: normalised world XZ, V flipped.
				float2 MaskUV = CurrentParallaxWorldSpacePosXZ*WorldSpaceToDetail;
				MaskUV.y = 1.0f - MaskUV.y;

				// Lod0: inside a loop the implicit derivatives are meaningless and would mip-flicker.
				float4 MaskSample = PdxTex2DLod0(COTC_Nebula_Mask, MaskUV);

				// Cloud detail, tiled in world space so it stays anchored to the map.
				// The per-layer UV offset keeps the slices from being identical when the
				// camera looks straight down and the parallax spread collapses to zero.
				float2 CloudUV = CurrentParallaxWorldSpacePosXZ/COTC_NEBULA_CLOUD_TILE_SIZE
				               + float(i)*COTC_NEBULA_CLOUD_LAYER_OFFSET;
				float  CloudSample     = PdxTex2DLod0(COTC_Nebula_Cloud, CloudUV).r;
				float  CloudMultiplier = lerp(1.0f - COTC_NEBULA_CLOUD_CONTRAST, 1.0f + COTC_NEBULA_CLOUD_CONTRAST, CloudSample);

				float LayerDensity = MaskSample.a*CloudMultiplier*COTC_NEBULA_DENSITY/float(COTC_NEBULA_LAYERS);

				AccumColor += MaskSample.rgb*LayerDensity;
				AccumAlpha += LayerDensity;
			}

			// Divide by the unclamped weight so the averaged colour stays correct even
			// where the accumulated density saturates.
			float3 NebulaColor = AccumColor/max(AccumAlpha, 1e-4f);
			float  NebulaAlpha = saturate(AccumAlpha);

			Color = lerp(Color, NebulaColor, NebulaAlpha);
			Alpha = lerp(Alpha, 1.0f, NebulaAlpha);
		}
	]]
}
