// ValksFuzzyCloudsModSystem.cs


using System;
using FluffyClouds;
using HarmonyLib;
using Vintagestory.API.Client;
using Vintagestory.API.Common;
using Vintagestory.API.Server;

namespace ValksFuzzyClouds
{
    public class ValksFuzzyCloudsModSystem : ModSystem
    {
        public override double ExecuteOrder() => 0.01;
        
        private static Harmony harmony;
        private const string HarmonyId = "valksfluffyclouds.patches";

        public override bool ShouldLoad(EnumAppSide side)
            => side == EnumAppSide.Client;

        public override void AssetsLoaded(ICoreAPI api)
        {
            CheckAndDisableConflict(api, "vintageshaderpolish");
        }
        
        
        public override void StartClientSide(ICoreClientAPI api)
        {
            harmony = new Harmony(HarmonyId);
            harmony.PatchAll();
            api.Logger.Notification("[ValksFuzzyClouds] Harmony patches applied.");
        }


        public override void Dispose()
        { 
            harmony?.UnpatchAll(Mod.Info.ModID);
            base.Dispose();
        }
        
        private void CheckAndDisableConflict(ICoreAPI api, string conflictModId)
        {
            if (api.ModLoader.IsModEnabled(conflictModId)){
              
            
            IAsset toReplace = api.Assets.TryGet(
                new AssetLocation("game", "shaders/cloudvolumetric.fsh")
            );
            
            IAsset toBeAddedShader = api.Assets.TryGet(
                new AssetLocation("valksfuzzyclouds", "shaders/cloudvolumetric.fsh")
            );
            
            AssetLocation toBeRemovedShaderPath = new AssetLocation("game", "shaders/cloudvolumetric.fsh");

            if (toBeAddedShader != null)
            {
                api.Assets.Add(toBeRemovedShaderPath, toBeAddedShader);
                toReplace.Data = toBeAddedShader.Data;
                api.Logger.Notification(
                    "[ValksFuzzyClouds] Detected vintageShaderPolish" +
                    "overriding cloudvolumetric.fsh with ValksFuzzyClouds version."
                );
            }
            
            }
        }
        
    }
    
}