module Cardano.StakeCSMT.Ledger.ConfigSpec
    ( spec
    ) where

import Cardano.StakeCSMT.Ledger.Config
    ( LedgerConfigBundle (..)
    , ledgerConfigEpochAt
    , ledgerConfigPathsFromDirectory
    , loadLedgerConfig
    )
import Control.Exception
    ( evaluate
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec =
    describe "Ledger.Config.loadLedgerConfig"
        $ it "loads devnet genesis and exposes epoch zero without networking"
        $ do
            bundle <-
                loadLedgerConfig
                    $ ledgerConfigPathsFromDirectory
                        "test/fixtures/devnet-genesis"

            _ <- evaluate $ ledgerConfigProtocolInfo bundle
            _ <- evaluate $ ledgerConfigGenesisState bundle
            _ <- evaluate $ ledgerConfigLedgerConfig bundle
            _ <- evaluate $ ledgerConfigTopLevelConfig bundle
            _ <- evaluate $ ledgerConfigEraHistory bundle

            epoch <- ledgerConfigEpochAt bundle 0
            epoch `shouldBe` 0
