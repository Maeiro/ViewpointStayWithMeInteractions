package maeiro.staywithme;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className = "viewpoint.interact.LootActions", methodName = "call", strictMatch = true)
public final class CompanionHarvestPatch {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(value = 0, readOnly = false) String function,
                             @Patch.Argument(1) Object[] arguments) {
        if ("ViewpointInteract.harvest".equals(function)) {
            function = CompanionTargets.harvestFunction(function, arguments);
        }
    }
}
