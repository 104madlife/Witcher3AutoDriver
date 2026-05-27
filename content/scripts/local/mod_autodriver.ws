// ----------------------------------------------------------------------------
// AutoDriver prototype
// ----------------------------------------------------------------------------
statemachine class CModAutoDriver extends CMod {
    default modName = 'AutoDriver';
    default modAuthor = "104madlife";
    default modUrl = "local";
    default modVersion = '0.1';

    default logLevel = MLOG_DEBUG;

    protected var minWalkDistance: float; default minWalkDistance = 8.0;
    protected var maxWalkDistance: float; default maxWalkDistance = 18.0;
    protected var minHorseDistance: float; default minHorseDistance = 12.0;
    protected var maxHorseDistance: float; default maxHorseDistance = 28.0;

    protected var walkSpeed: float; default walkSpeed = 1.0;
    protected var horseSpeed: float; default horseSpeed = 2.0;

    public function init() {
        super.init();

        theInput.RegisterListener(this, 'OnToggleWalkWander', 'AutoDriver_WalkWander');
        theInput.RegisterListener(this, 'OnToggleHorseWander', 'AutoDriver_HorseWander');

        GotoState('AutoDriver_Idle');
        notify("AutoDriver loaded: NumPad3 walk wander, NumPad2 horse wander");
    }

    protected function notify(message: String) {
        GetWitcherPlayer().DisplayHudMessage(message);
        log.info(message);
    }

    protected function stopCurrentAction() {
        var horse: CActor;

        thePlayer.ActionCancelAll();

        if (thePlayer.IsUsingHorse(true)) {
            horse = (CActor)thePlayer.GetUsedVehicle();
            if (horse) {
                horse.ActionCancelAll();
            }
        }
    }

    protected function randomGroundPosition(origin: Vector, minDistance: float, maxDistance: float) : Vector {
        var result: Vector;
        var groundZ: float;
        var world: CWorld;

        world = theGame.GetWorld();
        result = origin + VecRingRand(minDistance, maxDistance);

        if (world.NavigationComputeZ(result, result.Z - 8.0, result.Z + 8.0, groundZ)) {
            result.Z = groundZ;
        }

        if (world.PhysicsCorrectZ(result, groundZ)) {
            result.Z = groundZ;
        }

        return result;
    }

    protected latent function moveActorRandom(
        actor: CActor,
        minDistance: float,
        maxDistance: float,
        moveType: EMoveType,
        absSpeed: float
    ) : bool {
        var whereTo: Vector;
        var mac: CMovingAgentComponent;
        var corrected: Vector;

        if (!actor) {
            return false;
        }

        whereTo = randomGroundPosition(actor.GetWorldPosition(), minDistance, maxDistance);

        mac = actor.GetMovingAgentComponent();
        if (mac && !mac.IsPositionValid(whereTo)) {
            if (mac.GetEndOfLineNavMeshPosition(whereTo, corrected)) {
                whereTo = corrected;
            }
        }

        return actor.ActionMoveTo(whereTo, moveType, absSpeed, 1.5);
    }

    event OnToggleWalkWander(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_WalkWander') {
                stopCurrentAction();
                GotoState('AutoDriver_Idle');
                notify("AutoDriver walk wander stopped");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_WalkWander');
            }
        }
    }

    event OnToggleHorseWander(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_HorseWander') {
                stopCurrentAction();
                GotoState('AutoDriver_Idle');
                notify("AutoDriver horse wander stopped");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_HorseWander');
            }
        }
    }
}

state AutoDriver_Idle in CModAutoDriver {
}

state AutoDriver_WalkWander in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.notify("AutoDriver walk wander started");
        WalkLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopCurrentAction();
        super.OnLeaveState(nextStateName);
    }

    entry function WalkLoop() {
        while (parent.GetCurrentStateName() == 'AutoDriver_WalkWander') {
            if (thePlayer.IsUsingHorse(true)) {
                parent.notify("AutoDriver walk wander requires dismounted player");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            parent.moveActorRandom((CActor)thePlayer, parent.minWalkDistance, parent.maxWalkDistance, MT_Run, parent.walkSpeed);
            Sleep(0.5);
        }
    }
}

state AutoDriver_HorseWander in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.notify("AutoDriver horse wander started");
        HorseLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopCurrentAction();
        super.OnLeaveState(nextStateName);
    }

    entry function HorseLoop() {
        var horse: CActor;

        while (parent.GetCurrentStateName() == 'AutoDriver_HorseWander') {
            if (!thePlayer.IsUsingHorse(true)) {
                parent.notify("AutoDriver horse wander requires mounted player");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            horse = (CActor)thePlayer.GetUsedVehicle();
            if (!horse) {
                parent.notify("AutoDriver could not find current horse actor");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            parent.moveActorRandom(horse, parent.minHorseDistance, parent.maxHorseDistance, MT_Run, parent.horseSpeed);
            Sleep(0.5);
        }
    }
}

function createAutoDriver() : CMod {
    return new CModAutoDriver in thePlayer;
}
// ----------------------------------------------------------------------------
