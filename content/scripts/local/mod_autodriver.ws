// ----------------------------------------------------------------------------
// AutoDriver prototype
// ----------------------------------------------------------------------------
class CAutoDriverMoveTRGSeek extends CMoveTRGScript {
    public var target: Vector;
    public var speed: float;
    public var arrivalDistance: float;

    function UpdateChannels(out goal: SMoveLocomotionGoal) {
        var heading: Vector;

        if (VecDistance2D(agent.GetWorldPosition(), target) <= arrivalDistance) {
            SetFulfilled(goal, true);
            return;
        }

        SetFulfilled(goal, false);
        heading = Seek(target);
        SetSpeedGoal(goal, speed);
        SetHeadingGoal(goal, heading);
        SetOrientationGoal(goal, VecHeading(heading));
        MatchDirectionWithOrientation(goal, true);
    }
}

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
    protected var tunedMoveMinDistance: float; default tunedMoveMinDistance = 3.0;
    protected var tunedMoveMaxDistance: float; default tunedMoveMaxDistance = 7.0;
    protected var tunedMoveTickInterval: float; default tunedMoveTickInterval = 1.5;
    protected var tunedMoveTargetTimeout: float; default tunedMoveTargetTimeout = 12.0;
    protected var tunedMoveArrivalDistance: float; default tunedMoveArrivalDistance = 1.4;
    protected var tunedMoveSpeed: float; default tunedMoveSpeed = 1.0;
    protected var tunedMoveIterations: int; default tunedMoveIterations = 8;
    protected var customSeekMinDistance: float; default customSeekMinDistance = 6.0;
    protected var customSeekMaxDistance: float; default customSeekMaxDistance = 14.0;
    protected var customSeekTickInterval: float; default customSeekTickInterval = 0.5;
    protected var customSeekTargetTimeout: float; default customSeekTargetTimeout = 10.0;
    protected var customSeekArrivalDistance: float; default customSeekArrivalDistance = 2.0;
    protected var customSeekSpeed: float; default customSeekSpeed = 1.0;
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
    protected var godOxygenTickInterval: float; default godOxygenTickInterval = 0.25f;
    protected var randomTeleportMinRadius: float; default randomTeleportMinRadius = 20.0f;
    protected var randomTeleportMaxRadius: float; default randomTeleportMaxRadius = 100.0f;
    protected var randomTeleportSafeRadius: float; default randomTeleportSafeRadius = 6.0f;
    protected var randomTeleportPersonalSpace: float; default randomTeleportPersonalSpace = 1.0f;
    protected var randomTeleportZRange: float; default randomTeleportZRange = 20.0f;
    protected var randomTeleportMaxVerticalDelta: float; default randomTeleportMaxVerticalDelta = 50.0f;
    protected var randomTeleportStreamingDelay: float; default randomTeleportStreamingDelay = 2.0f;
    protected var randomTeleportAttempts: int; default randomTeleportAttempts = 20;
    protected var godModeEnabled: bool;

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
    protected var hasTunedMoveTarget: bool;
    protected var currentTunedMoveTarget: Vector;
    protected var tunedMoveTargetIssuedAt: float;
    protected var lastTunedMovePosition: Vector;
    protected var lastTunedMoveProgressAt: float;
    protected var hasCustomSeekTarget: bool;
    protected var currentCustomSeekTarget: Vector;
    protected var customSeekTargetIssuedAt: float;
    protected var lastCustomSeekPosition: Vector;
    protected var lastCustomSeekProgressAt: float;

    public function init() {
        super.init();

        theInput.RegisterListener(this, 'OnToggleWalkWander', 'AutoDriver_WalkWander');
        theInput.RegisterListener(this, 'OnToggleDirectWander', 'AutoDriver_DirectWander');
        theInput.RegisterListener(this, 'OnToggleCameraFollowNpc', 'AutoDriver_CameraFollowNpc');
        theInput.RegisterListener(this, 'OnToggleStaticCameraFollowNpc', 'AutoDriver_StaticCameraFollowNpc');
        theInput.RegisterListener(this, 'OnToggleHorseWander', 'AutoDriver_HorseWander');
        theInput.RegisterListener(this, 'OnToggleGodMode', 'AutoDriver_GodMode');
        theInput.RegisterListener(this, 'OnOfficialTeleport', 'AutoDriver_OfficialTeleport');
        theInput.RegisterListener(this, 'OnRandomXYTeleport', 'AutoDriver_RandomXYTeleport');

        GotoState('AutoDriver_Idle');
        notify("AutoDriver loaded: NumPad7 god, NumPad8 official teleport, NumPad9 random XY");
    }

    protected function notify(message: String) {
        GetWitcherPlayer().DisplayHudMessage(message);
        log.info(message);
    }

    protected function enableGodMode() {
        godModeEnabled = true;
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Default, true);
        maintainGodModeOxygen();
        notify("AutoDriver god mode ON: no health damage, oxygen refilled");
    }

    protected function disableGodMode() {
        godModeEnabled = false;
        thePlayer.SetImmortalityMode(AIM_None, AIC_Default, true);
        notify("AutoDriver god mode OFF");
    }

    protected function maintainGodModeOxygen() {
        if (!godModeEnabled || !thePlayer) {
            return;
        }

        thePlayer.ForceSetStat(BCS_Air, thePlayer.GetStatMax(BCS_Air));
        if (thePlayer.HasBuff(EET_Drowning)) {
            thePlayer.RemoveBuff(EET_Drowning);
        }
    }

    protected function canUseTeleport(out reason: String) : bool {
        if (!thePlayer) {
            reason = "player unavailable";
            return false;
        }

        if (thePlayer.IsInCombat()) {
            reason = "player is in combat";
            return false;
        }

        if (thePlayer.IsInGameplayScene() || theGame.IsCurrentlyPlayingNonGameplayScene()) {
            reason = "a story scene is active";
            return false;
        }

        if (thePlayer.IsUsingHorse(true)) {
            reason = "dismount horse first";
            return false;
        }

        if (thePlayer.IsSailing() || thePlayer.IsUsingBoat()) {
            reason = "leave the boat first";
            return false;
        }

        return true;
    }

    protected function formatFastTravelPin(pin: SAvailableFastTravelMapPin, index: int, total: int) : String {
        return IntToString(index + 1) + "/" + IntToString(total)
            + " tag=" + NameToString(pin.tag)
            + " type=" + NameToString(pin.type)
            + " area=" + pin.area;
    }

    protected function performOfficialTeleport() : bool {
        var manager: CCommonMapManager;
        var pins: array<SAvailableFastTravelMapPin>;
        var pin: SAvailableFastTravelMapPin;
        var index: int;
        var nextIndex: int;
        var worldPath: String;
        var currentWorldPath: String;
        var position: Vector;
        var rotation: EulerAngles;
        var positionResolved: bool;
        var landPoint: bool;
        var details: String;
        var reason: String;

        if (!canUseTeleport(reason)) {
            notify("AutoDriver teleport blocked: " + reason);
            return false;
        }

        manager = theGame.GetCommonMapManager();
        pins = manager.GetFastTravelPoints(false, false, false, false, false);
        if (pins.Size() == 0) {
            notify("AutoDriver official teleport list is empty");
            return false;
        }

        index = FactsQuerySum("autodriver_official_teleport_index");
        if (index < 0 || index >= pins.Size()) {
            index = 0;
        }

        pin = pins[index];
        details = formatFastTravelPin(pin, index, pins.Size());
        worldPath = manager.GetWorldPathFromAreaType(pin.area);
        currentWorldPath = theGame.GetWorld().GetDepotPath();
        landPoint = pin.type == 'RoadSign';

        if (StrLen(worldPath) == 0) {
            notify("AutoDriver unknown teleport world: " + details);
            log.error("official teleport failed: " + details + " worldPath=<empty>");
            return false;
        }

        positionResolved = manager.GetFastTravelPointPosition(worldPath, pin.tag, landPoint, position, rotation);
        nextIndex = index + 1;
        if (nextIndex >= pins.Size()) {
            nextIndex = 0;
        }

        stopCurrentAction();
        rotation.Pitch = 0.0f;
        rotation.Roll = 0.0f;

        if (worldPath == currentWorldPath) {
            if (!positionResolved) {
                notify("AutoDriver local teleport position failed: " + details);
                log.error("official teleport local failed: " + details + " worldPath=" + worldPath);
                return false;
            }

            FactsSet("autodriver_official_teleport_index", nextIndex, -1);
            log.info("official teleport local: " + details + " worldPath=" + worldPath
                + " position=" + VecToString(position) + " resolved=true issued=true");
            notify("AutoDriver official teleport: " + details);
            thePlayer.TeleportWithRotation(position, rotation);
            return true;
        }

        FactsSet("autodriver_official_teleport_index", nextIndex, -1);
        if (positionResolved) {
            log.info("official teleport global: " + details + " worldPath=" + worldPath
                + " position=" + VecToString(position) + " resolved=true issued=true");
            notify("AutoDriver cross-world teleport: " + details);
            theGame.ScheduleWorldChangeToPosition(worldPath, position, rotation);
        } else {
            log.info("official teleport global fallback: " + details + " worldPath=" + worldPath
                + " resolved=false issued=true");
            notify("AutoDriver cross-world map-pin fallback: " + details);
            theGame.ScheduleWorldChangeToMapPin(worldPath, pin.tag);
        }

        return true;
    }

    protected function getCurrentWorldRoadSignAnchors(out anchors: array<SAvailableFastTravelMapPin>) : bool {
        var manager: CCommonMapManager;
        var pins: array<SAvailableFastTravelMapPin>;
        var currentWorldPath: String;
        var pinWorldPath: String;
        var i: int;

        manager = theGame.GetCommonMapManager();
        pins = manager.GetFastTravelPoints(false, false, false, false, false);
        currentWorldPath = theGame.GetWorld().GetDepotPath();

        for (i = 0; i < pins.Size(); i += 1) {
            if (pins[i].type != 'RoadSign') {
                continue;
            }

            pinWorldPath = manager.GetWorldPathFromAreaType(pins[i].area);
            if (pinWorldPath == currentWorldPath) {
                anchors.PushBack(pins[i]);
            }
        }

        return anchors.Size() > 0;
    }

    protected function findRandomSafeTeleportPosition(anchor: Vector, out target: Vector) : bool {
        var world: CWorld;
        var mac: CMovingAgentComponent;
        var candidate: Vector;
        var safePosition: Vector;
        var correctedPosition: Vector;
        var correctedZ: float;
        var physicsZ: float;
        var i: int;

        world = theGame.GetWorld();
        mac = thePlayer.GetMovingAgentComponent();
        if (!world || !mac) {
            return false;
        }

        for (i = 0; i < randomTeleportAttempts; i += 1) {
            candidate = anchor + VecRingRand(randomTeleportMinRadius, randomTeleportMaxRadius);
            candidate.Z = anchor.Z;

            if (!world.NavigationFindSafeSpot(
                candidate,
                randomTeleportPersonalSpace,
                randomTeleportSafeRadius,
                safePosition
            )) {
                continue;
            }

            if (!world.NavigationComputeZ(
                safePosition,
                anchor.Z - randomTeleportZRange,
                anchor.Z + randomTeleportZRange,
                correctedZ
            )) {
                continue;
            }

            safePosition.Z = correctedZ;
            if (!world.NavigationFindSafeSpot(
                safePosition,
                randomTeleportPersonalSpace,
                randomTeleportSafeRadius,
                correctedPosition
            )) {
                continue;
            }

            if (AbsF(correctedPosition.Z - anchor.Z) > randomTeleportMaxVerticalDelta) {
                continue;
            }

            if (!mac.IsPositionValid(correctedPosition)) {
                continue;
            }

            if (world.PhysicsCorrectZ(correctedPosition, physicsZ)) {
                correctedPosition.Z = physicsZ;
                if (!mac.IsPositionValid(correctedPosition)) {
                    continue;
                }
            }

            target = correctedPosition;
            return true;
        }

        return false;
    }

    protected latent function performRandomXYTeleport() : bool {
        var manager: CCommonMapManager;
        var anchors: array<SAvailableFastTravelMapPin>;
        var anchorPin: SAvailableFastTravelMapPin;
        var anchorIndex: int;
        var currentWorldPath: String;
        var anchorPosition: Vector;
        var targetPosition: Vector;
        var rotation: EulerAngles;
        var reason: String;
        var result: bool;

        if (!canUseTeleport(reason)) {
            notify("AutoDriver random teleport blocked: " + reason);
            return false;
        }

        if (!getCurrentWorldRoadSignAnchors(anchors)) {
            notify("AutoDriver found no current-world RoadSign anchor");
            return false;
        }

        manager = theGame.GetCommonMapManager();
        currentWorldPath = theGame.GetWorld().GetDepotPath();
        anchorIndex = RandRange(anchors.Size());
        anchorPin = anchors[anchorIndex];

        if (!manager.GetFastTravelPointPosition(
            currentWorldPath,
            anchorPin.tag,
            true,
            anchorPosition,
            rotation
        )) {
            notify("AutoDriver failed to resolve random anchor " + NameToString(anchorPin.tag));
            return false;
        }

        stopCurrentAction();
        rotation.Pitch = 0.0f;
        rotation.Roll = 0.0f;
        notify("AutoDriver random XY anchor: " + NameToString(anchorPin.tag));
        log.info("random XY anchor tag=" + NameToString(anchorPin.tag)
            + " position=" + VecToString(anchorPosition));
        thePlayer.TeleportWithRotation(anchorPosition, rotation);

        Sleep(randomTeleportStreamingDelay);

        if (!findRandomSafeTeleportPosition(anchorPosition, targetPosition)) {
            notify("AutoDriver random XY validation failed; staying at safe anchor");
            log.error("random XY failed around anchor=" + NameToString(anchorPin.tag));
            return false;
        }

        rotation = thePlayer.GetWorldRotation();
        rotation.Pitch = 0.0f;
        rotation.Roll = 0.0f;
        thePlayer.TeleportWithRotation(targetPosition, rotation);
        notify("AutoDriver random XY teleport complete");
        log.info("random XY success anchor=" + NameToString(anchorPin.tag)
            + " target=" + VecToString(targetPosition));
        result = true;
        return result;
    }

    protected function stopCurrentAction() {
        var horse: CActor;
        var mac: CMovingAgentComponent;

        thePlayer.ActionCancelAll();
        resetWalkTarget();
        resetDirectTarget();
        resetTunedMoveTarget();
        resetCustomSeekTarget();
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
        return findSafeTargetForActorInRange((CActor)thePlayer, minWalkDistance, maxWalkDistance, target);
    }

    protected function findSafeTargetForActor(actor: CActor, out target : Vector) : bool {
        return findSafeTargetForActorInRange(actor, minWalkDistance, maxWalkDistance, target);
    }

    protected function findSafeTargetForActorInRange(actor: CActor, minDistance: float, maxDistance: float, out target : Vector) : bool {
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
            candidate = randomGroundPosition(playerActor.GetWorldPosition(), minDistance, maxDistance);

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

    protected function resetTunedMoveTarget() {
        hasTunedMoveTarget = false;
        lastTunedMovePosition = thePlayer.GetWorldPosition();
        lastTunedMoveProgressAt = theGame.GetEngineTimeAsSeconds();
    }

    protected function resetCustomSeekTarget() {
        hasCustomSeekTarget = false;
        lastCustomSeekPosition = thePlayer.GetWorldPosition();
        lastCustomSeekProgressAt = theGame.GetEngineTimeAsSeconds();
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
        return issueScriptedMoveToPointEx(actor, target, speed, decoratePlayer, 1, walkTargetTimeout, walkArrivalDistance, true);
    }

    protected function issueScriptedMoveToPointEx(
        actor: CActor,
        target: Vector,
        speed: float,
        decoratePlayer: bool,
        iterations: int,
        timeout: float,
        arrivalDistance: float,
        interruptOnInput: bool
    ) : bool {
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

        aiTree.params.maxDistance = arrivalDistance;
        aiTree.params.maxIterationsNumber = iterations;
        aiTree.params.useTimeout = true;
        aiTree.params.timeoutValue = timeout;

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
            decorator.interruptOnInput = interruptOnInput;
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

    protected function issueTunedMovePointTarget() : bool {
        var playerActor: CActor;

        playerActor = (CActor)thePlayer;
        if (!playerActor) {
            return false;
        }

        if (!findSafeTargetForActorInRange(playerActor, tunedMoveMinDistance, tunedMoveMaxDistance, currentTunedMoveTarget)) {
            hasTunedMoveTarget = false;
            log.error("failed to find tuned move target");
            return false;
        }

        if (issueScriptedMoveToPointEx(
            playerActor,
            currentTunedMoveTarget,
            tunedMoveSpeed,
            true,
            tunedMoveIterations,
            tunedMoveTargetTimeout,
            tunedMoveArrivalDistance,
            false
        )) {
            hasTunedMoveTarget = true;
            tunedMoveTargetIssuedAt = theGame.GetEngineTimeAsSeconds();
            lastTunedMovePosition = thePlayer.GetWorldPosition();
            lastTunedMoveProgressAt = tunedMoveTargetIssuedAt;
            log.debug("tuned move target issued: " + VecToString(currentTunedMoveTarget));
        } else {
            hasTunedMoveTarget = false;
            log.error("failed to issue tuned move target: " + VecToString(currentTunedMoveTarget));
        }

        return hasTunedMoveTarget;
    }

    protected function tunedMoveTargetNeedsRefresh() : bool {
        if (!hasTunedMoveTarget) {
            return true;
        }

        if (VecDistance2D(thePlayer.GetWorldPosition(), currentTunedMoveTarget) <= tunedMoveArrivalDistance) {
            return true;
        }

        if (theGame.GetEngineTimeAsSeconds() >= tunedMoveTargetIssuedAt + tunedMoveTargetTimeout) {
            return true;
        }

        return false;
    }

    protected function updateTunedMoveProgress() {
        var currentPosition: Vector;

        if (!hasTunedMoveTarget) {
            lastTunedMovePosition = thePlayer.GetWorldPosition();
            lastTunedMoveProgressAt = theGame.GetEngineTimeAsSeconds();
            return;
        }

        currentPosition = thePlayer.GetWorldPosition();
        if (VecDistance2D(currentPosition, lastTunedMovePosition) >= walkStuckDistance) {
            lastTunedMovePosition = currentPosition;
            lastTunedMoveProgressAt = theGame.GetEngineTimeAsSeconds();
        }
    }

    protected function isTunedMoveTargetStuck() : bool {
        if (!hasTunedMoveTarget) {
            return true;
        }

        return theGame.GetEngineTimeAsSeconds() >= lastTunedMoveProgressAt + walkStuckTimeout;
    }

    protected function issueCustomSeekTarget() : bool {
        var playerActor: CActor;
        var targeter: CAutoDriverMoveTRGSeek;
        var result: bool;

        playerActor = (CActor)thePlayer;
        if (!playerActor) {
            return false;
        }

        if (!findSafeTargetForActorInRange(playerActor, customSeekMinDistance, customSeekMaxDistance, currentCustomSeekTarget)) {
            hasCustomSeekTarget = false;
            log.error("failed to find custom seek target");
            return false;
        }

        playerActor.ActionCancelAll();
        targeter = new CAutoDriverMoveTRGSeek in playerActor;
        targeter.target = currentCustomSeekTarget;
        targeter.speed = customSeekSpeed;
        targeter.arrivalDistance = customSeekArrivalDistance;
        result = playerActor.ActionMoveCustomAsync(targeter);

        if (result) {
            hasCustomSeekTarget = true;
            customSeekTargetIssuedAt = theGame.GetEngineTimeAsSeconds();
            lastCustomSeekPosition = thePlayer.GetWorldPosition();
            lastCustomSeekProgressAt = customSeekTargetIssuedAt;
            log.debug("custom seek target issued: " + VecToString(currentCustomSeekTarget));
        } else {
            hasCustomSeekTarget = false;
            log.error("failed to issue custom seek target: " + VecToString(currentCustomSeekTarget));
        }

        return result;
    }

    protected function customSeekTargetNeedsRefresh() : bool {
        if (!hasCustomSeekTarget) {
            return true;
        }

        if (VecDistance2D(thePlayer.GetWorldPosition(), currentCustomSeekTarget) <= customSeekArrivalDistance) {
            return true;
        }

        if (theGame.GetEngineTimeAsSeconds() >= customSeekTargetIssuedAt + customSeekTargetTimeout) {
            return true;
        }

        return false;
    }

    protected function updateCustomSeekProgress() {
        var currentPosition: Vector;

        if (!hasCustomSeekTarget) {
            lastCustomSeekPosition = thePlayer.GetWorldPosition();
            lastCustomSeekProgressAt = theGame.GetEngineTimeAsSeconds();
            return;
        }

        currentPosition = thePlayer.GetWorldPosition();
        if (VecDistance2D(currentPosition, lastCustomSeekPosition) >= walkStuckDistance) {
            lastCustomSeekPosition = currentPosition;
            lastCustomSeekProgressAt = theGame.GetEngineTimeAsSeconds();
        }
    }

    protected function isCustomSeekTargetStuck() : bool {
        if (!hasCustomSeekTarget) {
            return true;
        }

        return theGame.GetEngineTimeAsSeconds() >= lastCustomSeekProgressAt + walkStuckTimeout;
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

    event OnToggleGodMode(action: SInputAction) {
        if (IsPressed(action)) {
            if (godModeEnabled) {
                disableGodMode();
            } else {
                enableGodMode();
            }
        }
    }

    event OnOfficialTeleport(action: SInputAction) {
        if (IsPressed(action)) {
            performOfficialTeleport();
        }
    }

    event OnRandomXYTeleport(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_RandomXYTeleport') {
                notify("AutoDriver random XY teleport is already running");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_RandomXYTeleport');
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
        } else {
            DirectLoop();
        }
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

state AutoDriver_TunedMovePointWander in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.resetTunedMoveTarget();
        parent.notify("AutoDriver tuned move point wander started");
        TunedMovePointLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopCurrentAction();
        super.OnLeaveState(nextStateName);
    }

    entry function TunedMovePointLoop() {
        while (parent.GetCurrentStateName() == 'AutoDriver_TunedMovePointWander') {
            if (thePlayer.IsUsingHorse(true)) {
                parent.notify("AutoDriver tuned move point requires dismounted player");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            parent.updateTunedMoveProgress();

            if (parent.tunedMoveTargetNeedsRefresh() || parent.isTunedMoveTargetStuck()) {
                parent.issueTunedMovePointTarget();
            }

            Sleep(parent.tunedMoveTickInterval);
        }
    }
}

state AutoDriver_CustomSeekWander in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.resetCustomSeekTarget();
        parent.notify("AutoDriver custom seek wander started");
        CustomSeekLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopCurrentAction();
        super.OnLeaveState(nextStateName);
    }

    entry function CustomSeekLoop() {
        while (parent.GetCurrentStateName() == 'AutoDriver_CustomSeekWander') {
            if (thePlayer.IsUsingHorse(true)) {
                parent.notify("AutoDriver custom seek requires dismounted player");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            parent.updateCustomSeekProgress();

            if (parent.customSeekTargetNeedsRefresh() || parent.isCustomSeekTargetStuck()) {
                parent.issueCustomSeekTarget();
            }

            Sleep(parent.customSeekTickInterval);
        }
    }
}

state AutoDriver_RandomXYTeleport in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        RandomXYTeleportLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        super.OnLeaveState(nextStateName);
    }

    entry function RandomXYTeleportLoop() {
        parent.performRandomXYTeleport();
        parent.GotoState('AutoDriver_Idle');
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
