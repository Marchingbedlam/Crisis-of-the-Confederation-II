Includes = {
	"cw/camera.fxh"
	"cw/pdxterrain.fxh"
	"cotc_compositing.fxh"
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
		# Uncompressed DDS with no mip chain, so the texture quality setting cannot degrade it
		File = "gfx/map/terrain/cotc_nebula_mask.dds"
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
		# Uncompressed DDS with no mip chain, so the texture quality setting cannot degrade it
		File = "gfx/map/environment/cotc_nebula_cloud.dds"
	}

	Code
	[[
		// A define, not a static const, so it can size the table and the unroll hint
		#define COTC_NEBULA_LAYERS 24
		static const float COTC_NEBULA_DENSITY   = 0.3f;

		static const float COTC_NEBULA_CEILING_Y = 5.0f;
		static const float COTC_NEBULA_FLOOR_Y   = -5.0f;

		static const float COTC_NEBULA_CLOUD_CONTRAST  = 2.0f;

		// Per-layer variation of the cloud texture
		// The values are arbitrary; change any of them freely:
		// rotation (deg), tile size, offset x, offset y
		static const float4 COTC_NEBULA_CLOUD_LAYERS[COTC_NEBULA_LAYERS] =
		{
			float4(  252.3f,  421.5f, 0.43f, 0.51f ),
			float4(  119.1f,  491.4f, 0.25f, 0.57f ),
			float4(   89.1f,  380.6f, 0.80f, 0.52f ),
			float4(  322.2f,  377.9f, 0.53f, 0.82f ),
			float4(  290.2f,  389.3f, 0.97f, 0.98f ),
			float4(  216.1f,  338.5f, 0.73f, 0.63f ),
			float4(  354.5f,  366.4f, 0.51f, 0.47f ),
			float4(  271.6f,  431.9f, 0.10f, 0.29f ),
			float4(  285.0f,  310.9f, 0.38f, 0.97f ),
			float4(  176.0f,  477.7f, 0.94f, 0.24f ),
			float4(  329.8f,  412.7f, 0.99f, 0.15f ),
			float4(   38.1f,  400.5f, 0.56f, 0.78f ),
			float4(   81.2f,  335.2f, 0.49f, 0.94f ),
			float4(  269.4f,  311.1f, 0.25f, 0.10f ),
			float4(   84.5f,  439.9f, 0.40f, 0.82f ),
			float4(  119.6f,  450.9f, 0.58f, 0.74f ),
			float4(  279.5f,  490.7f, 0.52f, 0.59f ),
			float4(  140.5f,  323.7f, 0.04f, 0.19f ),
			float4(  290.2f,  317.7f, 0.32f, 0.91f ),
			float4(   42.0f,  363.1f, 0.94f, 0.38f ),
			float4(  169.1f,  352.5f, 0.15f, 0.89f ),
			float4(  255.1f,  355.4f, 0.94f, 0.58f ),
			float4(  191.0f,  434.5f, 0.74f, 0.44f ),
			float4(  157.1f,  489.8f, 0.03f, 0.97f ),
		};

		void COTC_ApplyNebula(inout float3 Color, inout float Alpha, float3 WorldSpacePos, float Visibility)
		{
			if (Visibility <= 0.0f)
			{
				return;
			}

			float3 ToCameraNorm                   = normalize(CameraPosition - WorldSpacePos);
			float  CeilingParallaxDistance        = (COTC_NEBULA_CEILING_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float  FloorParallaxDistance          = (COTC_NEBULA_FLOOR_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float2 CeilingParallaxWorldSpacePosXZ = (WorldSpacePos + CeilingParallaxDistance*ToCameraNorm).xz;
			float2 FloorParallaxWorldSpacePosXZ   = (WorldSpacePos + FloorParallaxDistance*ToCameraNorm).xz;

			float3 AccumColor = float3(0.0f, 0.0f, 0.0f);
			float  AccumAlpha = 0.0f;

			// Rotation pivots on the map centre
			float2 FloorCloudPosXZ   = FloorParallaxWorldSpacePosXZ - 0.5f/WorldSpaceToDetail;
			float2 CeilingCloudPosXZ = CeilingParallaxWorldSpacePosXZ - 0.5f/WorldSpaceToDetail;

			// Unrolled so each layer's rotation is computed at compile time
			COTC_UNROLL_EXACT(COTC_NEBULA_LAYERS)
			for (int i = 0; i < COTC_NEBULA_LAYERS; i++)
			{
				float  LayerRelativeHeight            = (float(i) + 0.5f)/float(COTC_NEBULA_LAYERS);
				float2 CurrentParallaxWorldSpacePosXZ = lerp(FloorParallaxWorldSpacePosXZ, CeilingParallaxWorldSpacePosXZ, LayerRelativeHeight);

				float2 MaskUV = CurrentParallaxWorldSpacePosXZ*WorldSpaceToDetail;
				MaskUV.y = 1.0f - MaskUV.y;

				float4 MaskSample = PdxTex2DLod0(COTC_Nebula_Mask, MaskUV);

				// Empty space: the cloud tap could only multiply zero
				if (MaskSample.a <= 0.0f)
				{
					continue;
				}

				float4 Layer      = COTC_NEBULA_CLOUD_LAYERS[i];
				float  Angle      = radians(Layer.x);
				float2 Rotation   = float2(cos(Angle), sin(Angle));
				float2 CloudPosXZ = lerp(FloorCloudPosXZ, CeilingCloudPosXZ, LayerRelativeHeight);
				float2 RotatedCloudPosXZ = float2(Rotation.x*CloudPosXZ.x - Rotation.y*CloudPosXZ.y, Rotation.y*CloudPosXZ.x + Rotation.x*CloudPosXZ.y);

				float2 CloudUV         = RotatedCloudPosXZ/Layer.y + Layer.zw;
				float  CloudSample     = PdxTex2DLod0(COTC_Nebula_Cloud, CloudUV).r;
				float  CloudMultiplier = max(lerp(1.0f - COTC_NEBULA_CLOUD_CONTRAST, 1.0f + COTC_NEBULA_CLOUD_CONTRAST, CloudSample), 0.0f);

				float LayerDensity = MaskSample.a*CloudMultiplier*COTC_NEBULA_DENSITY/float(COTC_NEBULA_LAYERS);

				AccumColor += MaskSample.rgb*LayerDensity;
				AccumAlpha += LayerDensity;
			}

			float3 NebulaColor = AccumColor/max(AccumAlpha, 1e-4f);
			float  NebulaAlpha = saturate(AccumAlpha)*Visibility;

			COTC_BlendOver( Color, Alpha, NebulaColor, NebulaAlpha );
		}
	]]
}