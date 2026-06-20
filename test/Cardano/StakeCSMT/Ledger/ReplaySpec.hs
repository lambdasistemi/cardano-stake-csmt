module Cardano.StakeCSMT.Ledger.ReplaySpec
    ( spec
    ) where

import Cardano.Node.Client.N2C.ChainSync
    ( Fetched (..)
    )
import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle (..)
    , ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition (..)
    , ReplayFollowerConfig (..)
    , ReplayState (..)
    , initialReplayState
    , observeEpochTransition
    , runReplayFollowerWith
    )
import ChainFollower
    ( Follower (..)
    , Intersector (..)
    , ProgressOrRewind (..)
    )
import Data.IORef
    ( modifyIORef'
    , newIORef
    , readIORef
    )
import Ouroboros.Network.Block qualified as Network
import Ouroboros.Network.Magic
    ( NetworkMagic (..)
    )
import Ouroboros.Network.Point qualified as Network.Point
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
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
                        , fetchedTip = unusedTip
                        }
                unusedTip =
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
