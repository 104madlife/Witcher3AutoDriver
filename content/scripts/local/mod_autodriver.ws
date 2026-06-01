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

    protected var walkArrivalDistance: float; default walkArrivalDistance = 3.0;
    protected var walkTargetTimeout: float; default walkTargetTimeout = 8.0;
    protected var walkTickInterval: float; default walkTickInterval = 0.5;
    protected var walkStuckDistance: float; default walkStuckDistance = 0.75;
    protected var walkStuckTimeout: float; default walkStuckTimeout = 3.0;
    protected var walkTargetCandidates: int; default walkTargetCandidates = 12;
    protected var walkSafeSpotPersonalSpace: float; default walkSafeSpotPersonalSpace = 0.5;
    protected var walkSafeSpotSearchRadius: float; default walkSafeSpotSearchRadius = 5.0;
    protected var directTickInterval: float; default directTickInterval = 0.05;
    protected var directArrivalDistance: float; default directArrivalDistance = 3.0;
    protected var directRetargetInterval: float; default directRetargetInterval = 5.0;
    protected var directStuckTimeout: float; default directStuckTimeout = 2.0;
    protected var directSpeed: float; default directSpeed = 1.0;

    protected var hasWalkTarget: bool;
    protected var currentWalkTarget: Vector;
    protected var walkTargetIssuedAt: float;
    protected var lastWalkPosition: Vector;
    protected var lastWalkProgressAt: float;
    protected var hasDirectTarget: bool;
    protected var currentDirectTarget: Vector;
    protected var directTargetIssuedAt: float;
    protected var lastDirectPosition: Vector;
    protected var lastDirectProgressAt: float;

    public function init() {
        super.init();

        theInput.RegisterListener(this, 'OnToggleWalkWander', 'AutoDriver_WalkWander');
        theInput.RegisterListener(this, 'OnToggleDirectWander', 'AutoDriver_DirectWander');
        theInput.RegisterListener(this, 'OnToggleHorseWander', 'AutoDriver_HorseWander');

        GotoState('AutoDriver_Idle');
        notify("AutoDriver loaded: NumPad3 walk wander, NumPad4 direct wander, NumPad2 horse wander");
    }

    protected function notify(message: String) {
        GetWitcherPlayer().DisplayHudMessage(message);
        log.info(message);
    }

    protected function stopCurrentAction() {
        var horse: CActor;
        var mac: CMovingAgentComponent;

        thePlayer.ActionCancelAll();
        resetWalkTarget();
        resetDirectTarget();

        mac = thePlayer.GetMovingAgentComponent();
        if (mac) {
            mac.SetGameplayRelativeMoveSpeed(0.0f);
        }

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

    protected function findSafeWalkTarget(out target : Vector) : bool {
        var playerActor: CActor;
        var mac: CMovingAgentComponent;
        var world: CWorld;
        var candidate: Vector;
        var safeCandidate: Vector;
        var fallback: Vector;
        var hasFallback: bool;
        var i: int;

        playerActor = (CActor)thePlayer;
        if (!playerActor) {
            return false;
        }

        mac = playerActor.GetMovingAgentComponent();
        world = theGame.GetWorld();

        for (i = 0; i < walkTargetCandidates; i += 1) {
            candidate = randomGroundPosition(thePlayer.GetWorldPosition(), minWalkDistance, maxWalkDistance);

            if (world.NavigationFindSafeSpot(candidate, walkSafeSpotPersonalSpace, walkSafeSpotSearchRadius, safeCandidate)) {
                candidate = safeCandidate;
            }

            if (mac && !mac.IsPositionValid(candidate)) {
                continue;
            }

            if (!hasFallback) {
                fallback = candidate;
                hasFallback = true;
            }

            if (mac && mac.CanGoStraightToDestination(candidate)) {
                target = candidate;
                return true;
            }

            if (world.NavigationLineTest(thePlayer.GetWorldPosition(), candidate, walkSafeSpotPersonalSpace, false, true)) {
                target = candidate;
                return true;
            }
        }

        if (hasFallback) {
            target = fallback;
            return true;
        }

        return false;
    }

    protected function resetWalkTarget() {
        hasWalkTarget = false;
        lastWalkPosition = thePlayer.GetWorldPosition();
        lastWalkProgressAt = theGame.GetEngineTimeAsSeconds();
    }

    protected function resetDirectTarget() {
        hasDirectTarget = false;
        lastDirectPosition = thePlayer.GetWorldPosition();
        lastDirectProgressAt = theGame.GetEngineTimeAsSeconds();
    }

    protected function isWalkTargetReached() : bool {
        if (!hasWalkTarget) {
            return true;
        }

        return VecDistance2D(thePlayer.GetWorldPosition(), currentWalkTarget) <= walkArrivalDistance;
    }

    protected function isWalkTargetTimedOut() : bool {
        if (!hasWalkTarget) {
            return true;
        }

        return theGame.GetEngineTimeAsSeconds() >= walkTargetIssuedAt + walkTargetTimeout;
    }

    protected function updateWalkProgress() {
        var currentPosition: Vector;

        if (!hasWalkTarget) {
            lastWalkPosition = thePlayer.GetWorldPosition();
            lastWalkProgressAt = theGame.GetEngineTimeAsSeconds();
            return;
        }

        currentPosition = thePlayer.GetWorldPosition();
        if (VecDistance2D(currentPosition, lastWalkPosition) >= walkStuckDistance) {
            lastWalkPosition = currentPosition;
            lastWalkProgressAt = theGame.GetEngineTimeAsSeconds();
        }
    }

    protected function isWalkTargetStuck() : bool {
        if (!hasWalkTarget) {
            return true;
        }

        return theGame.GetEngineTimeAsSeconds() >= lastWalkProgressAt + walkStuckTimeout;
    }

    protected function issueWalkMoveAsync() : bool {
        var playerActor: CActor;
        var result: bool;

        playerActor = (CActor)thePlayer;
        if (!playerActor) {
            return false;
        }

        playerActor.ActionCancelAll();
        if (!findSafeWalkTarget(currentWalkTarget)) {
            hasWalkTarget = false;
            log.error("failed to find safe walk target");
            return false;
        }

        result = playerActor.ActionMoveToAsync(currentWalkTarget, MT_Run, walkSpeed, walkArrivalDistance);
        if (result) {
            hasWalkTarget = true;
            walkTargetIssuedAt = theGame.GetEngineTimeAsSeconds();
            lastWalkPosition = thePlayer.GetWorldPosition();
            lastWalkProgressAt = walkTargetIssuedAt;
            log.debug("walk target issued: " + VecToString(currentWalkTarget));
        } else {
            hasWalkTarget = false;
            log.error("failed to issue walk target: " + VecToString(currentWalkTarget));
        }

        return result;
    }

    protected function issueDirectTarget() : bool {
        if (!findSafeWalkTarget(currentDirectTarget)) {
            hasDirectTarget = false;
            log.error("failed to find direct target");
            return false;
        }

        hasDirectTarget = true;
        directTargetIssuedAt = theGame.GetEngineTimeAsSeconds();
        lastDirectPosition = thePlayer.GetWorldPosition();
        lastDirectProgressAt = directTargetIssuedAt;
        log.debug("direct target issued: " + VecToString(currentDirectTarget));
        return true;
    }

    protected function directTargetNeedsRefresh() : bool {
        if (!hasDirectTarget) {
            return true;
        }

        if (VecDistance2D(thePlayer.GetWorldPosition(), currentDirectTarget) <= directArrivalDistance) {
            return true;
        }

        if (theGame.GetEngineTimeAsSeconds() >= directTargetIssuedAt + directRetargetInterval) {
            return true;
        }

        return false;
    }

    protected function updateDirectProgress() {
        var currentPosition: Vector;

        if (!hasDirectTarget) {
            lastDirectPosition = thePlayer.GetWorldPosition();
            lastDirectProgressAt = theGame.GetEngineTimeAsSeconds();
            return;
        }

        currentPosition = thePlayer.GetWorldPosition();
        if (VecDistance2D(currentPosition, lastDirectPosition) >= walkStuckDistance) {
            lastDirectPosition = currentPosition;
            lastDirectProgressAt = theGame.GetEngineTimeAsSeconds();
        }
    }

    protected function isDirectTargetStuck() : bool {
        if (!hasDirectTarget) {
            return true;
        }

        return theGame.GetEngineTimeAsSeconds() >= lastDirectProgressAt + directStuckTimeout;
    }

    protected function driveDirectMove() {
        var mac: CMovingAgentComponent;
        var direction: Vector;

        if (!hasDirectTarget) {
            return;
        }

        mac = thePlayer.GetMovingAgentComponent();
        if (!mac) {
            return;
        }

        direction = currentDirectTarget - thePlayer.GetWorldPosition();
        direction.Z = 0.0f;

        mac.SetGameplayRelativeMoveSpeed(directSpeed);
        mac.SetGameplayMoveDirection(VecHeading(direction));
        mac.SetDirectionChangeRate(10000.0f);
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
        var result: bool;

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

        result = actor.ActionMoveTo(whereTo, moveType, absSpeed, 1.5);
        return result;
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

    event OnToggleDirectWander(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_DirectWander') {
                stopCurrentAction();
                GotoState('AutoDriver_Idle');
                notify("AutoDriver direct wander stopped");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_DirectWander');
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
        parent.resetWalkTarget();
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

            parent.updateWalkProgress();

            if (parent.isWalkTargetReached() || parent.isWalkTargetTimedOut() || parent.isWalkTargetStuck()) {
                parent.issueWalkMoveAsync();
            }

            Sleep(parent.walkTickInterval);
        }
    }
}

state AutoDriver_DirectWander in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.resetDirectTarget();
        parent.notify("AutoDriver direct wander started");
        DirectLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopCurrentAction();
        super.OnLeaveState(nextStateName);
    }

    entry function DirectLoop() {
        while (parent.GetCurrentStateName() == 'AutoDriver_DirectWander') {
            if (thePlayer.IsUsingHorse(true)) {
                parent.notify("AutoDriver direct wander requires dismounted player");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            parent.updateDirectProgress();

            if (parent.directTargetNeedsRefresh() || parent.isDirectTargetStuck()) {
                parent.issueDirectTarget();
            }

            parent.driveDirectMove();
            Sleep(parent.directTickInterval);
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
