Includes = {
	"cw/camera.fxh"
}

PixelShader = {
	Code [[
		// Height the camera loses per unit travelled along its look direction
		float COTC_GetCameraLookDown()
		{
			return max( -CameraLookAtDir.y, 0.1f );
		}

		// Same quantities as ZOOM_STEPS in common/defines/graphic/cotc_graphics.txt
		float COTC_GetZoomDistance()
		{
			return CameraPosition.y / COTC_GetCameraLookDown();
		}

		float COTC_GetCameraPitchCos()
		{
			float3 CameraLookAtDirXZ = float3( CameraLookAtDir.x, 0.0f, CameraLookAtDir.z );

			return dot( CameraLookAtDir, CameraLookAtDirXZ );
		}

		// KEEP THESE IN SYNC with ZOOM_STEPS
		#define COTC_ZOOM_DISTANCE_PLANETS 180.0f
		#define COTC_ZOOM_DISTANCE_SYSTEMS 229.0f
		#define COTC_ZOOM_DISTANCE_SECTORS 1092.0f
		#define COTC_ZOOM_DISTANCE_REGIONS 1218.0f
		float COTC_GetMapZoomFade()
		{
			return smoothstep( COTC_ZOOM_DISTANCE_PLANETS, COTC_ZOOM_DISTANCE_SYSTEMS, COTC_GetZoomDistance() );
		}

		// Province colour strength
		// A named alias of the shared fade for readability of purpose
		float COTC_GetProvinceColorFade()
		{
			return COTC_GetMapZoomFade();
		}

		// --- Sector opacity ------------------------------------------------------
		static const float COTC_SECTOR_NEAR_OPACITY = 0.05f;

		float COTC_GetSectorOpacity()
		{
			const float Fade = smoothstep(
				COTC_ZOOM_DISTANCE_PLANETS,
				COTC_ZOOM_DISTANCE_REGIONS,
				COTC_GetZoomDistance() );

			return lerp( COTC_SECTOR_NEAR_OPACITY, 0.75f, Fade );
		}
	]]
}
