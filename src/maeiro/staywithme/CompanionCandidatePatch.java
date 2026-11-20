package maeiro.staywithme;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoPlayer;
import zombie.iso.IsoGridSquare;

@Patch(className = "viewpoint.interact.LootTargets", methodName = "people", strictMatch = true)
public final class CompanionCandidatePatch {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.Argument(0) IsoPlayer player, @Patch.Argument(1) IsoGridSquare here) {
        CompanionTargets.addCandidate(player, here);
    }
}
