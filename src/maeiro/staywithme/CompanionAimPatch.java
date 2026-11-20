package maeiro.staywithme;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoPlayer;

@Patch(className = "viewpoint.interact.LootTargets", methodName = "aimed", strictMatch = true)
public final class CompanionAimPatch {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(1) IsoPlayer player, @Patch.Return Object target) {
        CompanionTargets.recordTarget(player, target);
    }
}
