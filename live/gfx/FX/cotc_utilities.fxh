Includes = {
	"cw/camera.fxh"
	"cotc_camera_utils.fxh"
	"cotc_stars.fxh"
	"cotc_nebula.fxh"
}

PixelShader = {
	Code [[
		void COTC_ApplyBackgroundEffects(inout float3 Color, inout float Alpha, float3 WorldSpacePos, int StarLayerMult)
		{
			COTC_ApplyStars(Color, Alpha, WorldSpacePos, StarLayerMult);
			COTC_ApplyNebula(Color, Alpha, WorldSpacePos);
		}
	]]
}
