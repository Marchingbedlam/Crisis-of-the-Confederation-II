Includes = {
	"cw/camera.fxh"
	"cw/pdxterrain.fxh"
	"dynamic_masks.fxh"
}

PixelShader = {
	TextureSampler COTC_StarLayer
	{
		Index = 39
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/map/environment/cotc_star_layer_1.dds"
		srgb = yes
	}

	Code [[
		//
		// Config
		//

		static const float3 COTC_STARS_COLOR = float3(0.4f, 0.6f, 1.0f);

		static const float COTC_STARS_MAX_CAMERA_PITCH_COS  = 1.0f;
		static const float COTC_STARS_FULL_CAMERA_PITCH_COS = 0.9f;

		static const float COTC_STARS_CEILING_Y = 6.0f;
		static const float COTC_STARS_FLOOR_Y   = -50.0f;

		static const float COTC_STARS_SOFT_CEILING_Y = 1.0f;
		static const float COTC_STARS_SOFT_FLOOR_Y   = -25.0f;

		static const float  COTC_STARS_VERTICAL_SPEED = 0.1f;
		static const float2 COTC_STARS_WIND_VELOCITY  = float2(-0.2f, -0.2f);

		static const float COTC_STARS_LAYER_TILE_SIZE = 200.0f;
		static const float COTC_STARS_LAYER_TILE_SIZE_SMALL = 70.0f;
		static const float COTC_STARS_LAYER_TILE_SIZE_Y = 300.0f;

		static const int COTC_STARS_LAYERS_COUNT = 8;

		// Per-layer randomisation. Every layer samples the one star texture, so
		// without this they are all the same arrangement and the repeat is obvious.
		// Rotation does the heavy lifting; the tile-size jitter stops layers sharing
		// a common repeat period, and the UV offset breaks up what is left.
		static const float COTC_STARS_LAYER_ROTATION_AMOUNT = 1.0f;  // 0 = off, 1 = full turn
		static const float COTC_STARS_LAYER_SCALE_JITTER    = 0.25f; // +/- fraction of tile size

		//
		// Constants
		//

		static const float COTC_STARS_VERTICAL_SPEED_MULTIPLIER = COTC_STARS_VERTICAL_SPEED/(COTC_STARS_CEILING_Y - COTC_STARS_FLOOR_Y);

		static const float COTC_STARS_LAYER_RELATIVE_TIME_SHIFT_STEP = 1.0f/float(COTC_STARS_LAYERS_COUNT);

		static const float COTC_STARS_TWO_PI = 6.283185307f;

		//
		// Macros
		//

		#ifndef PDX_OPENGL
			#define COTC_UNROLL_EXACT(ITERATIONS_COUNT) [unroll(ITERATIONS_COUNT)]
		#else
			#define COTC_UNROLL_EXACT(ITERATIONS_COUNT)
		#endif

		//
		// Service
		//

		float COTC_GetCameraPitchCosStars()
		{
			float3 CameraLookAtDirXZ = float3(CameraLookAtDir.x, 0.0f, CameraLookAtDir.z);

			return dot(CameraLookAtDir, CameraLookAtDirXZ);
		}

		// Four uncorrelated pseudo-random values in [0,1) for one layer.
		// Depends only on the layer index, never on time or screen position, so a
		// layer keeps the same arrangement every frame and the stars cannot shimmer.
		// Sine-free, so it stays bit-stable across GPUs and drivers.
		float4 COTC_StarsLayerRandom(float LayerIndex)
		{
			// +1 dodges the hash's fixed point at zero, which would otherwise leave
			// layer 0 unrotated and unoffset.
			float4 P = frac((LayerIndex + 1.0f)*float4(0.1031f, 0.1030f, 0.0973f, 0.1099f));
			P += dot(P, P.wzxy + 33.33f);
			return frac((P.xxyz + P.yzzw)*P.zywx);
		}

		//
		// Interface
		//

		void COTC_ApplyStars(inout float3 Color, inout float Alpha, float3 WorldSpacePos, int StarLayerMult)
		{
			float WinterSeverity = GetWinterSeverityValue(WorldSpacePos.xz*WorldSpaceToTerrain0To1);
			float CameraPitchCos = COTC_GetCameraPitchCosStars();

			float3 ToCameraNorm                   = normalize(CameraPosition - WorldSpacePos);
			float  CeilingParallaxDistance        = (COTC_STARS_CEILING_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float  FloorParallaxDistance          = (COTC_STARS_FLOOR_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float2 CeilingParallaxWorldSpacePosXZ = (WorldSpacePos + CeilingParallaxDistance*ToCameraNorm).xz;
			float2 FloorParallaxWorldSpacePosXZ   = (WorldSpacePos + FloorParallaxDistance*ToCameraNorm).xz;

			float StarAlpha = 0.0f;
			float StarLayers = float(COTC_STARS_LAYERS_COUNT) * StarLayerMult;

			for (int i = 0; i < StarLayers; i++)
			{
				float  LayerRelativeHeight            = 1.0f - frac(COTC_STARS_VERTICAL_SPEED_MULTIPLIER*GlobalTime + float(i)*COTC_STARS_LAYER_RELATIVE_TIME_SHIFT_STEP);
				float2 CurrentParallaxWorldSpacePosXZ = lerp(FloorParallaxWorldSpacePosXZ, CeilingParallaxWorldSpacePosXZ, LayerRelativeHeight);

				CurrentParallaxWorldSpacePosXZ += GlobalTime*COTC_STARS_WIND_VELOCITY;

				float LayerHeight                 = COTC_STARS_FLOOR_Y + LayerRelativeHeight*(COTC_STARS_CEILING_Y - COTC_STARS_FLOOR_Y);
				float LayerAlphaFloorMultiplier   = smoothstep(COTC_STARS_FLOOR_Y, COTC_STARS_SOFT_FLOOR_Y, LayerHeight);
				float LayerAlphaCeilingMultiplier = smoothstep(COTC_STARS_CEILING_Y, COTC_STARS_SOFT_CEILING_Y, LayerHeight);
				float LayerAlphaMultiplier        = LayerAlphaFloorMultiplier*LayerAlphaCeilingMultiplier;

				float LayerSize = COTC_STARS_LAYER_TILE_SIZE;
				if ( CameraPosition.y < COTC_STARS_LAYER_TILE_SIZE_Y )
				{
					LayerSize = COTC_STARS_LAYER_TILE_SIZE_SMALL;
				}

				float4 LayerRandom = COTC_StarsLayerRandom(float(i));

				// Rotate in world space, before the tile wrap, so the tiling grid is
				// rotated as a whole and stays seamless. Drift is unaffected: a star
				// sits at a fixed UV, so its world position still moves by -Wind*t
				// regardless of the rotation.
				float  LayerAngle    = LayerRandom.z*COTC_STARS_TWO_PI*COTC_STARS_LAYER_ROTATION_AMOUNT;
				float  LayerAngleSin = sin(LayerAngle);
				float  LayerAngleCos = cos(LayerAngle);
				float2 RotatedWorldSpacePosXZ = float2(
					LayerAngleCos*CurrentParallaxWorldSpacePosXZ.x - LayerAngleSin*CurrentParallaxWorldSpacePosXZ.y,
					LayerAngleSin*CurrentParallaxWorldSpacePosXZ.x + LayerAngleCos*CurrentParallaxWorldSpacePosXZ.y);

				LayerSize *= 1.0f + COTC_STARS_LAYER_SCALE_JITTER*(2.0f*LayerRandom.w - 1.0f);

				float2 BaseLayerUV     = mod(RotatedWorldSpacePosXZ, LayerSize)/LayerSize;
				float2 AdjustedLayerUV = BaseLayerUV + LayerRandom.xy;

				StarAlpha += LayerAlphaMultiplier*PdxTex2D(COTC_StarLayer, AdjustedLayerUV).a;
			}

			Color = lerp(Color, COTC_STARS_COLOR, saturate(StarAlpha));
			Alpha = lerp(Alpha, 1.0f, saturate(StarAlpha));
		}
	]]
}
