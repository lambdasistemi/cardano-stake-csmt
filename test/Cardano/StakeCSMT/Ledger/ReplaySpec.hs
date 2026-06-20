module Cardano.StakeCSMT.Ledger.ReplaySpec
    ( spec
    ) where

import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle (..)
    , ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Cardano.StakeCSMT.Ledger.Replay
    ( EpochTransition (..)
    , ReplayState (..)
    , initialReplayState
    , observeEpochTransition
    )
import Data.IORef
    ( modifyIORef'
    , newIORef
    , readIORef
    )
import Test.Hspec
    ( Spec
    , describe
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

loadDevnetBundle :: IO LedgerConfigBundle
loadDevnetBundle =
    loadLedgerConfig
        $ ledgerConfigPathsFromDirectory
            "test/fixtures/devnet-genesis"
