using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class Voxelize : MonoBehaviour {

	public bool voxelizationDebugMode = false;
	public Vector2Int resolution = Vector2Int.zero;

	[Header("Shaders")]
	public Shader worldPositionShader = null;
	public ComputeShader voxelGridEntryShader = null;

	[Header("Volume Settings")]
	public float worldVolumeBoundary = 10.0f;
	public int voxelVolumeDimension = 128;

	[Header("Ray Trace Settings")]
	public int downsample = 2;
	public float rayOffset = 0.1f;
	public float rayStep = 0.1f;
	public int maximumIterations = 100;

	[Header("Blur Settings")]
	public int blurIterations = 2;
	public float blurStep = 1.0f;

	private Voxel[] voxelData = null;
	private ComputeBuffer voxelVolumeBuffer = null;
	private Material worldPositionMaterial = null;
	private RenderTexture lightingTexture = null;
	private RenderTexture positionTexture = null;

	public struct Voxel
	{
		public Vector4 data;
	};

	// Use this for initialization
	void Start () {

		Screen.SetResolution (resolution.x, resolution.y, true);

		GetComponent<Camera> ().depthTextureMode = DepthTextureMode.Depth | DepthTextureMode.DepthNormals;

		if (worldPositionShader != null) {

			worldPositionMaterial = new Material (worldPositionShader);

		}

		InitializeVoxelGrid();

		lightingTexture = new RenderTexture (voxelVolumeDimension, voxelVolumeDimension, 0, RenderTextureFormat.DefaultHDR);
		positionTexture = new RenderTexture (voxelVolumeDimension, voxelVolumeDimension, 0, RenderTextureFormat.DefaultHDR);

	}

	// Function to initialize the voxel grid data
	private void InitializeVoxelGrid() {

		// Specular voxel grid
		voxelData = new Voxel[voxelVolumeDimension * voxelVolumeDimension * voxelVolumeDimension];

		for (int i = 0; i < voxelVolumeDimension * voxelVolumeDimension * voxelVolumeDimension; ++i)
		{
			voxelData [i].data = Vector4.zero;
		}

		voxelVolumeBuffer = new ComputeBuffer(voxelData.Length, 16);
		voxelVolumeBuffer.SetData(voxelData);

	}

	// Function to update data in the voxel grid
	private void UpdateVoxelGrid () {

		// Kernel index for the entry point in compute shader
		int kernelHandle = voxelGridEntryShader.FindKernel("CSMain");

		voxelGridEntryShader.SetBuffer(kernelHandle, "voxelVolumeBuffer", voxelVolumeBuffer);
		voxelGridEntryShader.SetInt("_VoxelVolumeDimension", voxelVolumeDimension);

		voxelGridEntryShader.SetTexture(kernelHandle, "_LightingTexture", lightingTexture);
		voxelGridEntryShader.SetTexture(kernelHandle, "_PositionTexture", positionTexture);

		voxelGridEntryShader.Dispatch(kernelHandle, voxelVolumeDimension, voxelVolumeDimension, 1);

	}

	// This is called once per frame after the scene is rendered
	void OnRenderImage (RenderTexture source, RenderTexture destination) {

		worldPositionMaterial.SetBuffer("voxelVolumeBuffer", voxelVolumeBuffer);
		worldPositionMaterial.SetFloat ("worldVolumeBoundary", worldVolumeBoundary);
		worldPositionMaterial.SetFloat ("rayStep", rayStep);
		worldPositionMaterial.SetFloat ("rayOffset", rayOffset);
		worldPositionMaterial.SetFloat ("maximumIterations", (float)maximumIterations);
		worldPositionMaterial.SetMatrix ("InverseViewMatrix", GetComponent<Camera>().cameraToWorldMatrix);
		worldPositionMaterial.SetMatrix ("InverseProjectionMatrix", GetComponent<Camera>().projectionMatrix.inverse);
		worldPositionMaterial.SetInt ("voxelVolumeDimension", voxelVolumeDimension);
		worldPositionMaterial.SetVector ("mainCameraPosition", GetComponent<Camera>().transform.position);
		worldPositionMaterial.SetFloat ("blurStep", blurStep);

		RenderTexture HVBlurred = RenderTexture.GetTemporary (source.width / downsample, source.height / downsample, 0, RenderTextureFormat.DefaultHDR);
		RenderTexture HBlurred = RenderTexture.GetTemporary (source.width / downsample, source.height / downsample, 0, RenderTextureFormat.DefaultHDR);

		Graphics.Blit (source, lightingTexture);
		Graphics.Blit (source, positionTexture, worldPositionMaterial, 0);

		UpdateVoxelGrid ();

		if (voxelizationDebugMode) {
		
			Graphics.Blit (source, destination, worldPositionMaterial, 1);
		
		}
		else {
		
			Graphics.Blit (source, HVBlurred, worldPositionMaterial, 2);

			for (int i = 0; i < blurIterations; ++i) {

				Graphics.Blit (HVBlurred, HBlurred, worldPositionMaterial, 3);
				Graphics.Blit (HBlurred, HVBlurred, worldPositionMaterial, 4);

			}

			worldPositionMaterial.SetTexture ("_ReflectionTex", HVBlurred);
			Graphics.Blit (source, destination, worldPositionMaterial, 5);
		
		}

		RenderTexture.ReleaseTemporary (HVBlurred);
		RenderTexture.ReleaseTemporary (HBlurred);

	}
}