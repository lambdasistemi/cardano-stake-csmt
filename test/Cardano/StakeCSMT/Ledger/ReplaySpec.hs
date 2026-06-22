module Cardano.StakeCSMT.Ledger.ReplaySpec
    ( spec
    ) where

import Cardano.Node.Client.N2C.ChainSync
    ( Fetched (..)
    , HeaderPoint
    )
import Cardano.Node.Client.Types
    ( Block
    )
import Cardano.StakeCSMT.Ledger.Checkpoint
    ( CheckpointPoint (..)
    , ReplayCheckpoint (..)
    , listReplayCheckpoints
    , saveReplayCheckpoint
    )
import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle (..)
    , ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition (..)
    , ReplayCheckpointConfig (..)
    , ReplayFollowerConfig (..)
    , ReplayState (..)
    , initialReplayState
    , observeEpochTransition
    , runReplayFollowerWith
    , runReplayFollowerWithCheckpoints
    )
import ChainFollower
    ( Follower (..)
    , Intersector (..)
    , ProgressOrRewind (..)
    )
import Data.IORef
    ( IORef
    , modifyIORef'
    , newIORef
    , readIORef
    )
import Data.Map.Strict qualified as Map
import Data.Word
    ( Word64
    )
import Ouroboros.Network.Block qualified as Network
import Ouroboros.Network.Magic
    ( NetworkMagic (..)
    )
import Ouroboros.Network.Point qualified as Network.Point
import System.IO.Temp
    ( withSystemTempDirectory
    )
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    )
import Unsafe.Coerce
    ( unsafeCoerce
    )

spec :: Spec
spec =
    describe "Ledger.Replay" $ do
        it "starts from the configured genesis ledger state and epoch zero" $ do
            bundle <- loadDevnetBundle

            state <- initialReplayState bundle

            replayStateLedgerState state
                `shouldBe` ledgerConfigGenesisState bundle
            replayStateLastEpoch state `shouldBe` 0

        it "emits epoch transitions once per observed epoch change" $ do
            bundle <- loadDevnetBundle
            transitions <- newIORef []
            state0 <- initialReplayState bundle

            state1 <-
                observeEpochTransition
                    (modifyIORef' transitions . (:))
                    state0
                    1
                    0
            state2 <-
                observeEpochTransition
                    (modifyIORef' transitions . (:))
                    state1
                    2
                    1
            state3 <-
                observeEpochTransition
                    (modifyIORef' transitions . (:))
                    state2
                    3
                    1

            replayStateLastEpoch state1 `shouldBe` 0
            replayStateLastEpoch state2 `shouldBe` 1
            replayStateLastEpoch state3 `shouldBe` 1
            recorded <- readIORef transitions
            recorded
                `shouldBe` [ EpochTransition
                                { epochTransitionPreviousEpoch = 0
                                , epochTransitionNewEpoch = 1
                                , epochTransitionSlot = 2
                                }
                           ]

        it "starts from Origin and threads replay state through roll-forward" $ do
            bundle <- loadDevnetBundle
            replayEpochs <- newIORef []
            let config =
                    ReplayFollowerConfig
                        { replayFollowerSocketPath = "node.socket"
                        , replayFollowerNetworkMagic =
                            NetworkMagic 42
                        , replayFollowerByronEpochSlots = 21_600
                        }
                replayAction state _block = do
                    modifyIORef'
                        replayEpochs
                        (replayStateLastEpoch state :)
                    pure
                        state
                            { replayStateLastEpoch =
                                replayStateLastEpoch state + 1
                            }
                fakeRunner _ _ _ _ _ Intersector{intersectFound} points = do
                    assertOriginStart points
                    follower0 <-
                        intersectFound
                            (Network.Point Network.Point.Origin)
                    followerAfterOriginRollback <-
                        rollBackward
                            follower0
                            (Network.Point Network.Point.Origin)
                            >>= \case
                                Progress follower ->
                                    pure follower
                                Rewind _ _ ->
                                    fail
                                        "expected origin rollback to progress, got rewind"
                                Reset _ ->
                                    fail
                                        "expected origin rollback to progress, got reset"
                    follower1 <-
                        rollForward
                            followerAfterOriginRollback
                            unusedFetched
                            unusedTip
                    _follower2 <-
                        rollForward follower1 unusedFetched unusedTip
                    pure (Right ())
                unusedFetched =
                    Fetched
                        { fetchedPoint =
                            Network.Point Network.Point.Origin
                        , fetchedBlock =
                            error "fetchedBlock should not be evaluated"
                        , fetchedTip = unusedLocalTip
                        }
                unusedLocalTip =
                    error "tip should not be evaluated"

            result <-
                runReplayFollowerWith
                    fakeRunner
                    replayAction
                    bundle
                    config

            case result of
                Left err ->
                    expectationFailure
                        $ "expected replay follower to finish, got "
                            <> show err
                Right () ->
                    pure ()
            recordedEpochs <- readIORef replayEpochs
            recordedEpochs `shouldBe` [1, 0]

        it
            "rewinds from the nearest checkpoint and retained tail on rollback"
            $ do
                bundle <- loadDevnetBundle
                replayApplications <- newIORef []
                state0 <- initialReplayState bundle

                withSystemTempDirectory "stake-csmt-replay-checkpoints" $ \directory -> do
                    let checkpoint =
                            ReplayCheckpoint
                                { replayCheckpointPoint = CheckpointAtBlock 1
                                , replayCheckpointFinalizedEpoch = 1
                                , replayCheckpointObservedEpoch = 1
                                }
                        checkpointState =
                            state0{replayStateLastEpoch = 1}
                    savedStates <-
                        newIORef
                            $ Map.singleton
                                (replayCheckpointPoint checkpoint)
                                checkpointState
                    _ <- saveReplayCheckpoint directory checkpoint

                    let checkpointConfig =
                            ReplayCheckpointConfig
                                { replayCheckpointDirectory = directory
                                , replayCheckpointTailLimit = 8
                                , replayCheckpointCadence = 0
                                , replayCheckpointSaveState =
                                    \savedCheckpoint state ->
                                        modifyIORef' savedStates
                                            $ Map.insert
                                                (replayCheckpointPoint savedCheckpoint)
                                                state
                                , replayCheckpointLoadState =
                                    \savedCheckpoint ->
                                        Map.lookup
                                            (replayCheckpointPoint savedCheckpoint)
                                            <$> readIORef savedStates
                                }
                        replayAction state block = do
                            let slot = syntheticBlockSlot block
                            modifyIORef'
                                replayApplications
                                ((replayStateLastEpoch state, slot) :)
                            pure state{replayStateLastEpoch = slot}
                        fakeRunner _ _ _ _ _ Intersector{intersectFound} points = do
                            assertOriginStart points
                            follower0 <-
                                intersectFound
                                    (Network.Point Network.Point.Origin)
                            follower1 <-
                                rollForward
                                    follower0
                                    (fetchedAt 1)
                                    unusedTip
                            follower2 <-
                                rollForward
                                    follower1
                                    (fetchedAt 2)
                                    unusedTip
                            follower3 <-
                                rollForward
                                    follower2
                                    (fetchedAt 3)
                                    unusedTip
                            followerRecovered <-
                                expectProgress
                                    "rollback to retained slot 2"
                                    =<< rollBackward
                                        follower3
                                        (headerPointAt 2)
                            follower4 <-
                                rollForward
                                    followerRecovered
                                    (fetchedAt 4)
                                    unusedTip
                            expectReset
                                "rollback to truncated slot 3"
                                =<< rollBackward follower4 (headerPointAt 3)
                            pure (Right ())

                    result <-
                        runReplayFollowerWithCheckpoints
                            fakeRunner
                            replayAction
                            bundle
                            testReplayConfig
                            checkpointConfig

                    case result of
                        Left err ->
                            expectationFailure
                                $ "expected replay follower to finish, got "
                                    <> show err
                        Right () ->
                            pure ()
                recordedApplications <-
                    reverse <$> readIORef replayApplications
                recordedApplications
                    `shouldBe` [ (0, 1)
                               , (1, 2)
                               , (2, 3)
                               , (1, 2)
                               , (2, 4)
                               ]

        it "resets when non-origin rollback is outside retained tail" $ do
            bundle <- loadDevnetBundle
            state0 <- initialReplayState bundle

            withSystemTempDirectory "stake-csmt-replay-checkpoints" $ \directory -> do
                let checkpoint =
                        ReplayCheckpoint
                            { replayCheckpointPoint = CheckpointAtBlock 1
                            , replayCheckpointFinalizedEpoch = 1
                            , replayCheckpointObservedEpoch = 1
                            }
                    checkpointState =
                        state0{replayStateLastEpoch = 1}
                savedStates <-
                    newIORef
                        $ Map.singleton
                            (replayCheckpointPoint checkpoint)
                            checkpointState
                _ <- saveReplayCheckpoint directory checkpoint

                let checkpointConfig =
                        replayCheckpointConfig directory savedStates 2 0
                    fakeRunner _ _ _ _ _ Intersector{intersectFound} points = do
                        assertOriginStart points
                        follower0 <-
                            intersectFound
                                (Network.Point Network.Point.Origin)
                        follower1 <-
                            rollForward follower0 (fetchedAt 1) unusedTip
                        follower2 <-
                            rollForward follower1 (fetchedAt 2) unusedTip
                        follower3 <-
                            rollForward follower2 (fetchedAt 3) unusedTip
                        follower4 <-
                            rollForward follower3 (fetchedAt 4) unusedTip
                        expectReset
                            "rollback before oldest retained tail"
                            =<< rollBackward follower4 (headerPointAt 3)
                        pure (Right ())

                result <-
                    runReplayFollowerWithCheckpoints
                        fakeRunner
                        advanceReplayEpoch
                        bundle
                        testReplayConfig
                        checkpointConfig

                case result of
                    Left err ->
                        expectationFailure
                            $ "expected replay follower to finish, got "
                                <> show err
                    Right () ->
                        pure ()

        it "keeps origin rollback progressing in checkpoint-aware replay" $ do
            bundle <- loadDevnetBundle

            withSystemTempDirectory "stake-csmt-replay-checkpoints" $ \directory -> do
                savedStates <- newIORef Map.empty
                let checkpointConfig =
                        replayCheckpointConfig directory savedStates 8 0
                    fakeRunner _ _ _ _ _ Intersector{intersectFound} points = do
                        assertOriginStart points
                        follower0 <-
                            intersectFound
                                (Network.Point Network.Point.Origin)
                        followerAfterRollback <-
                            expectProgress
                                "origin rollback"
                                =<< rollBackward
                                    follower0
                                    (Network.Point Network.Point.Origin)
                        _follower1 <-
                            rollForward
                                followerAfterRollback
                                (fetchedAt 1)
                                unusedTip
                        pure (Right ())

                result <-
                    runReplayFollowerWithCheckpoints
                        fakeRunner
                        advanceReplayEpoch
                        bundle
                        testReplayConfig
                        checkpointConfig

                case result of
                    Left err ->
                        expectationFailure
                            $ "expected replay follower to finish, got "
                                <> show err
                    Right () ->
                        pure ()

        it "saves checkpoint metadata at the configured cadence" $ do
            bundle <- loadDevnetBundle

            withSystemTempDirectory "stake-csmt-replay-checkpoints" $ \directory -> do
                savedStates <- newIORef Map.empty
                let checkpointConfig =
                        replayCheckpointConfig directory savedStates 8 2
                    fakeRunner _ _ _ _ _ Intersector{intersectFound} points = do
                        assertOriginStart points
                        follower0 <-
                            intersectFound
                                (Network.Point Network.Point.Origin)
                        follower1 <-
                            rollForward follower0 (fetchedAt 1) unusedTip
                        follower2 <-
                            rollForward follower1 (fetchedAt 2) unusedTip
                        _follower3 <-
                            rollForward follower2 (fetchedAt 3) unusedTip
                        pure (Right ())

                result <-
                    runReplayFollowerWithCheckpoints
                        fakeRunner
                        advanceReplayEpoch
                        bundle
                        testReplayConfig
                        checkpointConfig

                case result of
                    Left err ->
                        expectationFailure
                            $ "expected replay follower to finish, got "
                                <> show err
                    Right () ->
                        pure ()
                listReplayCheckpoints directory
                    >>= (`shouldBe` [CheckpointAtBlock 2])

loadDevnetBundle :: IO LedgerConfigBundle
loadDevnetBundle =
    loadLedgerConfig
        $ ledgerConfigPathsFromDirectory
            "test/fixtures/devnet-genesis"

assertOriginStart :: [Network.Point block] -> IO ()
assertOriginStart points =
    case points of
        [Network.Point Network.Point.Origin] ->
            pure ()
        other ->
            expectationFailure
                $ "expected [Origin], got "
                    <> show (length other)
                    <> " start points"

testReplayConfig :: ReplayFollowerConfig
testReplayConfig =
    ReplayFollowerConfig
        { replayFollowerSocketPath = "node.socket"
        , replayFollowerNetworkMagic = NetworkMagic 42
        , replayFollowerByronEpochSlots = 21_600
        }

replayCheckpointConfig
    :: FilePath
    -> IORef (Map.Map CheckpointPoint ReplayState)
    -> Int
    -> Word64
    -> ReplayCheckpointConfig
replayCheckpointConfig directory savedStates tailLimit cadence =
    ReplayCheckpointConfig
        { replayCheckpointDirectory = directory
        , replayCheckpointTailLimit = tailLimit
        , replayCheckpointCadence = cadence
        , replayCheckpointSaveState =
            \checkpoint state ->
                modifyIORef' savedStates
                    $ Map.insert
                        (replayCheckpointPoint checkpoint)
                        state
        , replayCheckpointLoadState =
            \checkpoint ->
                Map.lookup (replayCheckpointPoint checkpoint)
                    <$> readIORef savedStates
        }

advanceReplayEpoch :: ReplayState -> Block -> IO ReplayState
advanceReplayEpoch state block =
    pure state{replayStateLastEpoch = syntheticBlockSlot block}

expectProgress
    :: String
    -> ProgressOrRewind point tip block
    -> IO (Follower point tip block)
expectProgress context =
    \case
        Progress follower ->
            pure follower
        Rewind _ _ ->
            fail $ "expected progress for " <> context <> ", got rewind"
        Reset _ ->
            fail $ "expected progress for " <> context <> ", got reset"

expectReset :: String -> ProgressOrRewind point tip block -> IO ()
expectReset context =
    \case
        Progress _ ->
            fail $ "expected reset for " <> context <> ", got progress"
        Rewind _ _ ->
            fail $ "expected reset for " <> context <> ", got rewind"
        Reset _ ->
            pure ()

fetchedAt :: Word64 -> Fetched
fetchedAt slot =
    Fetched
        { fetchedPoint = headerPointAt slot
        , fetchedBlock = syntheticBlock slot
        , fetchedTip = Network.SlotNo slot
        }

unusedTip :: Network.SlotNo
unusedTip =
    Network.SlotNo 999

headerPointAt :: Word64 -> HeaderPoint
headerPointAt slot =
    Network.BlockPoint (Network.SlotNo slot) (unsafeCoerce ())

syntheticBlock :: Word64 -> Block
syntheticBlock =
    unsafeCoerce

syntheticBlockSlot :: Block -> Word64
syntheticBlockSlot =
    unsafeCoerce
