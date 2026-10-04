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
		File = "gfx/map/environment/cotc_star_layer.dds"
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
		static const float COTC_STARS_NEAR_DEPTH = -5.0f;	// nearest layer
		static const float COTC_STARS_FAR_DEPTH  = 250.0f;	// farthest layer

		// Brightness of the nearest and farthest layer
		static const float COTC_STARS_NEAR_ALPHA = 1.0f;
		static const float COTC_STARS_FAR_ALPHA  = 0.1f;

		// Layer distance (zoom distance + depth).
		// Larger = smaller stars.
		static const float COTC_STARS_SIZE_REFERENCE_DISTANCE = 400.0f;

		// smaller = size holds steadier, but the stars fade over more often while zooming.
		static const float COTC_STARS_SIZE_STEP = 0.5f;

		// Fade layers out where the view ray grazes them (-ViewDir.y), to stop streaks at the horizon
		static const float COTC_STARS_HORIZON_FADE_START = 0.05f;
		static const float COTC_STARS_HORIZON_FADE_END   = 1.0f;

		static const int COTC_STARS_LAYERS_COUNT = 2;

		#define COTC_STARS_MAX_LAYERS 5

		// Per-layer variation
		// rotation (deg), tile size, offset x, offset y
		static const float4 COTC_STARS_LAYERS[COTC_STARS_MAX_LAYERS] =
		{
			float4(  252.3f,   90.0f, 0.3f, 0.4f ),
			float4(  119.1f,   70.0f, 0.5f, 0.5f ),
			float4(   89.1f,   60.0f, 0.7f, 0.6f ),
			float4(  322.2f,   50.0f, 0.9f, 0.7f ),
			float4(  172.2f,   110.0f, 0.4f, 0.8f )
		};

		//
		// Service
		//

		// Rotation is a (cos, sin) pair from the layer's angle
		float COTC_SampleStarLayer(float2 LayerPosXZ, float2 Rotation, float4 Layer, float SizeScale)
		{
			float  LayerSize = Layer.y*SizeScale;
			float2 RotatedPosXZ = float2(
				Rotation.x*LayerPosXZ.x - Rotation.y*LayerPosXZ.y,
				Rotation.y*LayerPosXZ.x + Rotation.x*LayerPosXZ.y);

			float2 BaseLayerUV = mod(RotatedPosXZ, LayerSize)/LayerSize;
			return PdxTex2D(COTC_StarLayer, BaseLayerUV + Layer.zw).a;
		}

		//
		// Interface
		//

		void COTC_ApplyStars(inout float3 Color, inout float Alpha, float3 WorldSpacePos)
		{
			float3 ViewDir      = normalize(WorldSpacePos - CameraPosition);
			float  RayDown      = max(-ViewDir.y, 1e-3f);
			float2 RayXZPerDown = ViewDir.xz/RayDown;
			float  HorizonFade  = smoothstep(COTC_STARS_HORIZON_FADE_START, COTC_STARS_HORIZON_FADE_END, -ViewDir.y);

			float ZoomDistance = COTC_GetZoomDistance();

			float StarAlpha = 0.0f;

			// Fixed count so it unrolls and each layer's rotation is computed at compile time
			COTC_UNROLL_EXACT(COTC_STARS_MAX_LAYERS)
			for (int i = 0; i < COTC_STARS_MAX_LAYERS; i++)
			{
				float4 Layer    = COTC_STARS_LAYERS[i];
				float  Angle    = radians(Layer.x);
				float2 Rotation = float2(cos(Angle), sin(Angle));

				float LayerRelativeDepth   = (float(i) + 0.5f)/float(COTC_STARS_MAX_LAYERS);
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
					LayerStarAlpha += (1.0f - SizeBlend)*COTC_SampleStarLayer(LayerPosXZ, Rotation, Layer, SizeScaleLo);
				}
				if (SizeBlend > 0.001f)
				{
					LayerStarAlpha += SizeBlend*COTC_SampleStarLayer(LayerPosXZ, Rotation, Layer, SizeScaleHi);
				}

				StarAlpha += LayerAlphaMultiplier*LayerStarAlpha;
			}

			StarAlpha *= HorizonFade;

			COTC_BlendOver( Color, Alpha, COTC_STARS_COLOR, saturate( StarAlpha ) );
		}
	]]
}
