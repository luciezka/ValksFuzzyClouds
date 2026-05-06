using System.Reflection;
using FluffyClouds;
using HarmonyLib;
using OpenTK.Graphics.OpenGL;
using Vintagestory.API.Client;
using Vintagestory.API.Common;
using Vintagestory.API.MathTools;

namespace ValksFuzzyClouds;

[HarmonyPatch(typeof(CloudRendererMap), nameof(CloudRendererMap.InitCloudTiles))]
public class CloudRendererMap_InitCloudTiles_Patch
{
    [HarmonyPostfix]
    static void Postfix(CloudRendererMap __instance)
    {
        // Patch TextureMap (cloudMap in shader)
        GL.BindTexture(TextureTarget.Texture2D, __instance.TextureMap);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.Linear);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMagFilter, (int)TextureMagFilter.Linear);

        // Patch TextureCol (cloudCol in shader)
        GL.BindTexture(TextureTarget.Texture2D, __instance.TextureCol);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.Linear);
        GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMagFilter, (int)TextureMagFilter.Linear);

        // Unbind to leave GL state clean
        GL.BindTexture(TextureTarget.Texture2D, 0);
    }
}

