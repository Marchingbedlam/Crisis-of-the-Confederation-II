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

	Code
	[[
		//
		// Config
		//

		static const int   COTC_NEBULA_LAYERS    = 8;
		static const float COTC_NEBULA_DENSITY   = 0.8f;

		static const float COTC_NEBULA_CEILING_Y = 20.0f;
		static const float COTC_NEBULA_FLOOR_Y   = -20.0f;

		// Regional volumetric fog
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

				float LayerDensity = MaskSample.a*COTC_NEBULA_DENSITY/float(COTC_NEBULA_LAYERS);

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
