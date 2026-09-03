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
		static const int   COTC_NEBULA_LAYERS    = 24;
		static const float COTC_NEBULA_DENSITY   = 0.3f;

		static const float COTC_NEBULA_CEILING_Y = 5.0f;
		static const float COTC_NEBULA_FLOOR_Y   = -5.0f;

		static const float COTC_NEBULA_CLOUD_TILE_SIZE = 400.0f;
		static const float COTC_NEBULA_CLOUD_CONTRAST  = 2.0f;

		static const float COTC_NEBULA_CLOUD_ROTATION_AMOUNT = 1.0f;
		static const float COTC_NEBULA_CLOUD_SCALE_JITTER    = 0.25f;

		static const float COTC_NEBULA_CLOUD_ROTATION_SPEED    = 0.001f;
		static const float COTC_NEBULA_CLOUD_SPEED_VARIATION   = 0.001f;

		static const float COTC_NEBULA_TWO_PI = 6.283185307f;

		float4 COTC_NebulaLayerRandom(float LayerIndex)
		{
			// +1 dodges the hash's fixed point at zero, which would leave layer 0 unrotated.
			float4 P = frac((LayerIndex + 1.0f)*float4(0.1031f, 0.1030f, 0.0973f, 0.1099f));
			P += dot(P, P.wzxy + 33.33f);
			return frac((P.xxyz + P.yzzw)*P.zywx);
		}

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
				float  LayerRelativeHeight            = (float(i) + 0.5f)/float(COTC_NEBULA_LAYERS);
				float2 CurrentParallaxWorldSpacePosXZ = lerp(FloorParallaxWorldSpacePosXZ, CeilingParallaxWorldSpacePosXZ, LayerRelativeHeight);

				float2 MaskUV = CurrentParallaxWorldSpacePosXZ*WorldSpaceToDetail;
				MaskUV.y = 1.0f - MaskUV.y;

				float4 MaskSample = PdxTex2DLod0(COTC_Nebula_Mask, MaskUV);

				float4 LayerRandom = COTC_NebulaLayerRandom(float(i));

				float  LayerSpeed = COTC_NEBULA_CLOUD_ROTATION_SPEED*(1.0f + COTC_NEBULA_CLOUD_SPEED_VARIATION*(2.0f*LayerRandom.x - 1.0f));

				float  CloudAngle    = LayerRandom.z*COTC_NEBULA_TWO_PI*COTC_NEBULA_CLOUD_ROTATION_AMOUNT + GlobalTime*LayerSpeed;
				float  CloudAngleSin = sin(CloudAngle);
				float  CloudAngleCos = cos(CloudAngle);

				float2 MapCentre     = 0.5f/WorldSpaceToDetail;
				float2 CloudPosXZ    = CurrentParallaxWorldSpacePosXZ - MapCentre;
				float2 RotatedCloudPosXZ = float2(CloudAngleCos*CloudPosXZ.x - CloudAngleSin*CloudPosXZ.y, CloudAngleSin*CloudPosXZ.x + CloudAngleCos*CloudPosXZ.y);

				float CloudTileSize = COTC_NEBULA_CLOUD_TILE_SIZE*(1.0f + COTC_NEBULA_CLOUD_SCALE_JITTER*(2.0f*LayerRandom.w - 1.0f));

				float2 CloudUV         = RotatedCloudPosXZ/CloudTileSize + LayerRandom.xy;
				float  CloudSample     = PdxTex2DLod0(COTC_Nebula_Cloud, CloudUV).r;
				float  CloudMultiplier = lerp(1.0f - COTC_NEBULA_CLOUD_CONTRAST, 1.0f + COTC_NEBULA_CLOUD_CONTRAST, CloudSample);

				float LayerDensity = MaskSample.a*CloudMultiplier*COTC_NEBULA_DENSITY/float(COTC_NEBULA_LAYERS);

				AccumColor += MaskSample.rgb*LayerDensity;
				AccumAlpha += LayerDensity;
			}

			float3 NebulaColor = AccumColor/max(AccumAlpha, 1e-4f);
			float  NebulaAlpha = saturate(AccumAlpha);

			COTC_BlendOver( Color, Alpha, NebulaColor, NebulaAlpha );
		}
	]]
}