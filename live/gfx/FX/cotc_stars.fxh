Includes = {
	"cw/camera.fxh"
	"cw/pdxterrain.fxh"
	"cotc_camera_utils.fxh"
	"cotc_compositing.fxh"
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
		# Top level only: below High texture quality the engine drops the top mip of any mipped
		# texture, and the stars are drawn at about 1:1. Source with mips: cotc_star_layer_1.dds
		File = "gfx/map/environment/cotc_star_layer_1_single.dds"
		srgb = yes
	}

	Code [[
		//
		// Config
		//

		static const float3 COTC_STARS_COLOR = float3(0.4f, 0.6f, 1.0f);

		static const float COTC_STARS_MAX_CAMERA_PITCH_COS  = 1.0f;
		static const float COTC_STARS_FULL_CAMERA_PITCH_COS = 0.9f;

		// Layers are fixed, the parallax effect comes from the depth range here
		static const float COTC_STARS_NEAR_DEPTH = 100.0f;	// nearest layer
		static const float COTC_STARS_FAR_DEPTH  = 5000.0f;	// farthest layer

		// Brightness of the nearest and farthest layer
		static const float COTC_STARS_NEAR_ALPHA = 1.0f;
		static const float COTC_STARS_FAR_ALPHA  = 0.2f;

		// Layer distance (zoom distance + depth).
		// Larger = smaller stars.
		static const float COTC_STARS_SIZE_REFERENCE_DISTANCE = 150.0f;

		// smaller = size holds steadier, but the stars fade over more often while zooming.
		static const float COTC_STARS_SIZE_STEP = 0.5f;

		// Fade layers out where the view ray grazes them (-ViewDir.y), to stop streaks at the horizon
		static const float COTC_STARS_HORIZON_FADE_START = 0.02f;
		static const float COTC_STARS_HORIZON_FADE_END   = 0.1f;

		static const int COTC_STARS_LAYERS_COUNT = 4;

		// Upper bound of COTC_STARS_LAYERS_COUNT * StarLayerMult
		#define COTC_STARS_MAX_LAYERS 16

		// Baked transforms
		// We don't want it to look obviously tiled
		static const float4 COTC_STARS_LAYER_ROT_OFFSET[COTC_STARS_MAX_LAYERS] =
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
		};

		static const float COTC_STARS_LAYER_SIZE[COTC_STARS_MAX_LAYERS] =
		{
			79.03414753f, 92.13122616f, 71.37008343f, 70.86209145f,
			73.00114698f, 63.46367136f, 68.70861057f, 80.97743517f,
			58.29414036f, 89.56282241f, 77.38341777f, 75.09252299f,
			62.85366315f, 58.33430223f, 82.48442884f, 84.53655619f,
		};

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

		float COTC_SampleStarLayer(float2 LayerPosXZ, int LayerIndex, float SizeScale)
		{
			float4 RotOffset = COTC_STARS_LAYER_ROT_OFFSET[LayerIndex];
			float  LayerSize = COTC_STARS_LAYER_SIZE[LayerIndex]*SizeScale;
			float2 RotatedPosXZ = float2(
				RotOffset.x*LayerPosXZ.x - RotOffset.y*LayerPosXZ.y,
				RotOffset.y*LayerPosXZ.x + RotOffset.x*LayerPosXZ.y);

			float2 BaseLayerUV = mod(RotatedPosXZ, LayerSize)/LayerSize;
			return PdxTex2D(COTC_StarLayer, BaseLayerUV + RotOffset.zw).a;
		}

		//
		// Interface
		//

		void COTC_ApplyStars(inout float3 Color, inout float Alpha, float3 WorldSpacePos, int StarLayerMult)
		{
			float3 ViewDir      = normalize(WorldSpacePos - CameraPosition);
			float  RayDown      = max(-ViewDir.y, 1e-3f);
			float2 RayXZPerDown = ViewDir.xz/RayDown;
			float  HorizonFade  = smoothstep(COTC_STARS_HORIZON_FADE_START, COTC_STARS_HORIZON_FADE_END, -ViewDir.y);

			float ZoomDistance = COTC_GetZoomDistance();

			float StarAlpha = 0.0f;
			int   StarLayers = min(COTC_STARS_LAYERS_COUNT * StarLayerMult, COTC_STARS_MAX_LAYERS);

			for (int i = 0; i < StarLayers; i++)
			{
				float LayerRelativeDepth   = (float(i) + 0.5f)/float(StarLayers);
				float LayerDepth           = lerp(COTC_STARS_NEAR_DEPTH, COTC_STARS_FAR_DEPTH, LayerRelativeDepth);
				float LayerAlphaMultiplier = lerp(COTC_STARS_NEAR_ALPHA, COTC_STARS_FAR_ALPHA, LayerRelativeDepth);

				float2 LayerPosXZ = CameraPosition.xz + RayXZPerDown*(CameraPosition.y + LayerDepth);

				float SizeSteps   = log2((ZoomDistance + LayerDepth)/COTC_STARS_SIZE_REFERENCE_DISTANCE)/COTC_STARS_SIZE_STEP;
				float SizeStep    = floor(SizeSteps);
				float SizeBlend   = SizeSteps - SizeStep;
				float SizeScaleLo = exp2(SizeStep*COTC_STARS_SIZE_STEP);
				float SizeScaleHi = SizeScaleLo*exp2(COTC_STARS_SIZE_STEP);

				float LayerStarAlpha = 0.0f;
				if (SizeBlend < 0.999f)
				{
					LayerStarAlpha += (1.0f - SizeBlend)*COTC_SampleStarLayer(LayerPosXZ, i, SizeScaleLo);
				}
				if (SizeBlend > 0.001f)
				{
					LayerStarAlpha += SizeBlend*COTC_SampleStarLayer(LayerPosXZ, i, SizeScaleHi);
				}

				StarAlpha += LayerAlphaMultiplier*LayerStarAlpha;
			}

			StarAlpha *= HorizonFade;

			COTC_BlendOver( Color, Alpha, COTC_STARS_COLOR, saturate( StarAlpha ) );
		}
	]]
}
