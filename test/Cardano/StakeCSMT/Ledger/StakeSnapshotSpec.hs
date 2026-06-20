module Cardano.StakeCSMT.Ledger.StakeSnapshotSpec
    ( spec
    ) where

import Cardano.Ledger.Coin
    ( Coin (..)
    )
import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle (..)
    , ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot (..)
    , stakeSnapshotFromLedgerState
    )
import Data.Foldable
    ( fold
    )
import Data.Map.Strict qualified as Map
import Test.Hspec
    ( Spec
    , describe
    , expectationFailure
    , it
    , shouldBe
    )

spec :: Spec
spec =
    describe "Ledger.StakeSnapshot"
        $ it
            "extracts the decoded devnet genesis mark stake without reconstructing genesis delegation"
        $ do
            bundle <-
                loadLedgerConfig
                    $ ledgerConfigPathsFromDirectory
                        "test/fixtures/devnet-genesis"

            case stakeSnapshotFromLedgerState
                $ ledgerConfigGenesisState bundle of
                Left err ->
                    expectationFailure
                        $ "expected stake snapshot, got "
                            <> show err
                Right StakeSnapshot{..} -> do
                    stakeSnapshotStake `shouldBe` Map.empty
                    stakeSnapshotTotalStake
                        `shouldBe` Coin 0
                    stakeSnapshotTotalStake
                        `shouldBe` fold (Map.elems stakeSnapshotStake)
