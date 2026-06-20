module Main
    ( main
    ) where

import Cardano.StakeCSMT.Application.Run.Config
    ( RuntimeConfig (..)
    , defaultConfig
    )
import Test.Hspec
    ( describe
    , hspec
    , it
    , shouldBe
    )

main :: IO ()
main =
    hspec
        $ describe "cardano-stake-csmt executable scaffold"
        $ it "uses the default HTTP port"
        $ configPort defaultConfig
        `shouldBe` configPort expectedConfig
  where
    expectedConfig :: RuntimeConfig
    expectedConfig = RuntimeConfig{configPort = 8080}
