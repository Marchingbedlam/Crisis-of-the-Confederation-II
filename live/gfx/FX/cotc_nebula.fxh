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
		static const int   COTC_NEBULA_LAYERS    = 24;
		static const float COTC_NEBULA_DENSITY   = 0.3f;

		static const float COTC_NEBULA_CEILING_Y = 5.0f;
		static const float COTC_NEBULA_FLOOR_Y   = -5.0f;

		static const float COTC_NEBULA_CLOUD_TILE_SIZE = 400.0f;
		static const float COTC_NEBULA_CLOUD_CONTRAST  = 2.0f;

		// Baked transforms
		// We don't want it to look obviously tiled
		static const float4 COTC_NEBULA_LAYER_ROT_OFFSET[COTC_NEBULA_LAYERS] =
		{
			float4( -0.30418188f, -0.95261397f, 0.43077997f, 0.51013020f ),
			float4( -0.48671217f, 0.87356240f, 0.24747414f, 0.56584871f ),
			float4( 0.01612735f, 0.99986995f, 0.80226441f, 0.52079790f ),
			float4( 0.79049606f, -0.61246712f, 0.53486666f, 0.81615413f ),
			float4( 0.34516748f, -0.93854111f, 0.97253077f, 0.98062775f ),
			float4( -0.80831919f, -0.58874449f, 0.73004061f, 0.63046309f ),
			float4( 0.99536876f, -0.09613032f, 0.50971401f, 0.46943850f ),
			float4( 0.02748749f, -0.99962215f, 0.10140284f, 0.28886627f ),
			float4( 0.25866422f, -0.96596730f, 0.38249292f, 0.96759272f ),
			float4( -0.99756972f, 0.06967539f, 0.93855312f, 0.23725019f ),
			float4( 0.86400371f, -0.50348544f, 0.99079358f, 0.14553028f ),
			float4( 0.78730862f, 0.61655911f, 0.55704393f, 0.77668087f ),
			float4( 0.15281219f, 0.98825525f, 0.48745247f, 0.93830573f ),
			float4( -0.00996361f, -0.99995036f, 0.24989753f, 0.09974367f ),
			float4( 0.09653460f, 0.99532963f, 0.39979143f, 0.81786748f ),
			float4( -0.49324205f, 0.86989211f, 0.58008049f, 0.73708396f ),
			float4( 0.16456793f, -0.98636575f, 0.52124502f, 0.58933388f ),
			float4( -0.77150998f, 0.63621722f, 0.04129930f, 0.19409201f ),
			float4( 0.34536864f, -0.93846710f, 0.31543962f, 0.91088414f ),
			float4( 0.74289339f, 0.66940974f, 0.94218343f, 0.37813311f ),
			float4( -0.98186562f, 0.18957823f, 0.14941524f, 0.89310654f ),
			float4( -0.25691531f, -0.96643392f, 0.94406309f, 0.58171315f ),
			float4( -0.98166538f, -0.19061240f, 0.73797261f, 0.44107900f ),
			float4( -0.92093305f, 0.38972082f, 0.02718458f, 0.96870535f ),
		};

		static const float COTC_NEBULA_LAYER_INV_TILE[COTC_NEBULA_LAYERS] =
		{
			0.00237239f, 0.00203514f, 0.00262715f, 0.00264598f,
			0.00256845f, 0.00295445f, 0.00272892f, 0.00231546f,
			0.00321645f, 0.00209350f, 0.00242300f, 0.00249692f,
			0.00298312f, 0.00321423f, 0.00227316f, 0.00221798f,
			0.00203792f, 0.00308950f, 0.00314779f, 0.00275402f,
			0.00283721f, 0.00281406f, 0.00230133f, 0.00204149f,
		};

		void COTC_ApplyNebula(inout float3 Color, inout float Alpha, float3 WorldSpacePos, float Visibility, float2 PixelPos)
		{
			if (Visibility <= 0.0f)
			{
				return;
			}

			float SliceJitter = COTC_InterleavedGradientNoise(PixelPos + float2(113.0f, 71.0f));

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

			for (int i = 0; i < COTC_NEBULA_LAYERS; i++)
			{
				float  LayerRelativeHeight            = (float(i) + SliceJitter)/float(COTC_NEBULA_LAYERS);
				float2 CurrentParallaxWorldSpacePosXZ = lerp(FloorParallaxWorldSpacePosXZ, CeilingParallaxWorldSpacePosXZ, LayerRelativeHeight);

				float2 MaskUV = CurrentParallaxWorldSpacePosXZ*WorldSpaceToDetail;
				MaskUV.y = 1.0f - MaskUV.y;

				float4 MaskSample = PdxTex2DLod0(COTC_Nebula_Mask, MaskUV);

				// Empty space: the cloud tap could only multiply zero
				if (MaskSample.a <= 0.0f)
				{
					continue;
				}

				float4 RotOffset  = COTC_NEBULA_LAYER_ROT_OFFSET[i];
				float2 CloudPosXZ = lerp(FloorCloudPosXZ, CeilingCloudPosXZ, LayerRelativeHeight);
				float2 RotatedCloudPosXZ = float2(RotOffset.x*CloudPosXZ.x - RotOffset.y*CloudPosXZ.y, RotOffset.y*CloudPosXZ.x + RotOffset.x*CloudPosXZ.y);

				float2 CloudUV         = RotatedCloudPosXZ*COTC_NEBULA_LAYER_INV_TILE[i] + RotOffset.zw;
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