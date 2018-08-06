Shader "Hidden/WorldPositionShader"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		CGINCLUDE

		#include "UnityCG.cginc"

		uniform sampler3D				voxelGrid;

		uniform sampler2D 				_MainTex;
		uniform sampler2D				_ReflectionTex;
		uniform sampler2D				_CameraDepthTexture;
		uniform sampler2D				_CameraDepthNormalsTexture;
		uniform sampler2D				_CameraGBufferTexture1;

		uniform float4x4				InverseProjectionMatrix;
		uniform float4x4				InverseViewMatrix;

		uniform float4					_MainTex_TexelSize;

		uniform float3					mainCameraPosition;

		uniform float					worldVolumeBoundary;
		uniform float					rayStep;
		uniform float					rayOffset;
		uniform float					maximumIterations;
		uniform float					blurStep;

		uniform int						voxelVolumeDimension;

		struct appdata
		{
			float4 vertex : POSITION;
			float2 uv : TEXCOORD0;

		};

		struct v2f
		{
			float2 uv : TEXCOORD0;
			float4 vertex : SV_POSITION;
			float4 cameraRay : TEXCOORD1;
		};

		struct v2f_blending
		{
			float2 uv : TEXCOORD0;
			float4 vertex : SV_POSITION;
		};

		// Structure representing the input to the fragment shader of blur pass
		struct v2f_blur
		{
			float2 uv : TEXCOORD0;
			float4 vertex : SV_POSITION;
			float2 offset1 : TEXCOORD1;
			float2 offset2 : TEXCOORD2;
			float2 offset3 : TEXCOORD3;
			float2 offset4 : TEXCOORD4;
		};

		// Vertex shader for the horizontal blurring pass
		v2f_blur vert_horizontal_blur(appdata v)
		{
			half unitX = _MainTex_TexelSize.x * blurStep;

			v2f_blur o;

			o.vertex = UnityObjectToClipPos(v.vertex);
			o.uv = v.uv;

			o.offset1 = half2(-2.0 * unitX, 0.0);
			o.offset2 = half2(-unitX, 0.0);
			o.offset3 = half2(unitX, 0.0);
			o.offset4 = half2(2.0 * unitX, 0.0);

			return o;
		}

		// Vertex shader for the vertical blurring pass
		v2f_blur vert_vertical_blur(appdata v)
		{
			half unitY = _MainTex_TexelSize.y * blurStep;

			v2f_blur o;

			o.vertex = UnityObjectToClipPos(v.vertex);
			o.uv = v.uv;

			o.offset1 = half2(0.0, 2.0 * unitY);
			o.offset2 = half2(0.0, unitY);
			o.offset3 = half2(0.0, -unitY);
			o.offset4 = half2(0.0, -2.0 * unitY);

			return o;
		}

		// Fragment shader for the blur pass
		float4 frag_blur(v2f_blur i) : SV_Target
		{
			float4 col = tex2D(_MainTex, i.uv);
			col += tex2D(_MainTex, i.uv + i.offset1);
			col += tex2D(_MainTex, i.uv + i.offset2);
			col += tex2D(_MainTex, i.uv + i.offset3);
			col += tex2D(_MainTex, i.uv + i.offset4);

			col *= 0.2;

			return col;
		}

		v2f vert (appdata v)
		{
			v2f o;
			o.vertex = UnityObjectToClipPos(v.vertex);
			o.uv = v.uv;

			//transform clip pos to view space
			float4 clipPos = float4( v.uv * 2.0f - 1.0f, 1.0f, 1.0f);
			float4 cameraRay = mul(InverseProjectionMatrix, clipPos);
			o.cameraRay = cameraRay / cameraRay.w;

			return o;
		}

		v2f_blending vert_blending (appdata v)
		{
			v2f_blending o;
			o.vertex = UnityObjectToClipPos(v.vertex);
			o.uv = v.uv;
			return o;
		}

		float3 EncodePosition (float3 inputPosition)
		{

			float3 encodedPosition = inputPosition / worldVolumeBoundary;
			encodedPosition += float3(1.0f, 1.0f, 1.0f);
			encodedPosition /= 2.0f;
			return encodedPosition;

		}

		float4 frag (v2f i) : SV_Target
		{
			// read low res depth and reconstruct world position
			float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
			
			//linearise depth		
			float lindepth = Linear01Depth (depth);
			
			//get view and then world positions		
			float4 viewPos = float4(i.cameraRay.xyz * lindepth,1);
			float3 worldPos = mul(InverseViewMatrix, viewPos).xyz;

			float3 finalPosition = EncodePosition (worldPos);

			return float4(finalPosition, 1.0f);
		}

		// Returns the voxel information
		inline float4 GetVoxelInfo(float3 worldPosition)
		{
			// Default value
			float4 info = float4(0.0f, 0.0f, 0.0f, 0.0f);

			// Check if the given position is inside the voxelized volume
			if ((abs(worldPosition.x) < worldVolumeBoundary) && (abs(worldPosition.y) < worldVolumeBoundary) && (abs(worldPosition.z) < worldVolumeBoundary))
			{
				worldPosition += worldVolumeBoundary;
				worldPosition /= (2.0f * worldVolumeBoundary);

				info = tex3D(voxelGrid, worldPosition);
			}

			return info;
		}

		float4 frag_debug (v2f i) : SV_Target
		{
			// read low res depth and reconstruct world position
			float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
			
			//linearise depth		
			float lindepth = Linear01Depth (depth);
			
			//get view and then world positions		
			float4 viewPos = float4(i.cameraRay.xyz * lindepth, 1.0f);
			float3 worldPos = mul(InverseViewMatrix, viewPos).xyz;

			return GetVoxelInfo(worldPos);
		}

		// Traces a ray starting from the current voxel in the reflected ray direction and accumulates color
		inline float3 RayTrace(float3 worldPosition, float3 reflectedRayDirection, float3 pixelNormal)
		{
			// Color for storing all the samples
			float3 accumulatedColor = float3(0.0f, 0.0f, 0.0f);

			float3 currentPosition = worldPosition + (rayOffset * pixelNormal);
			float4 currentVoxelInfo = float4(0.0f, 0.0f, 0.0f, 0.0f);

			bool hitFound = false;

			// Loop for tracing the ray through the scene
			for (float i = 0.0f; i < maximumIterations; i += 1.0f)
			{
				// Traverse the ray in the reflected direction
				currentPosition += (reflectedRayDirection * rayStep);

				// Get the currently hit voxel's information
				currentVoxelInfo = GetVoxelInfo(currentPosition);

				// At the currently traced sample
				if ((currentVoxelInfo.w > 0.0f) && (!hitFound))
				{
					accumulatedColor = (currentVoxelInfo.xyz);
					hitFound = true;
				}
			}

			return accumulatedColor;
		}

		float4 frag_ray_tracing (v2f i) : SV_Target
		{
			float4 originalColor = tex2D(_MainTex, i.uv);

			// read low res depth and reconstruct world position
			float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
			
			//linearise depth		
			float lindepth = Linear01Depth (depth);
			
			//get view and then world positions		
			float4 viewPos = float4(i.cameraRay.xyz * lindepth,1);
			float3 worldPos = mul(InverseViewMatrix, viewPos).xyz;

			// Extract the information of the current pixel from the voxel grid
			float depthValue;
			float3 viewSpaceNormal;
			DecodeDepthNormal(tex2D(_CameraDepthNormalsTexture, i.uv), depthValue, viewSpaceNormal);
			viewSpaceNormal = normalize(viewSpaceNormal);
			float3 pixelNormal = mul((float3x3)InverseViewMatrix, viewSpaceNormal);

			// Compute the current pixel to camera unit vector
			float3 pixelToCameraUnitVector = normalize(mainCameraPosition - worldPos);

			// Compute the reflected ray direction
			float3 reflectedRayDirection = normalize(reflect(pixelToCameraUnitVector, pixelNormal));
			reflectedRayDirection *= -1.0;

			float3 reflectedColor = RayTrace(worldPos, reflectedRayDirection, pixelNormal);

			return float4(reflectedColor, 1.0f);
		}

		float4 frag_blending (v2f_blending i) : SV_Target
		{
			float metallic = tex2D (_CameraGBufferTexture1, i.uv).r;
			float smoothness = tex2D (_CameraGBufferTexture1, i.uv).a;
			float4 originalColor = tex2D(_MainTex, i.uv);
			float3 reflectedColor = tex2D(_ReflectionTex, i.uv).rgb;
			float3 finalColor = originalColor.rgb + (reflectedColor * smoothness * metallic);
			return float4(finalColor, originalColor.a);
		}

		ENDCG

		// 0 : World Position Writing pass
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			ENDCG
		}

		// 1 : Voxelization Debug pass
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag_debug
			ENDCG
		}

		// 2 : Ray tracing pass
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag_ray_tracing
			ENDCG
		}

		// 3 : Vertical Blurring
		Pass
		{
			CGPROGRAM
			#pragma vertex vert_vertical_blur
			#pragma fragment frag_blur
			ENDCG
		}

		// 4 : Horizontal Blurring
		Pass
		{
			CGPROGRAM
			#pragma vertex vert_horizontal_blur
			#pragma fragment frag_blur
			ENDCG
		}

		// 5 : Blending 
		Pass
		{
			CGPROGRAM
			#pragma vertex vert_blending
			#pragma fragment frag_blending
			ENDCG
		}

	}
}
