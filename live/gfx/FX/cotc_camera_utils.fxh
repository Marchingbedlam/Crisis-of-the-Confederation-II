Includes = {
	"cw/camera.fxh"
}

PixelShader = {
	Code [[
		// Same quantities as ZOOM_STEPS in common/defines/graphic/cotc_graphics.txt
		float COTC_GetZoomDistance()
		{
			return CameraPosition.y / max( -CameraLookAtDir.y, 0.1f );
		}

		float COTC_GetCameraPitchCos()
		{
			float3 CameraLookAtDirXZ = float3( CameraLookAtDir.x, 0.0f, CameraLookAtDir.z );

			return dot( CameraLookAtDir, CameraLookAtDirXZ );
		}

		// KEEP THESE IN SYNC with ZOOM_STEPS
		#define COTC_ZOOM_DISTANCE_NAMES_HIDDEN 100.0f
		#define COTC_ZOOM_DISTANCE_NAMES_SHOWN 140.0f
		float COTC_GetMapZoomFade()
		{
			return smoothstep( COTC_ZOOM_DISTANCE_NAMES_HIDDEN, COTC_ZOOM_DISTANCE_NAMES_SHOWN, COTC_GetZoomDistance() );
		}

		// Province colour strength
		// A named alias of the shared fade for readability of purpose
		float COTC_GetProvinceColorFade()
		{
			return COTC_GetMapZoomFade();
		}
	]]
}
