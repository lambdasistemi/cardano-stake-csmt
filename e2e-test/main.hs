module Main
    ( main
    ) where

import Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , defaultConfig
    )
import Cardano.StakeCSMT.E2E.IndexerSpec qualified as IndexerSpec
import Cardano.StakeCSMT.E2E.ReplaySpec qualified as ReplaySpec
import Test.Hspec
    ( describe
    , hspec
    , it
    , shouldBe
    )

main :: IO ()
main =
    hspec $ do
        describe "cardano-stake-csmt executable scaffold"
            $ it "uses the default HTTP port"
            $ configPort defaultConfig
            `shouldBe` 8080
        IndexerSpec.spec
        ReplaySpec.spec
