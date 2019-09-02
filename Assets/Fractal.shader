// Based on this shader (https://www.shadertoy.com/view/XsXXWS)
// open source under the http://opensource.org/licenses/BSD-2-Clause license
// by Morgan McGuire, http://graphics-codex.com

Shader "Unlit/Fractal"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

			// Set to 1 to lower quality and increase speed
			#define FAST 0

			#define Color4 float4
			#define Color3 float3
			#define Point3 float3
			#define Vector3 float3

			////////////////////////////////////////////////////////////
			// Scene configuration:

			// = normalize(+1, +1, -1)
			static const Vector3 lightDirection = Point3(0.57735026919, 0.57735026919, -0.57735026919);

			static const Color3 keyLightColor = Color3(1.0, 0.9, 1.0);
			static const Color3 fillLightColor = Color3(0.0, 0.2, 0.7);

			static const Color3 backgroundGradientCenterColor = Color3(0.3, 0.9, 0.9);
			static const Color3 backgroundGradientRimColor = Color3(0.1, 0.1, 0.);

			static const float cameraDistance = 6.5;

			////////////////////////////////////////////////////////////

			////////////////////////////////////////////////////////////
			// Algorithm options:

			// A point this close to the surface is considered to be on the surface.
			// Larger numbers lead to faster convergence but "blur" out the shape
			//static const float minimumDistanceToSurface = 0.0003;
			static const float minimumDistanceToSurface = 0.0003;

			// Higher is more complex and fills holes
			static const int ITERATIONS =
#	if FAST
				10;
#	else
				12;// 16;
			#	endif

			// Larger is slower but more accurate and fills holes
			static const int RAY_MARCH_ITERATIONS =
#	if FAST
				100;
#	else
				100;// 150;
			#	endif

			// Different values give different shapes; 8.0 is the "standard" bulb
			static const float power = 6.0 + 2*sin(_Time.y*0.5);

			// A small step, used for computing the surface normal
			// by numerical differentiation. A scaled up version of
			// this is also used for computing a low-frequency gradient.
			static const Vector3 eps = Vector3(minimumDistanceToSurface * 5.0, 0.0, 0.0);

			// Orientation of the object
			float3x3 rotation;

			////////////////////////////////////////////////////////////

			// AO = scale surface brightness by this value. 0 = deep valley, 1 = high ridge
			float distanceToSurface(Point3 P, out float AO) {
				// Rotate the query point into the reference frame of the function
				//P = rotation * P;
				P = mul(P, rotation);
				AO = 1.0;

				// Sample distance function for a sphere:
				// return length(P) - 1.0;

				// Unit rounded box (http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)
				//return length(max(abs(P) - 1.0, 0.0)) - 0.1;	

				// This is a 3D analog of the 2D Mandelbrot set. Altering the mandlebulbExponent
				// affects the shape.
				// See the equation at
				// http://blog.hvidtfeldts.net/index.php/2011/09/distance-estimated-3d-fractals-v-the-mandelbulb-different-de-approximations/	
				Point3 Q = P;

				// Put the whole shape in a bounding sphere to 
				// speed up distant ray marching. This is necessary
				// to ensure that we don't expend all ray march iterations
				// before even approaching the surface
				{
					static const float externalBoundingRadius = 1.2;
					float r = length(P) - externalBoundingRadius;
					// If we're more than 1 unit away from the
					// surface, return that distance
					if (r > 1.0) { return r; }
				}

				// Embed a sphere within the fractal to fill in holes under low iteration counts
				static const float internalBoundingRadius = 0.72;

				// Used to smooth discrete iterations into continuous distance field
				// (similar to the trick used for coloring the Mandelbrot set)	
				float derivative = 1.0;

				for (int i = 0; i < ITERATIONS; ++i) {
					// Darken as we go deeper
					AO *= 0.725;
					float r = length(Q);

					if (r > 2.0) {
						// The point escaped. Remap AO for more brightness and return
						AO = min((AO + 0.075) * 4.1, 1.0);
						return min(length(P) - internalBoundingRadius, 0.5 * log(r) * r / derivative);
					}
					else {
						// Convert to polar coordinates and then rotate by the power
						float theta = acos(Q.z / r) * power;
						float phi = atan2(Q.y, Q.x) * power;

						// Update the derivative
						derivative = pow(r, power - 1.0) * power * derivative + 1.0;

						// Convert back to Cartesian coordinates and 
						// offset by the original point (which we're orbiting)
						float sinTheta = sin(theta);

						Q = Vector3(sinTheta * cos(phi),
							sinTheta * sin(phi),
							cos(theta)) * pow(r, power) + P;
					}
				}

				// Never escaped, so either already in the set...or a complete miss
				return minimumDistanceToSurface;
			}

			float distanceToSurface(Point3 P) {
				float ignore;
				return distanceToSurface(P, ignore);
			}

			Color3 trace(float2 coord) {
				//float zoom = pow(200.0, -cos(_Time.y * 0.2) + 1.0);
				float zoom = 1;// pow(200.0, -cos(_Time.y * 0.2) + 1.0);

				Point3 rayOrigin = Point3(2.0 * coord / _ScreenParams.xy - 1.0, -cameraDistance);

				// Correct for aspect ratio
				//rayOrigin.x *= iResolution.x / iResolution.y;
				rayOrigin.x *= _ScreenParams.x / _ScreenParams.y;

				Vector3 rayDirection = normalize(normalize(Point3(0.0, 0.0, 1.0) - rayOrigin) + 0.2 * Point3(rayOrigin.xy, 0.0) / zoom);

				// Distance from ray origin to hit point
				float t = 0.0;

				// Point on (technically, near) the surface of the Mandelbulb
				Point3 X;

				bool hit = false;
				float d;

				// March along the ray, detecting when we are very close to the surface
				for (int i = 0; i < RAY_MARCH_ITERATIONS; ++i) {
					X = rayOrigin + rayDirection * t;

					d = distanceToSurface(X);
					hit = (d < minimumDistanceToSurface);
					if (hit) { break; }

					// Advance along the ray by the worst-case distance to the
					// surface in any direction
					t += d;
				}

				Color3 color;
				if (hit) {
					// Compute AO term
					float AO;
					distanceToSurface(X, AO);

					// Back away from the surface a bit before computing the gradient
					X -= rayDirection * eps.x;

					// Accurate micro-normal
					Vector3 n = normalize(
						Vector3(d - distanceToSurface(X - eps.xyz),
							d - distanceToSurface(X - eps.yxz),
							d - distanceToSurface(X - eps.zyx)));

					// Broad scale normal to large shape
					Vector3 n2 = normalize(
						Vector3(d - distanceToSurface(X - eps.xyz * 50.0),
							d - distanceToSurface(X - eps.yxz * 50.0),
							d - distanceToSurface(X - eps.zyx * 50.0)));

					// Bend the local surface normal by the
					// gross local shape normal and the bounding sphere
					// normal to avoid the hyper-detailed look
					n = normalize(n + n2 + normalize(X));

					// Fade between the key and fill light based on the normal (Gooch-style wrap shading).
					// Also darken the surface in cracks (on top of the AO term)
					return AO * lerp(fillLightColor, keyLightColor, AO * clamp(0.7 * dot(lightDirection, n) + 0.6, 0.0, 1.0)) +
						// Give the feel of blowing out the highlights with a yellow tint
						AO * pow(max(dot(lightDirection, n2), 0.0), 5.0) * Color3(1.3, 1.2, 0.0);
				}
				else {
					// No hit: return the background gradient		
					//return mix(backgroundGradientCenterColor, backgroundGradientRimColor, sqrt(length((coord / iResolution.xy - vec2(0.66, 0.66)) * 2.5)));
					return lerp(backgroundGradientCenterColor, backgroundGradientRimColor, sqrt(length((coord / _ScreenParams.xy - float2(0.5, 0.66)) * 1.)));
				}
			}


            fixed4 frag (v2f i) : SV_Target
            {
                /*// sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;*/

				// Euler-angle animated rotation	
				float pitch = sin(_Time.y * 0.2);
				float yaw = cos(_Time.y * 0.3);
				//rotation = float3x3(1.0, 0.0, 0.0, 0.0, cos(pitch), -sin(pitch), 0.0, sin(pitch), cos(pitch)) *
				//	float3x3(cos(yaw), 0.0, sin(yaw), 0.0, 1.0, 0.0, -sin(yaw), 0.0, cos(yaw));
				rotation = mul(float3x3(cos(yaw), 0.0, sin(yaw), 0.0, 1.0, 0.0, -sin(yaw), 0.0, cos(yaw)), float3x3(1.0, 0.0, 0.0, 0.0, cos(pitch), -sin(pitch), 0.0, sin(pitch), cos(pitch)));
				//rotation = float3x3(cos(yaw), 0.0, sin(yaw), 0.0, 1.0, 0.0, -sin(yaw), 0.0, cos(yaw));
				float2 fragCoord = i.uv * _ScreenParams.xy;

				Color3 color =
#		if FAST
					// Single sample for speed
					trace(fragCoord.xy);
#		else
					// 4x rotated-grid SSAA for antialiasing
					(trace(fragCoord.xy + float2(-0.125, -0.375)) +
						trace(fragCoord.xy + float2(+0.375, -0.125)) +
						trace(fragCoord.xy + float2(+0.125, +0.375)) +
						trace(fragCoord.xy + float2(-0.375, +0.125))) / 4.0;
#		endif

				// Coarse RGB->sRGB encoding via sqrt
				color = sqrt(color);

				// Vignetting (from iq https://www.shadertoy.com/view/MdX3Rr)
				float2 xy = 2.0 * fragCoord.xy / _ScreenParams.xy - 1.0;
				color *= 0.5 + 0.5*pow((xy.x + 1.0)*(xy.y + 1.0)*(xy.x - 1.0)*(xy.y - 1.0), 0.5);

				//fragColor = vec4(color, 1.0);
				return float4(color, 1.0);
            }
            ENDCG
        }
    }
}
