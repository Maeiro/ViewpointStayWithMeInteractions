package maeiro.staywithme;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className = "viewpoint.interact.LootRows", methodName = "nextSelectable", strictMatch = true)
public final class CompanionScrollPatch {
    @Patch.OnExit(suppress = Throwable.class)
    public static void exit(@Patch.This Object rows, @Patch.Argument(0) int from,
                            @Patch.Argument(1) int direction, @Patch.Return(readOnly = false) int next) {
        if (next == -1 && (direction == 1 || direction == -1)) {
            next = CompanionTargets.wrapSelection(rows, from, direction);
        }
    }
}
