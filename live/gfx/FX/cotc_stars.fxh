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

		static const float COTC_STARS_CEILING_Y = 5.0f;
		static const float COTC_STARS_FLOOR_Y   = -50.0f;

		static const float COTC_STARS_SOFT_CEILING_Y = 1.0f;
		static const float COTC_STARS_SOFT_FLOOR_Y   = -25.0f;

		static const float  COTC_STARS_VERTICAL_SPEED = 0.2f;
		static const float2 COTC_STARS_WIND_VELOCITY  = float2(-0.2f, -0.2f);

		static const float COTC_STARS_LAYER_TILE_SIZE = 300.0f;
		static const float COTC_STARS_LAYER_TILE_SIZE_SMALL = 150.0f;
		static const float COTC_STARS_LAYER_TILE_SIZE_Y = 200.0f;

		static const int COTC_STARS_LAYERS_COUNT = 5;

		static const float2 COTC_STARS_LAYER_UV_OFFSET_STEP = float2(0.35f, -0.15f);

		//
		// Constants
		//

		static const float COTC_STARS_VERTICAL_SPEED_MULTIPLIER = COTC_STARS_VERTICAL_SPEED/(COTC_STARS_CEILING_Y - COTC_STARS_FLOOR_Y);

		static const float COTC_STARS_LAYER_RELATIVE_TIME_SHIFT_STEP = 1.0f/float(COTC_STARS_LAYERS_COUNT);

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

		//
		// Interface
		//

		void COTC_ApplyStars(inout float3 Color, inout float Alpha, float3 WorldSpacePos)
		{
			float WinterSeverity = GetWinterSeverityValue(WorldSpacePos.xz*WorldSpaceToTerrain0To1);
			float CameraPitchCos = COTC_GetCameraPitchCosStars();

			float3 ToCameraNorm                   = normalize(CameraPosition - WorldSpacePos);
			float  CeilingParallaxDistance        = (COTC_STARS_CEILING_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float  FloorParallaxDistance          = (COTC_STARS_FLOOR_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float2 CeilingParallaxWorldSpacePosXZ = (WorldSpacePos + CeilingParallaxDistance*ToCameraNorm).xz;
			float2 FloorParallaxWorldSpacePosXZ   = (WorldSpacePos + FloorParallaxDistance*ToCameraNorm).xz;

			float StarAlpha = 0.0f;

			COTC_UNROLL_EXACT(COTC_STARS_LAYERS_COUNT)
			for (int i = 0; i < COTC_STARS_LAYERS_COUNT; i++)
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
				float2 BaseLayerUV     = mod(CurrentParallaxWorldSpacePosXZ, LayerSize)/LayerSize;
				float2 AdjustedLayerUV = BaseLayerUV + float(i)*COTC_STARS_LAYER_UV_OFFSET_STEP;

				StarAlpha += LayerAlphaMultiplier*PdxTex2D(COTC_StarLayer, AdjustedLayerUV).a;
			}

			StarAlpha *= smoothstep( 0.0f, 100.0f, CameraPosition.y );

			Color = lerp(Color, COTC_STARS_COLOR, saturate(StarAlpha));
			Alpha = lerp(Alpha, 1.0f, saturate(StarAlpha));
		}
	]]
}
