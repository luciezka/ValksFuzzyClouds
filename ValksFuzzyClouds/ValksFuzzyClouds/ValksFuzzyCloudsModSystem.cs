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
        private static Harmony harmony;
        private const string HarmonyId = "valksfluffyclouds.patches";

        public override bool ShouldLoad(EnumAppSide side)
            => side == EnumAppSide.Client;

       
        
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
    }
    
}