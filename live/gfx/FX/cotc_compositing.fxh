PixelShader = {
	Code [[
		// Composites a source colour OVER a destination that is itself only PARTLY opaque
		void COTC_BlendOver( inout float3 DstColor, inout float DstAlpha, in float3 SrcColor, in float SrcAlpha )
		{
			const float OutAlpha = SrcAlpha + DstAlpha * ( 1.0f - SrcAlpha );
			const float ColorWeight = OutAlpha > 1e-5f ? SrcAlpha / OutAlpha : 0.0f;

			DstColor = lerp( DstColor, SrcColor, ColorWeight );
			DstAlpha = OutAlpha;
		}

		static const float COTC_DITHER_STRENGTH = 1.0f;

		float COTC_InterleavedGradientNoise( float2 PixelPos )
		{
			return frac( 52.9829189f * frac( dot( PixelPos, float2( 0.06711056f, 0.00583715f ) ) ) );
		}

		float4 COTC_DitherOutput( float4 Out, float2 PixelPos )
		{
			const float Noise = ( COTC_InterleavedGradientNoise( PixelPos ) + COTC_InterleavedGradientNoise( PixelPos + float2( 47.0f, 17.0f ) ) - 1.0f ) * ( COTC_DITHER_STRENGTH / 255.0f );

			Out.rgb = max( Out.rgb + Noise / max( Out.a, 1.0f / 255.0f ), 0.0f );
			Out.a = saturate( Out.a + Noise );
			return Out;
		}
	]]
}
