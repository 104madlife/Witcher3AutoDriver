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
    protected var cloneSpawnDistance: float; default cloneSpawnDistance = 3.0;
    protected var cloneMoveSpeed: float; default cloneMoveSpeed = 1.0;
    protected var npcSearchRange: float; default npcSearchRange = 60.0;
    protected var npcMinVelocity: float; default npcMinVelocity = 0.2;
    protected var npcCamTickInterval: float; default npcCamTickInterval = 0.05;
    protected var npcCamRetargetInterval: float; default npcCamRetargetInterval = 5.0;
    protected var npcCamDistance: float; default npcCamDistance = 4.0;
    protected var npcCamHeight: float; default npcCamHeight = 1.8;
    protected var npcLookAtHeight: float; default npcLookAtHeight = 1.4;
    protected var npcStaticCamFov: float; default npcStaticCamFov = 70.0f;
    protected var npcCamPositionSmooth: float; default npcCamPositionSmooth = 5.0f;
    protected var npcCamRotationSmooth: float; default npcCamRotationSmooth = 7.0f;

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
    protected var followedNpc: CActor;
    protected var followedNpcSelectedAt: float;
    protected var followedNpcIsClone: bool;
    protected var autoClone: CActor;
    protected var npcStaticCam: CStaticCamera;
    protected var npcCameraFollowUsesStaticFallback: bool;
    protected var npcCamSmoothingInitialized: bool;
    protected var smoothedNpcCamPos: Vector;
    protected var smoothedNpcCamRot: EulerAngles;

    public function init() {
        super.init();

        theInput.RegisterListener(this, 'OnToggleWalkWander', 'AutoDriver_WalkWander');
        theInput.RegisterListener(this, 'OnToggleDirectWander', 'AutoDriver_DirectWander');
        theInput.RegisterListener(this, 'OnToggleCameraFollowNpc', 'AutoDriver_CameraFollowNpc');
        theInput.RegisterListener(this, 'OnToggleStaticCameraFollowNpc', 'AutoDriver_StaticCameraFollowNpc');
        theInput.RegisterListener(this, 'OnToggleHorseWander', 'AutoDriver_HorseWander');

        GotoState('AutoDriver_Idle');
        notify("AutoDriver loaded: NumPad3 official walk, NumPad4 clone wander, NumPad5/6 NPC cam, NumPad2 horse");
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
        followedNpc = NULL;
        followedNpcIsClone = false;
        npcCameraFollowUsesStaticFallback = false;
        npcCamSmoothingInitialized = false;

        if (npcStaticCam && npcStaticCam.IsRunning()) {
            npcStaticCam.Stop();
        }

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

        destroyAutoClone();
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

    protected function findMovingNpc(out npc : CActor) : bool {
        var actors: array<CActor>;
        var actor: CActor;
        var mac: CMovingAgentComponent;
        var i: int;

        actors = GetActorsInRange(thePlayer, npcSearchRange, 80, '', true);
        for (i = 0; i < actors.Size(); i += 1) {
            actor = actors[i];
            if (!actor || actor == thePlayer) {
                continue;
            }

            mac = actor.GetMovingAgentComponent();
            if (!mac) {
                continue;
            }

            if (actor.IsMoving() || VecLength(mac.GetVelocity()) >= npcMinVelocity) {
                npc = actor;
                if (followedNpc != actor) {
                    npcCamSmoothingInitialized = false;
                }
                followedNpc = actor;
                followedNpcSelectedAt = theGame.GetEngineTimeAsSeconds();
                return true;
            }
        }

        return false;
    }

    protected function npcFollowNeedsRetarget() : bool {
        var mac: CMovingAgentComponent;

        if (!followedNpc) {
            return true;
        }

        if (VecDistance2D(thePlayer.GetWorldPosition(), followedNpc.GetWorldPosition()) > npcSearchRange + 20.0f) {
            return true;
        }

        mac = followedNpc.GetMovingAgentComponent();
        if (!mac) {
            return true;
        }

        if (!followedNpc.IsMoving() && VecLength(mac.GetVelocity()) < npcMinVelocity) {
            if (theGame.GetEngineTimeAsSeconds() >= followedNpcSelectedAt + npcCamRetargetInterval) {
                return true;
            }
        }

        return false;
    }

    protected function startGameCameraFollowNpc() : bool {
        var npc: CActor;
        var cam: CCamera;

        if (!findMovingNpc(npc)) {
            notify("AutoDriver could not find moving NPC nearby");
            return false;
        }

        cam = (CCamera)theCamera.GetTopmostCameraObject();
        if (!cam) {
            if (!ensureStaticNpcCamera()) {
                notify("AutoDriver could not get top camera");
                return false;
            }

            npcCameraFollowUsesStaticFallback = true;
            npcStaticCam.Run();
            updateStaticCameraPlacement();
            notify("AutoDriver top camera unavailable, using static NPC camera");
            return true;
        }

        npcCameraFollowUsesStaticFallback = false;
        cam.FollowWithRotation(npc);
        cam.LookAt(npc, 0.2f, 0.0f);
        cam.SetActive(0.2f);
        notify("AutoDriver camera following NPC");
        return true;
    }

    protected function updateGameCameraFollowNpc() {
        var npc: CActor;
        var cam: CCamera;

        if (npcCameraFollowUsesStaticFallback) {
            updateStaticCameraPlacement();
            return;
        }

        if (npcFollowNeedsRetarget()) {
            if (!findMovingNpc(npc)) {
                return;
            }

            cam = (CCamera)theCamera.GetTopmostCameraObject();
            if (cam) {
                cam.FollowWithRotation(npc);
                cam.LookAt(npc, 0.2f, 0.0f);
            }
        }
    }

    protected function ensureStaticNpcCamera() : bool {
        var ent: CEntity;
        var template: CEntityTemplate;

        if (npcStaticCam) {
            return true;
        }

        template = (CEntityTemplate)LoadResource("dlc\modtemplates\storyboardui\interactive_camera.w2ent", true);
        if (!template) {
            notify("AutoDriver could not load StoryBoardUI camera template");
            return false;
        }

        ent = theGame.CreateEntity(template, thePlayer.GetWorldPosition(), thePlayer.GetWorldRotation());
        npcStaticCam = (CStaticCamera)ent;
        if (!npcStaticCam) {
            notify("AutoDriver could not create static NPC camera");
            return false;
        }

        npcStaticCam.SetFov(npcStaticCamFov);
        return true;
    }

    protected function startStaticCameraFollowNpc() : bool {
        var npc: CActor;

        if (!findMovingNpc(npc)) {
            notify("AutoDriver could not find moving NPC nearby");
            return false;
        }

        if (!ensureStaticNpcCamera()) {
            return false;
        }

        npcStaticCam.Run();
        updateStaticCameraPlacement();
        notify("AutoDriver static camera following NPC");
        return true;
    }

    protected function updateStaticCameraPlacement() {
        var npc: CActor;
        var camPos: Vector;
        var desiredPos: Vector;
        var lookAt: Vector;
        var forward: Vector;
        var velocity: Vector;
        var rot: EulerAngles;
        var posAlpha: float;
        var rotAlpha: float;

        if (!followedNpcIsClone && npcFollowNeedsRetarget()) {
            findMovingNpc(npc);
        }

        if (!followedNpc || !npcStaticCam) {
            return;
        }

        velocity = followedNpc.GetMovingAgentComponent().GetVelocity();
        velocity.Z = 0.0f;
        if (VecLength(velocity) >= npcMinVelocity) {
            forward = VecNormalize(velocity);
        } else {
            forward = followedNpc.GetHeadingVector();
        }

        desiredPos = followedNpc.GetWorldPosition() - forward * npcCamDistance;
        desiredPos.Z = desiredPos.Z + npcCamHeight;

        lookAt = followedNpc.GetWorldPosition();
        lookAt.Z = lookAt.Z + npcLookAtHeight;

        rot = VecToRotation(lookAt - desiredPos);

        if (!npcCamSmoothingInitialized) {
            smoothedNpcCamPos = desiredPos;
            smoothedNpcCamRot = rot;
            npcCamSmoothingInitialized = true;
        } else {
            posAlpha = MinF(1.0f, npcCamPositionSmooth * npcCamTickInterval);
            rotAlpha = MinF(1.0f, npcCamRotationSmooth * npcCamTickInterval);

            smoothedNpcCamPos = LerpV(smoothedNpcCamPos, desiredPos, posAlpha);
            smoothedNpcCamRot.Pitch = LerpAngleF(rotAlpha, smoothedNpcCamRot.Pitch, rot.Pitch);
            smoothedNpcCamRot.Yaw = LerpAngleF(rotAlpha, smoothedNpcCamRot.Yaw, rot.Yaw);
            smoothedNpcCamRot.Roll = LerpAngleF(rotAlpha, smoothedNpcCamRot.Roll, rot.Roll);
        }

        camPos = smoothedNpcCamPos;
        npcStaticCam.TeleportWithRotation(camPos, smoothedNpcCamRot);
    }

    protected function stopNpcCamera() {
        followedNpc = NULL;
        followedNpcIsClone = false;
        npcCameraFollowUsesStaticFallback = false;
        npcCamSmoothingInitialized = false;

        if (npcStaticCam && npcStaticCam.IsRunning()) {
            npcStaticCam.Stop();
        }

        theGame.GetGameCamera().Activate(0.25f);
    }

    protected function findSafeWalkTarget(out target : Vector) : bool {
        return findSafeTargetForActor((CActor)thePlayer, target);
    }

    protected function findSafeTargetForActor(actor: CActor, out target : Vector) : bool {
        var playerActor: CActor;
        var mac: CMovingAgentComponent;
        var world: CWorld;
        var candidate: Vector;
        var safeCandidate: Vector;
        var fallback: Vector;
        var hasFallback: bool;
        var i: int;

        playerActor = actor;
        if (!playerActor) {
            return false;
        }

        mac = playerActor.GetMovingAgentComponent();
        world = theGame.GetWorld();

        for (i = 0; i < walkTargetCandidates; i += 1) {
            candidate = randomGroundPosition(playerActor.GetWorldPosition(), minWalkDistance, maxWalkDistance);

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

            if (world.NavigationLineTest(playerActor.GetWorldPosition(), candidate, walkSafeSpotPersonalSpace, false, true)) {
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

        playerActor = (CActor)thePlayer;
        if (!playerActor) {
            return false;
        }

        if (!findSafeWalkTarget(currentWalkTarget)) {
            hasWalkTarget = false;
            log.error("failed to find safe walk target");
            return false;
        }

        if (issueScriptedMoveToPoint(playerActor, currentWalkTarget, walkSpeed, true)) {
            hasWalkTarget = true;
            walkTargetIssuedAt = theGame.GetEngineTimeAsSeconds();
            lastWalkPosition = thePlayer.GetWorldPosition();
            lastWalkProgressAt = walkTargetIssuedAt;
            log.debug("walk target issued: " + VecToString(currentWalkTarget));
        } else {
            hasWalkTarget = false;
            log.error("failed to issue walk target: " + VecToString(currentWalkTarget));
        }

        return hasWalkTarget;
    }

    protected function issueScriptedMoveToPoint(actor: CActor, target: Vector, speed: float, decoratePlayer: bool) : bool {
        var aiTree: CAIMoveToPoint;
        var decorator: CAIPlayerActionDecorator;
        var heading: Vector;

        if (!actor) {
            return false;
        }

        actor.ActionCancelAll();

        aiTree = new CAIMoveToPoint in actor;
        aiTree.OnCreated();
        aiTree.enterExplorationOnStart = false;
        aiTree.params.moveSpeed = speed;
        aiTree.params.destinationPosition = target;

        heading = target - actor.GetWorldPosition();
        heading.Z = 0.0f;
        if (VecLength(heading) > 0.1f) {
            aiTree.params.destinationHeading = VecHeading(heading);
        } else {
            aiTree.params.destinationHeading = VecHeading(actor.GetHeadingVector());
        }

        aiTree.params.maxDistance = walkArrivalDistance;
        aiTree.params.maxIterationsNumber = 1;
        aiTree.params.useTimeout = true;
        aiTree.params.timeoutValue = walkTargetTimeout;

        if (speed >= 2.0f) {
            aiTree.params.moveType = MT_Sprint;
        } else if (speed >= 1.0f) {
            aiTree.params.moveType = MT_FastRun;
        } else {
            aiTree.params.moveType = MT_Walk;
        }

        if (decoratePlayer) {
            thePlayer.GetMovingAgentComponent().SetGameplayMoveDirection(aiTree.params.destinationHeading);

            decorator = new CAIPlayerActionDecorator in actor;
            decorator.OnCreated();
            decorator.interruptOnInput = true;
            decorator.scriptedAction = aiTree;

            if (decorator) {
                actor.ForceAIBehavior(decorator, BTAP_Emergency);
            } else {
                actor.ForceAIBehavior(aiTree, BTAP_Emergency);
            }
        } else {
            actor.ForceAIBehavior(aiTree, BTAP_Emergency);
        }

        return true;
    }

    protected function issueDirectTarget() : bool {
        if (!autoClone) {
            return false;
        }

        if (!findSafeTargetForActor(autoClone, currentDirectTarget)) {
            hasDirectTarget = false;
            log.error("failed to find clone target");
            return false;
        }

        hasDirectTarget = true;
        directTargetIssuedAt = theGame.GetEngineTimeAsSeconds();
        lastDirectPosition = autoClone.GetWorldPosition();
        lastDirectProgressAt = directTargetIssuedAt;
        log.debug("clone target issued: " + VecToString(currentDirectTarget));
        issueScriptedMoveToPoint(autoClone, currentDirectTarget, cloneMoveSpeed, false);
        return true;
    }

    protected function directTargetNeedsRefresh() : bool {
        if (!hasDirectTarget) {
            return true;
        }

        if (!autoClone) {
            return true;
        }

        if (VecDistance2D(autoClone.GetWorldPosition(), currentDirectTarget) <= directArrivalDistance) {
            return true;
        }

        if (theGame.GetEngineTimeAsSeconds() >= directTargetIssuedAt + directRetargetInterval) {
            return true;
        }

        return false;
    }

    protected function updateDirectProgress() {
        var currentPosition: Vector;

        if (!autoClone) {
            return;
        }

        if (!hasDirectTarget) {
            lastDirectPosition = autoClone.GetWorldPosition();
            lastDirectProgressAt = theGame.GetEngineTimeAsSeconds();
            return;
        }

        currentPosition = autoClone.GetWorldPosition();
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

    protected function ensureAutoClone() : bool {
        var template: CEntityTemplate;
        var entity: CEntity;
        var spawnPos: Vector;
        var actor: CActor;

        if (autoClone) {
            return true;
        }

        template = (CEntityTemplate)LoadResource("dlc\modtemplates\storyboardui\geralt_npc.w2ent", true);
        if (!template) {
            notify("AutoDriver could not load StoryBoardUI Geralt clone template");
            return false;
        }

        spawnPos = thePlayer.GetWorldPosition() + thePlayer.GetHeadingVector() * cloneSpawnDistance;
        spawnPos = randomGroundPosition(spawnPos, 0.0f, 1.0f);

        entity = theGame.CreateEntity(template, spawnPos, thePlayer.GetWorldRotation());
        actor = (CActor)entity;
        if (!actor) {
            notify("AutoDriver could not create Geralt NPC clone");
            return false;
        }

        actor.EnableCharacterCollisions(false);
        actor.EnableCollisions(false);
        actor.SetTemporaryAttitudeGroup('q104_avallach_friendly_to_all', AGP_Default);
        actor.AddTag('AutoDriverClone');

        autoClone = actor;
        followedNpc = actor;
        followedNpcIsClone = true;
        followedNpcSelectedAt = theGame.GetEngineTimeAsSeconds();
        npcCamSmoothingInitialized = false;

        return true;
    }

    protected function startCloneWander() : bool {
        if (!ensureAutoClone()) {
            return false;
        }

        if (!ensureStaticNpcCamera()) {
            return false;
        }

        followedNpc = autoClone;
        followedNpcIsClone = true;
        npcStaticCam.Run();
        updateStaticCameraPlacement();
        notify("AutoDriver Geralt clone wander started");
        return true;
    }

    protected function destroyAutoClone() {
        if (autoClone) {
            autoClone.ActionCancelAll();
            autoClone.Destroy();
            autoClone = NULL;
        }

        followedNpcIsClone = false;
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
                notify("AutoDriver Geralt clone wander stopped");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_DirectWander');
            }
        }
    }

    event OnToggleCameraFollowNpc(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_CameraFollowNpc') {
                stopNpcCamera();
                GotoState('AutoDriver_Idle');
                notify("AutoDriver NPC camera follow stopped");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_CameraFollowNpc');
            }
        }
    }

    event OnToggleStaticCameraFollowNpc(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_StaticCameraFollowNpc') {
                stopNpcCamera();
                GotoState('AutoDriver_Idle');
                notify("AutoDriver static NPC camera stopped");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_StaticCameraFollowNpc');
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
        if (!parent.startCloneWander()) {
            parent.GotoState('AutoDriver_Idle');
            return;
        }
        DirectLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopCurrentAction();
        super.OnLeaveState(nextStateName);
    }

    entry function DirectLoop() {
        while (parent.GetCurrentStateName() == 'AutoDriver_DirectWander') {
            if (thePlayer.IsUsingHorse(true)) {
                parent.notify("AutoDriver clone wander requires dismounted player");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            parent.updateDirectProgress();

            if (parent.directTargetNeedsRefresh() || parent.isDirectTargetStuck()) {
                parent.issueDirectTarget();
            }

            parent.updateStaticCameraPlacement();
            Sleep(parent.walkTickInterval);
        }
    }
}

state AutoDriver_CameraFollowNpc in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.startGameCameraFollowNpc();
        CameraFollowLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopNpcCamera();
        super.OnLeaveState(nextStateName);
    }

    entry function CameraFollowLoop() {
        while (parent.GetCurrentStateName() == 'AutoDriver_CameraFollowNpc') {
            parent.updateGameCameraFollowNpc();
            Sleep(parent.npcCamTickInterval);
        }
    }
}

state AutoDriver_StaticCameraFollowNpc in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.startStaticCameraFollowNpc();
        StaticCameraFollowLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopNpcCamera();
        super.OnLeaveState(nextStateName);
    }

    entry function StaticCameraFollowLoop() {
        while (parent.GetCurrentStateName() == 'AutoDriver_StaticCameraFollowNpc') {
            parent.updateStaticCameraPlacement();
            Sleep(parent.npcCamTickInterval);
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
